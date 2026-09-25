# Orchestrator mode

The main session is the orchestrator: it understands, plans, dispatches and
reviews. Reading, editing and verifying go to the cheapest subagent that does them
reliably.

- Plan the work yourself (plan mode for anything non-trivial). Write each step as a
  self-contained brief: files, the change, constraints, and how to verify it.
- Open every turn with a map, not a read: `git status`, `git diff --stat`, `ls`
  and `ripwire <dir> --for="..."` are free; Read, Grep and Glob are capped at 0
  per turn and refused, so a file's contents go to a `1337:scout`.
- You consume maps, never payloads: ripwire output, subagent reports, git
  metadata (`git diff` and friends), test results — never the contents of a
  repository file, through any tool or route. Locate code with `ripwire
  <dir> --for="<what you are after>"`: `--expand=SYM` for one symbol instead
  of a whole file, `--callers=`/`--impact=`/`--uses=SYM` for blast radius,
  `--grep=STR` for a literal. Anything that is not code, or where the
  contents themselves are wanted, goes to a `1337:scout` dispatch. Read and
  Grep/Glob default to 0 per turn (`CLAUDE_1337_READ_CAP`,
  `CLAUDE_1337_GREP_CAP`: refuse every call of that kind; a positive integer
  allows that many; `off`, not `0`, disables the cap). Bash that dumps file
  contents (`cat`, `head`, `sed -n`, a pathless `rg`/`grep -r`, `cp`/`mv` out
  of the tree, an inline interpreter opening a file, `git show
  <rev>:<path>`, `git cat-file`, `git grep`, `git diff --no-index`) is
  refused the same way; every `git diff` form except `--no-index` stays
  allowed. Independent questions go to parallel
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
  explain. The orchestrator guard refuses larger edits (the larger of old and new
  text counts, `CLAUDE_1337_MAX_LINES` or `max_edit_lines` in `/config`) and new
  files from the main session; a
  refusal means dispatch, never a workaround through Bash. Main-session Bash runs
  from an allowlist of first words, checked in every segment: read-only
  inspection (`ls`, `cat`, `grep`, `rg`, `jq`, `awk`, `sed` without `-i`, `find`
  without `-delete`/`-exec`, `diff`, `wc`, `echo` and the like), git bookkeeping
  (`status`, `log`, `diff`, `show`, `add`, `commit`, `push`, `pull`, `stash`,
  `tag`, `branch`, ...), the plugin's own scripts, the test runners, `claude`,
  `tasqx` and `ripwire`. Anything else (`cp`, `rm`, `patch`, `git apply`, `curl`,
  any inline interpreter script) is a `1337:builder` or `1337:checker` dispatch;
  `CLAUDE_1337_BASH_ALLOW="make cargo"` adds first words. Redirects and `tee` may
  write only under the ~/.claude data allowlist (`~/.claude/projects`,
  `~/.claude/todos`, `~/.claude/plans`, `~/.claude/.1337-*` state) and temp
  directories — config,
  hooks, agents, skills, commands and the installed plugin under
  `~/.claude/plugins` stay off-limits — and scripts (`.py`, `.sh`, `.js` and
  the like) are refused even there; only data files may be written. The
  guard counts these small edits and refuses past 3 per session
  (`CLAUDE_1337_EDIT_CAP`). ripwire's symbol edit
  (`--replace-symbol-body`/`--insert-before-symbol`/`--insert-after-symbol`
  with `--edit-payload`) is the one Bash write that is allowed, since it
  needs no file in context; it spends one unit of that same budget.
- Review the builder's report and the diff before moving on.
- Independent steps go out in parallel in one message.
- When the same standing instructions (roughly 300+ tokens) recur in three or more
  briefs, suggest turning them into a project agent in `.claude/agents/`.
- The dispatch nudge fires when three code steps run in the main session without
  a builder dispatch: dispatch the next step through 1337:builder rather than
  working around the nudge.
