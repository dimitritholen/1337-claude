# 1337

> My personal experimentation repo for Claude Code. This is where I test new
> workflows and prompts, hooks, output styles, token optimization and anything
> else an agent might do differently.

A Claude Code plugin with eight output styles (`1337:l33t`, `1337:unc`,
`1337:tremendous`, `1337:silent`, `1337:hippy`, `1337:pimp`, `1337:surfer`,
`1337:yoda`) whose voices ride on every non-answer
sentence, always-on evaluate-before-you-build, name-your-assumptions
and proactive-teammate rules, and an opt-in orchestrator mode that routes work to cheaper models.

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

## Skills

- `/1337:review` — reviews the current diff (or a named branch/PR) for
  over-engineering and hands back a delete-list: what to cut and what existing
  code, stdlib or platform feature replaces it. Read-only.
- `/1337:assumptions` — audits a plan, spec or diff for unchecked assumptions
  that would flip the decision, each with what changes if it is wrong.
  Read-only.
- `/1337:scope` — shrinks a feature request to the smallest version that
  still achieves its goal, before any code exists. Read-only.
- `/1337:debt` — sweeps the repo for TODO markers, dead code, obsolete
  workarounds and stale dependencies; hands back a delete-ledger with
  evidence per line. Read-only.
- `/1337:tier` — splits a task into builder-sized steps and assigns the
  cheapest model tier per step (Haiku/Sonnet/Opus) for dispatch. Read-only.

After a session's diff grows past 30 added lines, a Stop hook offers one
`/1337:review` pass before the session ends — once per session, never runs it
unasked. Opt out with `CLAUDE_1337_REVIEW_NUDGE=0`.

## Terse mode

A Stop hook measures every reply: if it exceeds the word budget (code fences
excluded) and the user did not ask why, how or for an explanation, the reply
is blocked and resent as the answer only. On by default at 40 words;
`/1337:terse hard` tightens it to one line, `/1337:terse off` disables.
Levels persist in `~/.claude/.1337-terse`; `CLAUDE_1337_TERSE=0|on|hard`
overrides per session. Pair it with the `1337:silent` output style
(`/output-style`) for a no-persona, answers-only voice.

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
tests/stop-review.test.sh
tests/terse-governor.test.sh
```

The session rules (evaluate, assumptions, proactive teammate) are checked by an
eval suite in `evals/`, run with and without the plugin so each case shows
whether the rule changes behaviour. It spends real tokens (about $1.20 for one
run per case):

```bash
claude plugin eval . --runs 1
```
