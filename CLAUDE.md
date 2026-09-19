# CLAUDE.md

This repo is the source of the `1337` Claude Code plugin. Everything here must
work when the plugin is installed and used in any folder, not only this one.

## Layout

- `.claude-plugin/plugin.json`: plugin manifest; the name `1337` gives every
  skill the `/1337:` prefix.
- `.claude-plugin/marketplace.json`: makes this repo the `1337-claude` marketplace,
  so the plugin installs as `1337@1337-claude`.
- `skills/<name>/SKILL.md`: one folder per skill.
- `output-styles/<name>.md`: a pack of voices (`1337:l33t`, `1337:unc`,
  `1337:tremendous`, `1337:silent`, `1337:hippy`, `1337:pimp`, `1337:surfer`,
  `1337:yoda`),
  chosen with `/output-style`. Each file stands alone and repeats the "Say as little as
  needed", plain-text and quality sections, since styles cannot include each other.
- `hooks/hooks.json` + `hooks/evaluate.md`: SessionStart hook that injects the
  evaluate-before-you-build, name-your-assumptions and proactive-teammate rules
  into every session. Behaviour checks: `evals/<case>/` (`claude plugin eval .`).
- `hooks/stop-review.sh`: Stop hook that once per session offers a
  `/1337:review` pass when the session diff adds 30+ lines
  (`CLAUDE_1337_REVIEW_NUDGE=0` opts out). Test: `tests/stop-review.test.sh`.
- `hooks/terse-governor.sh`: Stop hook that measures the last reply and blocks
  over-budget ones (mode in `~/.claude/.1337-terse`, set by `/1337:terse`;
  `CLAUDE_1337_TERSE=0|on|hard` overrides). Test:
  `tests/terse-governor.test.sh`.
- `hooks/subagent-rules.sh` + `hooks/subagent.md`: SubagentStart hook that
  injects a compact rule digest into every spawned subagent
  (`CLAUDE_1337_SUBAGENT_MATCHER` scopes by agent type,
  `CLAUDE_1337_SUBAGENT_RULES=0` disables). Test:
  `tests/subagent-rules.test.sh`.
- `tests/rule-copies.test.sh`: drift check that shared rule sentences (the
  brevity blocks, the build ladder, the never-cut rule) stay aligned across
  the hook copies, skills and styles.
- Orchestrator mode, opt-in via the `orchestrator` option in `plugin.json`
  `userConfig` (or `CLAUDE_1337_ORCHESTRATOR=1`): `agents/` holds `scout`,
  `builder` and `checker`; `hooks/orchestrator-guard.sh` injects
  `hooks/orchestrator.md` at SessionStart and refuses large main-session edits.
  Test: `tests/orchestrator-guard.test.sh`.

Behaviour that users should get goes in the plugin, never in this file.

## Try it locally

Run Claude with the plugin loaded straight from this folder, then pick the
style:

```bash
claude --plugin-dir ~/projects/1337-claude
```

Inside the session: `/output-style` and choose `1337:l33t`. After editing
plugin files, run `/reload-plugins` or restart.
