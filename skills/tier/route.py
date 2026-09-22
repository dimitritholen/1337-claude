#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["typesafe-sdk>=0.7,<1"]
# ///
"""Assign a model tier to each step of a plan by asking Jev, TypeSafe's
decision model, one Choice question per step.

Input: JSON on stdin (or a file path as the only argument):

    {"task": "<the whole task in a line or two>",
     "steps": [{"id": 1, "title": "...", "brief": "..."}, ...]}

Output: JSON on stdout, one entry per step in input order:

    {"model": "jev-1.12",
     "floor": 0.5,
     "steps": [{"id": 1, "tier": "sonnet", "confidence": 0.71,
                "probabilities": {"haiku": 0.2, "sonnet": 0.7, "opus": 0.1},
                "escalated": false}, ...]}

A step whose confidence falls under the floor is escalated one tier, because
an uncertain "haiku" is a retry waiting to happen. The floor is 0.5 unless
CLAUDE_1337_TIER_FLOOR says otherwise.

Needs TYPESAFE_API_KEY in the environment. Nothing else is read: no
credentials file, no config. Exit codes: 0 routed, 2 bad input, 3 no key,
4 the API call failed. Every failure prints one line on stderr so the skill
can fall back to sizing by hand.
"""

import json
import os
import sys

from typesafe_sdk import Choice, RetryPolicy, TypeSafeClient, TypeSafeError

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
    for i, step in enumerate(steps):
        if not isinstance(step, dict) or not step.get("title"):
            fail(2, f'steps[{i}] needs a "title"')
    return task, steps


def escalate(tier):
    return TIERS[min(TIERS.index(tier) + 1, len(TIERS) - 1)]


def main(argv):
    task, steps = read_input(argv)

    if not os.environ.get("TYPESAFE_API_KEY"):
        fail(3, "TYPESAFE_API_KEY is not set; export it and run again")

    floor = float(os.environ.get("CLAUDE_1337_TIER_FLOOR", "0.5"))

    # Every step goes into one state so each question can name its own step
    # and still see the others: the same rename is haiku in a script and
    # sonnet next to a public API.
    keys = [f"step_{i}" for i in range(len(steps))]
    state = {
        "task": task,
        "steps": {
            key: {"title": step["title"], "brief": step.get("brief", "")}
            for key, step in zip(keys, steps)
        },
    }
    questions = {
        key: Choice(
            instructions=(
                f"Which is the cheapest model tier that can build `steps.{key}` "
                "reliably in one go, as part of `task`? Cheap is the default; "
                "a higher tier must be earned by the hard part of the step."
            ),
            criteria=CRITERIA,
        )
        for key in keys
    }

    try:
        with TypeSafeClient(
            model=os.environ.get("TYPESAFE_DEFAULT_MODEL", "jev-latest"),
            base_url=os.environ.get("TYPESAFE_BASE_URL"),
            timeout=15.0,
            retry=RetryPolicy(max_retries=2),
        ) as client:
            response = client.system_one(state=state, questions=questions)
    except TypeSafeError as e:
        fail(4, f"Jev call failed: {e}")

    routed = []
    for key, step in zip(keys, steps):
        answer = response.answers[key]
        tier = answer.choice
        escalated = answer.confidence < floor and tier != TIERS[-1]
        if escalated:
            tier = escalate(tier)
        routed.append(
            {
                "id": step.get("id", keys.index(key) + 1),
                "tier": tier,
                "confidence": round(answer.confidence, 3),
                "probabilities": {
                    t: round(answer.probabilities.get(t, 0.0), 3) for t in TIERS
                },
                "escalated": escalated,
            }
        )

    json.dump({"model": response.model, "floor": floor, "steps": routed}, sys.stdout)
    print()


if __name__ == "__main__":
    main(sys.argv)
