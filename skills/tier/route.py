#!/usr/bin/env python3
"""Assign a model tier to each step of a plan by asking Jev, TypeSafe's
decision model, one Choice question per step.

Input: JSON on stdin (or a file path as the only argument):

    {"task": "<the whole task in a line or two>",
     "steps": [{"id": 1, "title": "...", "brief": "...",
                "previous_attempt": {"tier": "sonnet", "outcome": "..."}},
               ...]}

At most five steps, and ids (when given) must be unique; a step without an
id falls back to its position. `previous_attempt` is optional; when given,
its `tier` must be one of "haiku", "sonnet", "opus".

An optional top-level `"model"` field forces every step to one tier, no Jev
call and no key needed: "haiku", "sonnet" or "opus", case-insensitive.
CLAUDE_1337_TIER_MODEL and then CLAUDE_PLUGIN_OPTION_TIER_MODEL (the /config
option) are the same override from the environment; first one set wins.
"off" or empty means no override. Under an override the output gains a
top-level `"override"` key and every step comes back with confidence 1.0,
unescalated, `previous_attempt` ignored.

Output: JSON on stdout, one entry per step in input order:

    {"model": "jev-1.12",
     "floor": 0.6,
     "steps": [{"id": 1, "tier": "sonnet", "confidence": 0.71,
                "probabilities": {"haiku": 0.2, "sonnet": 0.7, "opus": 0.1},
                "escalated": false}, ...]}

A step whose confidence falls under the floor is escalated one tier, because
an uncertain "haiku" is a retry waiting to happen. The floor is 0.6 unless
CLAUDE_1337_TIER_FLOOR says otherwise. The API timeout is 20 seconds by default;
CLAUDE_1337_TIER_TIMEOUT overrides it (in seconds, as a float; unparseable or
non-positive values fall back to 20).

Needs a stored OpenRouter or TypeSafe key (see lib/keys.py: the
environment, then ~/.config/1337/credentials). Exit codes: 0 routed, 2 bad
input, 3 no key, 4 the API call failed. Every failure prints one line on
stderr so the skill can fall back to sizing by hand.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from lib import jev, keys  # noqa: E402

TIERS = ["haiku", "sonnet", "opus"]
DEFAULT_FLOOR = 0.6

# The contrastive question design that won the live eval in
# tools/tier-eval.py (accuracy 0.867 vs. 0.667, under-route 6.7% vs. 30%,
# identical over 2 runs): each tier gets what it is
# for, what it is explicitly not for, and worked examples, instead of one
# descriptive sentence. Module-level so tools/tier-eval.py imports it rather
# than keeping its own copy.
CRITERIA = {
    "haiku": {
        "what": "Mechanical execution along a path that already exists: "
                "renames, moves, config edits, CRUD copied from a sibling, "
                "boilerplate, running checks.",
        "not_for": "A step that introduces a new shape, decision or surface, "
                   "even a small one.",
        "examples": [
            "rename a helper and update its call sites",
            "add a CLI flag that maps straight to an existing internal option",
            "bump a pinned dependency version",
        ],
    },
    "sonnet": {
        "what": "Pattern-following with judgment: a new endpoint or "
                "component shaped like its neighbours, a straightforward "
                "test, a small refactor.",
        "not_for": "Either a step so mechanical it needs no judgment, or "
                   "one whose hard part is genuinely unclear.",
        "examples": [
            "add a new REST endpoint next to three existing ones",
            "write unit tests for an existing function",
            "extract a duplicated block into a helper",
        ],
    },
    "opus": {
        "what": "Reasoning-heavy: new architecture, tricky algorithms, "
                "concurrency, security-sensitive paths, or a step that "
                "already failed at a lower tier.",
        "not_for": "A step whose shape is already decided elsewhere and "
                   "only needs following.",
        "examples": [
            "design the locking strategy for concurrent writers",
            "add an auth check to a sensitive endpoint",
            "retry a step that failed as sonnet",
        ],
    },
}


def instructions(key):
    """The Choice instructions for one step's question. Module-level so
    tools/tier-eval.py's "current" variant imports it rather than keeping
    its own copy."""
    return (
        f"Which model tier fits `steps.{key}` best, as part of `task`? "
        f"When `steps.{key}.previous_attempt` is present, weigh its outcome."
    )


def fail(code, message):
    print(f"tier-route: {message}", file=sys.stderr)
    # Failure marker for hook lookup, same spirit as the success marker
    # below but its own prefix: neither grep can match the other, not even
    # as a substring (hooks/route-guard.sh tells exit 2 -- bad input, fix
    # and route again -- from exit 3/4 -- routing unavailable, size by hand
    # -- by this line alone).
    print(f'1337-tier-failed: {json.dumps({"exit": code}, separators=(",", ":"))}',
          file=sys.stderr)
    sys.exit(code)


def read_input(argv):
    try:
        raw = open(argv[1]).read() if len(argv) > 1 else sys.stdin.read()
        data = json.loads(raw)
    except (OSError, ValueError) as e:
        fail(2, f"input is not JSON: {e}")

    task = data.get("task") if isinstance(data, dict) else None
    steps = data.get("steps") if isinstance(data, dict) else None
    model_override = data.get("model") if isinstance(data, dict) else None
    if not isinstance(task, str) or not task.strip():
        fail(2, 'input needs a non-empty "task" string')
    if not isinstance(steps, list) or not steps:
        fail(2, 'input needs a non-empty "steps" list')
    if len(steps) > 5:
        fail(2, f"{len(steps)} steps is more than five: split into subtasks first")
    for i, step in enumerate(steps):
        if not isinstance(step, dict) or not step.get("title"):
            fail(2, f'steps[{i}] needs a "title"')
        previous_attempt = step.get("previous_attempt")
        if previous_attempt is not None:
            if not isinstance(previous_attempt, dict) or previous_attempt.get("tier") not in TIERS:
                fail(2, f'steps[{i}].previous_attempt.tier must be one of {TIERS}')
    seen_ids = set()
    for step in steps:
        step_id = step.get("id")
        if step_id is None:
            continue
        if step_id in seen_ids:
            fail(2, f"duplicate step id: {step_id!r}")
        seen_ids.add(step_id)
    return task, steps, model_override


def escalate(tier):
    return TIERS[min(TIERS.index(tier) + 1, len(TIERS) - 1)]


def resolve_override(input_override):
    """A forced-tier override that skips Jev entirely: every step runs on
    the one tier named here. First source that is set wins, whatever its
    value: the input's own top-level "model" field, then
    CLAUDE_1337_TIER_MODEL, then CLAUDE_PLUGIN_OPTION_TIER_MODEL (the
    /config option, added later). "off" or empty means no override --
    route through Jev as usual. Anything else must be a bare tier name
    (case- and whitespace-insensitive, like a Jev answer); anything else
    fails the same way a bad previous_attempt.tier does."""
    for source, raw in (
        ('the input\'s "model" field', input_override),
        ("CLAUDE_1337_TIER_MODEL", os.environ.get("CLAUDE_1337_TIER_MODEL")),
        ("CLAUDE_PLUGIN_OPTION_TIER_MODEL", os.environ.get("CLAUDE_PLUGIN_OPTION_TIER_MODEL")),
    ):
        if raw is None:
            continue
        if not isinstance(raw, str):
            fail(2, f"{source} must be a string, got {raw!r}")
        value = raw.strip().lower()
        if value in ("", "off"):
            return None
        if value not in TIERS:
            fail(2, f'{source} must be one of {TIERS} or "off", got {raw!r}')
        return value
    return None


def main(argv):
    task, steps, input_override = read_input(argv)
    override = resolve_override(input_override)

    if override is None:
        try:
            jev.transport()
        except keys.MissingKey:
            fail(3, "no key: run /1337:visual setup once, or export "
                    "OPENROUTER_API_KEY (or TYPESAFE_API_KEY)")
        except keys.UnsafeFile as e:
            fail(3, str(e))

    floor_raw = os.environ.get("CLAUDE_1337_TIER_FLOOR", str(DEFAULT_FLOOR))
    try:
        floor = float(floor_raw)
    except ValueError:
        fail(2, f"CLAUDE_1337_TIER_FLOOR must be a number between 0 and 1, got {floor_raw!r}")
    if not 0.0 <= floor <= 1.0:
        fail(2, f"CLAUDE_1337_TIER_FLOOR must be between 0 and 1, got {floor}")

    timeout_raw = os.environ.get("CLAUDE_1337_TIER_TIMEOUT", "20.0")
    try:
        timeout = float(timeout_raw)
        if timeout <= 0:
            timeout = 20.0
    except ValueError:
        timeout = 20.0

    if override is not None:
        # No Jev call at all: every step is forced to the override tier,
        # full confidence, never escalated, previous_attempt ignored.
        reported_model = "override"
        routed = [
            {
                "id": step.get("id", i + 1),
                "tier": override,
                "confidence": 1.0,
                "probabilities": {t: (1.0 if t == override else 0.0) for t in TIERS},
                "escalated": False,
            }
            for i, step in enumerate(steps)
        ]
    else:
        # Every step goes into one state so each question can name its own
        # step and still see the others: the same rename is haiku in a
        # script and sonnet next to a public API.
        step_keys = [f"step_{i}" for i in range(len(steps))]
        steps_state = {}
        for key, step in zip(step_keys, steps):
            entry = {"title": step["title"], "brief": step.get("brief", "")}
            if step.get("previous_attempt"):
                entry["previous_attempt"] = step["previous_attempt"]
            steps_state[key] = entry
        state = {"task": task, "steps": steps_state}
        questions = {key: jev.choice(instructions(key), CRITERIA) for key in step_keys}

        try:
            response = jev.decide(state, questions, timeout=timeout)
        except jev.JevError as e:
            fail(4, f"Jev call failed: {e}")
        if not response.get("model"):
            fail(4, f"Jev response had no model: {response!r}")
        reported_model = response["model"]

        routed = []
        for key, step in zip(step_keys, steps):
            answer = response["answers"][key]
            if not isinstance(answer, dict):
                fail(4, f"Jev answered {key} with {answer!r}, not an answer object")
            tier = answer.get("choice")
            if isinstance(tier, str):
                tier = tier.strip().lower()
            if tier not in TIERS:
                fail(4, f"Jev answered {key} with {answer.get('choice')!r}, not one of {TIERS}")
            raw_confidence = answer.get("confidence")
            if raw_confidence is None:
                print(f"tier-route: {key} came back with no confidence; not escalating it",
                      file=sys.stderr)
                confidence = None
                escalated = False
            else:
                try:
                    confidence = float(raw_confidence)
                except (TypeError, ValueError):
                    fail(4, f"Jev answered {key} with a non-numeric confidence: {raw_confidence!r}")
                escalated = confidence < floor and tier != TIERS[-1]
            if escalated:
                tier = escalate(tier)
            probabilities = answer.get("probabilities") or {}
            routed.append(
                {
                    "id": step.get("id", step_keys.index(key) + 1),
                    "tier": tier,
                    "confidence": round(confidence, 3) if confidence is not None else None,
                    "probabilities": {
                        t: round(float(probabilities.get(t, 0.0)), 3) for t in TIERS
                    },
                    "escalated": escalated,
                }
            )

    main_output = {"model": reported_model, "floor": floor, "steps": routed}
    if override is not None:
        main_output["override"] = override
    json.dump(main_output, sys.stdout)
    print()

    # Print the marker line for hook lookup: compact JSON, no probabilities.
    marker_steps = [
        {
            "id": step["id"],
            "tier": step["tier"],
            "confidence": step["confidence"],
            "escalated": step["escalated"],
        }
        for step in routed
    ]
    marker = {
        "model": reported_model,
        "floor": floor,
        "steps": marker_steps,
    }
    if override is not None:
        marker["override"] = override
    print(f"1337-tier-route: {json.dumps(marker, separators=(',', ':'))}")


if __name__ == "__main__":
    main(sys.argv)
