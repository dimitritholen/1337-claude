---
name: implement
description: Implement a piece of work from a plan, a spec or a set of tickets, one task at a time with review between steps. Use on /1337:implement, or when the user wants a planned change built end to end. `--one` builds a single task and stops, so the user can /clear before the next.
argument-hint: "[--one]"
disable-model-invocation: true
---

Work the open tasks of the plan one at a time, in dependency order:
`tasqx_list_tasks` under the project (`tasqx_list_projects`) if the plan lives
there, else the `plans/` file.

`$ARGUMENTS` picks the scope. With `--one` (or the bare word `one` or
`single`), run single-ticket mode: take the first open, unblocked task exactly
as the loop would, run the full cycle below for it, retry and diagnose rules
included, then stop without starting the next task. End the reply with exactly
one line:

`Ticket <id> done. Next: <id> <title> — run /clear, then /1337:implement --one.`

When no open task remains, say the plan is done instead. This keeps the
orchestrator's context from growing across tickets, and the next run resumes
from tasqx or the plan file, so nothing needs to survive the /clear. Anything
else in `$ARGUMENTS`, or nothing, runs the loop over every open task.

For each task:

1. `tasqx_start_timer` and annotate the approach.
2. Pick the tier and dispatch:
   - Tiered mode: run `skills/tier/route.py` once for the step, exactly as
     `hooks/tiered.md` shows:
     ```bash
     python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <<'EOF'
     {"task": "<the task in one or two lines>",
      "steps": [{"id": 1, "title": "<step>", "brief": "<files, the change>"}]}
     EOF
     ```
     then dispatch `1337:builder` at the tier it printed.
   - Otherwise, pick the tier yourself per `hooks/orchestrator.md`'s ladder
     (haiku/sonnet/opus).
   The builder brief asks for `/1337:tdd` red-green-refactor.
3. Verify with `1337:checker`.
4. `git diff`, then `/1337:review` in spec mode against the task's spec.
5. Annotate what was delivered.
6. Commit the task.

On checker `FAIL`: retry once, one tier up from the routed/chosen tier, never
twice, never for a step already at Opus; if it fails again, stop and hand off
to `/1337:diagnose`.

Never `tasqx_complete_task` without the user's acceptance.

One routing call licenses exactly as many builder dispatches as it routed
steps — route each task on its own rather than batching several under one
call. Review the diff before moving to the next task; nothing after a
dispatch skips straight to another dispatch or a commit.

Outside orchestrator mode, run this same loop yourself in the main session
instead of dispatching. Tiered and orchestrator mode are separate switches
(`hooks/lib/mode.sh`), so the `route.py` step in 2 still applies whenever
tiered mode is on; without it, pick the tier yourself.
