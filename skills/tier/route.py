#!/usr/bin/env python3
"""Assign a model tier to each step of a plan by asking Jev, TypeSafe's
decision model, one Choice question per step.

Input: JSON on stdin (or a file path as the only argument):

    {"task": "<the whole task in a line or two>",
     "steps": [{"id": 1, "title": "...", "brief": "..."}, ...]}

At most five steps, and ids (when given) must be unique; a step without an
id falls back to its position.

Output: JSON on stdout, one entry per step in input order:

    {"model": "jev-1.12",
     "floor": 0.5,
     "steps": [{"id": 1, "tier": "sonnet", "confidence": 0.71,
                "probabilities": {"haiku": 0.2, "sonnet": 0.7, "opus": 0.1},
                "escalated": false}, ...]}

A step whose confidence falls under the floor is escalated one tier, because
an uncertain "haiku" is a retry waiting to happen. The floor is 0.5 unless
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

# The same wording as the Tiers section of SKILL.md, so the model and the
# reader judge steps by one rulebook.
CRITERIA = {
    "haiku": (
        "Mechanical: renames, moves, config edits, CRUD along an existing "
        "pattern, boilerplate, lookups, running checks."
    ),
    "sonnet": (
        "Pattern-following with judgment: a new endpoint or component "
        "matching existing conventions, straightforward tests, small refactors."
    ),
    "opus": (
        "Reasoning-heavy: new architecture, tricky algorithms, concurrency, "
        "security-sensitive paths, or a step that already failed at a lower tier."
    ),
}


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
    if not isinstance(task, str) or not task.strip():
        fail(2, 'input needs a non-empty "task" string')
    if not isinstance(steps, list) or not steps:
        fail(2, 'input needs a non-empty "steps" list')
    if len(steps) > 5:
        fail(2, f"{len(steps)} steps is more than five: split into subtasks first")
    for i, step in enumerate(steps):
        if not isinstance(step, dict) or not step.get("title"):
            fail(2, f'steps[{i}] needs a "title"')
    seen_ids = set()
    for step in steps:
        step_id = step.get("id")
        if step_id is None:
            continue
        if step_id in seen_ids:
            fail(2, f"duplicate step id: {step_id!r}")
        seen_ids.add(step_id)
    return task, steps


def escalate(tier):
    return TIERS[min(TIERS.index(tier) + 1, len(TIERS) - 1)]


def main(argv):
    task, steps = read_input(argv)

    try:
        jev.transport()
    except keys.MissingKey:
        fail(3, "no key: run /1337:visual setup once, or export "
                "OPENROUTER_API_KEY (or TYPESAFE_API_KEY)")
    except keys.UnsafeFile as e:
        fail(3, str(e))

    floor_raw = os.environ.get("CLAUDE_1337_TIER_FLOOR", "0.5")
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

    # Every step goes into one state so each question can name its own step
    # and still see the others: the same rename is haiku in a script and
    # sonnet next to a public API.
    step_keys = [f"step_{i}" for i in range(len(steps))]
    state = {
        "task": task,
        "steps": {
            key: {"title": step["title"], "brief": step.get("brief", "")}
            for key, step in zip(step_keys, steps)
        },
    }
    questions = {
        key: jev.choice(
            f"Which is the cheapest model tier that can build `steps.{key}` "
            "reliably in one go, as part of `task`? Cheap is the default; "
            "a higher tier must be earned by the hard part of the step.",
            CRITERIA,
        )
        for key in step_keys
    }

    try:
        response = jev.decide(state, questions, timeout=timeout)
    except jev.JevError as e:
        fail(4, f"Jev call failed: {e}")

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
            confidence = float(raw_confidence)
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

    main_output = {"model": response["model"], "floor": floor, "steps": routed}
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
        "model": response["model"],
        "floor": floor,
        "steps": marker_steps,
    }
    print(f"1337-tier-route: {json.dumps(marker, separators=(',', ':'))}")


if __name__ == "__main__":
    main(sys.argv)
