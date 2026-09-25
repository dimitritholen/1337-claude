---
name: terse
description: Report the terse mode level that the verbosity governor enforces (off, on, hard) and where it is set. Use on /1337:terse, or when the user says replies are too long or chatty, to stop explaining so much, be terser, or keep answers short from now on.
---

You report the terse mode that `hooks/terse-governor.sh` and
`hooks/terse-rules.sh` read. One line, never write any file. On/hard also inject
rules at SessionStart, and over-budget replies are nudged next turn, not
blocked.

# Levels

- **off**: no reply budgets, no rules injected.
- **on**: budget 40 words per reply, code fences excluded. The default.
- **hard**: budget 12 words, one line. For when the codebase has wronged you.

The user asking why, how, or for an explanation lifts the budget for that
turn automatically; hard mode still expects the explanation itself to stay
tight around its substance.

# Action

Report the current level (from /config: `${user_config.terse}`, or the default
if unset). One line, e.g. `terse: hard (12 words, from /config)`.
`CLAUDE_1337_TERSE` beats /config for one shell; check it with `printenv CLAUDE_1337_TERSE`.

With an argument, say where to change it: the "Terse mode" row in `/config`,
or `CLAUDE_1337_TERSE=<level>` for one shell. Change nothing yourself.
