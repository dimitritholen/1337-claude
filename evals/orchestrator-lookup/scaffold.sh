#!/usr/bin/env bash
set -euo pipefail
mkdir -p hooks

cat > hooks/route.py <<'PY'
#!/usr/bin/env python3
"""UserPromptSubmit hook: route a visual request to a generation model.

Reads the hook payload on stdin and stays silent (exit 0, no output)
unless the prompt matches the word prefilter below and a stored key is
found. On a match it asks a decision model what the prompt wants and, if
the answer's confidence clears the floor, offers a modality choice.

CLAUDE_1337_VISUAL_FLOOR moves the confidence floor (0.5 by default); see
SKILL.md for where else it can be set.
"""

import json
import os
import re
import sys

PREFILTER = re.compile(
    r"\b(image|images|logo|logos|svg|vector|video|videos|voice|voices)\b",
    re.IGNORECASE,
)
FLOOR = float(os.environ.get("CLAUDE_1337_VISUAL_FLOOR", "0.5"))


def find_key():
    return bool(os.environ.get("EXAMPLE_API_KEY"))


def route(prompt):
    if not PREFILTER.search(prompt):
        return None
    if not find_key():
        return None
    # A real routing call would go here; the fixture only demonstrates
    # the prefilter and the floor.
    return {"modality": "raster_image", "confidence": 0.9}


def main():
    try:
        payload = json.load(sys.stdin)
        prompt = payload.get("prompt") if isinstance(payload, dict) else None
    except ValueError:
        return 0
    if not isinstance(prompt, str):
        return 0
    result = route(prompt)
    if result and result["confidence"] >= FLOOR:
        json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                          "additionalContext": str(result)}}, sys.stdout)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

cat > SKILL.md <<'MD'
---
name: visual-fixture
description: Fixture skill for the orchestrator-lookup eval, documenting hooks/route.py.
---

# hooks/route.py

A `UserPromptSubmit` hook that stays silent unless a prompt matches the
word prefilter (`image`, `logo`, `svg`, `video`, `voice`, and their
plurals) and a key is stored.

## Confidence floor

Routing only fires when the decision's confidence clears
`CLAUDE_1337_VISUAL_FLOOR`, which defaults to `0.5`. Override it either as
an environment variable before the session starts, or per-run through the
`env` block of a case's `prompt.md`/`case.yaml` frontmatter (as this eval
suite itself does for other settings).
MD

if command -v git >/dev/null 2>&1; then
  git init -q
fi
