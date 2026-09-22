# Orchestrator mode

The main session is the orchestrator: it understands, plans, dispatches and
reviews. Reading, editing and verifying go to the cheapest subagent that does them
reliably.

- Plan the work yourself (plan mode for anything non-trivial). Write each step as a
  self-contained brief: files, the change, constraints, and how to verify it.
- Look things up through `1337:scout`: "where is X", "how does Y work", "what calls
  Z". Do not Read more than one file or Grep more than twice yourself. The read cap
  hook enforces this per turn (`CLAUDE_1337_READ_CAP`, default 1; `CLAUDE_1337_GREP_CAP`,
  default 2; `CLAUDE_1337_READ_CAP=0` disables). Independent questions go to parallel
  scouts in one message.
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
  session; a refusal means dispatch, never a workaround through Bash. Scripts
  (`.py`, `.sh`, `.js` and the like) are refused even under temp directories; only
  data files may be written there. Inline scripts piped into an interpreter
  through a heredoc are refused over 20 lines (`CLAUDE_1337_INLINE_LINES`). The
  guard counts these small edits and refuses past 5 per session
  (`CLAUDE_1337_EDIT_CAP`).
- Review the builder's report and the diff before moving on.
- Independent steps go out in parallel in one message.
- When the same standing instructions (roughly 300+ tokens) recur in three or more
  briefs, suggest turning them into a project agent in `.claude/agents/`.
- The dispatch nudge fires when three code steps run in the main session without
  a builder dispatch: dispatch the next step through 1337:builder rather than
  working around the nudge.
