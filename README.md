# 1337

A Claude Code plugin with three output styles (`1337:l33t`, `1337:unc`,
`1337:tremendous`), always-on evaluate-before-you-build and name-your-assumptions
rules, and an opt-in orchestrator mode that routes work to cheaper models.

## Install

```bash
claude plugin marketplace add dimitritholen/1337-claude
claude plugin install 1337@1337-claude
```

Or load it straight from a checkout:

```bash
claude --plugin-dir ~/projects/1337-claude
```

Pick a voice with `/output-style`.

## Orchestrator mode

Off by default. When on, the main session only plans, dispatches and reviews:

| Agent | Model | Job |
|---|---|---|
| `1337:scout` | Haiku | Read-only lookups, answered with `path:line` |
| `1337:builder` | Chosen per step (Haiku, Sonnet or Opus) | Implements one step |
| `1337:checker` | Haiku | Runs tests, build and lint; reports `PASS` or `FAIL` |

A failed check goes back to the builder once, one model tier up. A hook refuses
main-session edits over 20 lines and new files outside `~/.claude` and temp
directories, so larger changes go through `1337:builder`.

### Turn it on

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

Start a new session after changing it. The rules and the edit guard load at session
start.

### Optional: cheaper built-in agents

A plugin cannot set environment variables. To also run built-in agents such as
`general-purpose` on Haiku, add this to `~/.claude/settings.json` yourself:

```json
{ "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "haiku" } }
```

Agents that set their own `model`, including the three above, are not affected.

## Test

```bash
tests/orchestrator-guard.test.sh
```
