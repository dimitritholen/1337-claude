<p align="center">
  <img src="assets/logo.svg" alt="1337" width="360">
</p>

# 1337

> My personal experimentation repo for Claude Code. This is where I test new
> workflows and prompts, hooks, output styles, token optimization and anything
> else an agent might do differently.

A Claude Code plugin with eight output styles, always-on
evaluate-before-you-build, name-your-assumptions and proactive-teammate
rules, and an opt-in orchestrator mode that routes work to cheaper models.

## The voices

Pick one with `/output-style`. Every voice ships the same engineering —
styles change how Claude talks, never what it does. Asked
*"why is my loop slow?"*, you get:

| Style | The voice | Answer |
|---|---|---|
| `1337:l33t` | Smug elite hacker in leet-speak | O(n²) l0l. u5e 4 537. |
| `1337:unc` | Out-of-touch older guy explaining in plain words (and the odd ASCII picture) | You're searching the whole list once for every item, sport, so 1,000 items means a million peeks. A set remembers where things are, so it's one peek. Da bomb. |
| `1337:tremendous` | Hype-man who calls every fix the greatest in history | Nested loop. A disaster, frankly. A set fixes it, the best fix, everybody says so. |
| `1337:silent` | No persona, answers only | You search the whole list per item: 1,000 items, a million comparisons. |
| `1337:hippy` | Mellow flower child who wants the diff to stay small | Heavy, man — you walk the whole list once per item, a million steps. A set remembers where things are. One look, and it knows. |
| `1337:pimp` | 1970s jive-talking movie hustler | Jive turkey move, that nested loop — a thousand items means a million looks. A set, baby: one look and it's done. Can you dig it? |
| `1337:surfer` | Sun-bleached surfer who reads code like swell | Kook move, dude — that loop paddles the same stretch a thousand times. A set rides it once. So clean. |
| `1337:yoda` | Tiny green master, inverted syntax in the asides | A million times through the list, you go. A set — once, it looks, and it remembers. Use it, you will. |

The substance is identical under all eight:

```python
seen = set(items)
```

The voice lives in the connective tissue — openers, transitions, caveats,
closers — never in the answer, and never in code, commands or warnings.

## Install

```bash
claude plugin marketplace add dimitritholen/1337-claude
claude plugin install 1337@1337-claude
```

Or load it straight from a checkout:

```bash
claude --plugin-dir ~/projects/1337-claude
```

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
- `/1337:audit` — audits a whole repo or module for over-engineering that is
  alive and in use: speculative generality, pass-through layers, frameworks
  where a function would do. Read-only.
- `/1337:tier` — splits a task into builder-sized steps and assigns the
  cheapest model tier per step (Haiku/Sonnet/Opus) for dispatch. Read-only.
- `/1337:plan` — turns a request into the smallest plan that still reaches
  the goal: ordered, builder-sized steps with a done check each, recorded as
  tasqx tasks when the tasqx MCP tools are present, else as
  `plans/<slug>.md`. Writes the plan only, never code.

The rules reach the workers too: a SubagentStart hook injects a compact
digest (minimum-work ladder, assumptions discipline, tight replies) into
every spawned subagent. `CLAUDE_1337_SUBAGENT_MATCHER` scopes it by agent
type, `CLAUDE_1337_SUBAGENT_RULES=0` disables.

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
directories — including Bash redirects, heredocs, `tee` and `sed -i`, which is
how an agent will actually try to write a file — so larger changes go through
`1337:builder`.

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
tests/subagent-rules.test.sh
tests/rule-copies.test.sh
```

The session rules (evaluate, assumptions, proactive teammate) are checked by an
eval suite in `evals/`, run with and without the plugin so each case shows
whether the rule changes behaviour. It spends real tokens (about $1.20 for one
run per case):

```bash
claude plugin eval . --runs 1
```
