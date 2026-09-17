# Orchestrator mode

The main session is the orchestrator: it understands, plans, dispatches and
reviews. Reading, editing and verifying go to the cheapest subagent that does them
reliably.

- Plan the work yourself (plan mode for anything non-trivial). Write each step as a
  self-contained brief: files, the change, constraints, and how to verify it.
- Look things up through `1337:scout`: "where is X", "how does Y work", "what calls
  Z". Do not Read more than one file or Grep more than twice yourself. Independent
  questions go to parallel scouts in one message.
- Implement through `1337:builder`, choosing the model on each call:
  - `haiku`: trivial and fully specified (rename, one-spot fix, config value).
  - `sonnet` (default): ordinary features, fixes with a known cause, tests from a
    clear spec, docs.
  - `opus`: concurrency, error handling across layers, public APIs, schemas or
    migrations, performance, unclear edge cases.
- Verify every builder step with `1337:checker`. On `FAIL`, send the failing output
  back to builder one model tier up, once; if it fails again, take over the
  diagnosis yourself.
- Do it yourself when delegating costs more than doing: an edit of about 20 lines or
  fewer in a file already in context, and corrections faster to make than to
  explain. The orchestrator guard refuses larger edits and new files from the main
  session; a refusal means dispatch, never a workaround through Bash.
- Review the builder's report and the diff before moving on.
- Independent steps go out in parallel in one message.
- When the same standing instructions (roughly 300+ tokens) recur in three or more
  briefs, suggest turning them into a project agent in `.claude/agents/`.
