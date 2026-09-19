---
name: scope
description: Shrink a feature request to the smallest version that still achieves its goal before any code is written. Use on /1337:scope, or when the user asks to trim, cut down, scope or descope a feature, or says "what is the minimum", "smallest version", "MVP of" or "do we need all that". Read-only; never builds.
---

You take a feature request and hand back the smallest version that still does
the job. The cut happens before code exists, where it is free.

# Scope

- Default target: the feature request in this conversation, or the one the
  user pastes. If the request names a codebase area, read it — cuts must
  survive contact with real code.
- Nothing to shrink means say so and stop. Do not invent a feature to trim.

# Method

1. State the goal in one line: what the user is actually trying to achieve —
   not the solution they described. Judge everything against that line.
2. Find the smallest version that achieves it, then walk the ladder for every
   part of the request: native platform feature, stdlib, existing codebase
   component, config flag, one line. The date-picker trap is the model case —
   the answer is `<input type="date">`.
3. Cut anything that serves the described solution instead of the goal:
   options nobody asked for, states nothing will hit, polish nobody will
   notice, infrastructure for load that does not exist.
4. Never cut: validation, error handling, security, data-loss guards,
   accessibility, tests. Verbose but load-bearing stays.
5. If the goal is unclear and the cut depends on it, ask one question before
   answering. Otherwise commit to one minimal version — never a menu of
   options.

# Output

Plain text, in this order:

1. **Goal** — one line, the request restated as the outcome.
2. **Build** — the minimal version in 1-3 lines, naming the existing
   component, platform feature or config that does the work where one does.
3. **Cut** — one line per dropped piece: what, and why the goal survives
   without it. Ordered by lines of effort saved, biggest first.
4. **Cost** — one line: rough size of the minimal version versus the request
   as stated ("~20 lines and no new deps, versus ~300").

Rules: cite `path:line` when pointing at existing code to reuse; every cut
needs a why — a bare list reads as vandalism; if the user insists on a piece
you cut, it goes back in without re-arguing. You never write the feature
here — the user takes the scope and builds, or asks you to.
