# Orchestrator mode

Keeps the main session as a planner and pushes reading, coding and
verifying to cheaper subagents.

Off by default. When on, the main session only plans, dispatches and reviews:

| Agent | Model | Job |
|---|---|---|
| `1337:scout` | Haiku | Read-only lookups, answered with `path:line` |
| `1337:builder` | Chosen per step (Haiku, Sonnet or Opus) | Implements one step |
| `1337:checker` | Haiku | Runs tests, build and lint; reports `PASS` or `FAIL` |

A failed check goes back to the builder once, one model tier up. The main
session consumes maps, never payloads: ripwire output, subagent reports, git
metadata and test results, never a repository file's contents, through any
tool or route. Bash that dumps file contents (`cat`, `head`, `sed -n`, a
pathless `rg`/`grep -r`, `cp`/`mv` out of the tree, an inline interpreter
opening a file, `git show <rev>:<path>`, `git cat-file`, `git grep`) is
refused outright — every `git diff` form stays allowed. Code discovery goes
through `ripwire <dir> --for="..."` (then `--expand=SYM`, `--callers=`/
`--impact=`/`--uses=SYM`, `--grep=STR`); anything else, or the file contents
themselves, goes to `1337:scout`. A second hook refuses main-session edits
over 20 lines and new files outside `~/.claude` and temp directories —
including Bash redirects, `tee` and `sed -i` — past 3 small edits per
session (`CLAUDE_1337_EDIT_CAP`; ripwire's own symbol edit draws on the same
budget), so larger or further changes go through `1337:builder`.

## Read cap

Two counters per turn in the main session, both 0 by default
(`CLAUDE_1337_READ_CAP`, `CLAUDE_1337_GREP_CAP`): 0 refuses every call of
that kind, `off` disables it, a positive integer allows that many. The read
kind is the Read tool, WebFetch, the codebase-memory MCP reads
(`get_code_snippet`, `search_code`, `search_graph`) and any Bash command
with a segment that reads a file (`cat`, `head`, `tail`, `sed -n`, `rg`,
`grep`/`awk`/`jq` over a path, `git show`, `git cat-file`, `git grep`); a
stdin filter such as `ps aux | grep x` does not count. The grep kind is Grep
and Glob. The count resets each turn and subagents are exempt, apart from a
one-time nudge toward ripwire on their first Grep or Glob. A refusal routes
the same way as the guard: ripwire for code, a `1337:scout` dispatch for
anything else. Test: `tests/read-cap.test.sh`, run by `tests/run-all.sh`.

## Turn it on

Pick one:

- **At install:**
  ```bash
  claude plugin install 1337@1337-claude --config orchestrator=true
  ```
- **When enabling:** Claude Code asks for the `orchestrator` option when the plugin
  is enabled. Answer `true`.
- **Later:** change the plugin's `orchestrator` row in `/config` (Claude Code
  2.1.269 or later), or set it in `~/.claude/settings.json`:
  ```json
  {
    "pluginConfigs": {
      "1337@1337-claude": { "options": { "orchestrator": true } }
    }
  }
  ```
- **For one session, or with `--plugin-dir`** (where option values do not persist):
  ```bash
  CLAUDE_1337_ORCHESTRATOR=1 claude --plugin-dir ~/projects/1337-claude
  ```

Start a new session after changing it. The rules and the edit guard load at
session start.

## Optional: cheaper built-in agents

A plugin cannot set environment variables. To also run built-in agents such as
`general-purpose` on Haiku, add this to `~/.claude/settings.json` yourself:

```json
{ "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "haiku" } }
```

Agents that set their own `model`, including the three above, are not affected.

[Back to README](../README.md)
