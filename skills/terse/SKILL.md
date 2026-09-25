---
name: terse
description: Set or report the terse mode level that the verbosity governor enforces (off, on, hard). Use on /1337:terse, or when the user says replies are too long or chatty, to stop explaining so much, be terser, or keep answers short from now on.
---

You manage the terse mode flag that `hooks/terse-governor.sh` and
`hooks/terse-rules.sh` read. One-word confirmations only. On/hard also inject
rules at SessionStart, and over-budget replies are nudged next turn, not
blocked.

# Levels

- **off** — no reply budgets. The governor never blocks.
- **on** — budget 40 words per reply, code fences excluded. The default.
- **hard** — budget 12 words: one line. For when the codebase has wronged you.

The user asking why, how, or for an explanation lifts the budget for that
turn automatically; hard mode still expects the explanation itself to stay
tight around its substance.

# Actions

- No argument: read the mode file and report one line, e.g. `terse: on (40
  words)`. File path: `${CLAUDE_1337_TERSE_FILE:-$HOME/.claude/.1337-terse}`;
  missing file means `on`.
- `off`, `on` or `hard`: write that word to the mode file (a one-line file,
  `printf '%s\n' <mode> > <path>`), then confirm in one line, e.g.
  `terse: hard (12 words)`. The next turn enforces it; nothing else to
  reload.
- Anything else: say the three valid levels in one line, change nothing.

The `CLAUDE_1337_TERSE` environment variable overrides the file when set
(`0`/`off`, `on`, `hard`); mention that only if the user asks why a level
did not stick.
