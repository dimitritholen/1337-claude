---
max_turns: 15
allowed_tools: [Agent, Read, Grep, Glob, Bash]
env:
  EVAL_CLAUDE_1337_ORCHESTRATOR: "1"
---

This project has a UserPromptSubmit hook at `hooks/route.py`, with
`SKILL.md` documenting it. Which words does the prefilter match on before
it does anything else, what confidence floor does it apply before offering
the modality choice, and where can that floor be overridden?
