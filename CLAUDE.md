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
  `1337:tremendous`),
  chosen with `/output-style`. Each file stands alone and repeats the "Say as little as
  needed", plain-text and quality sections, since styles cannot include each other.
- `hooks/hooks.json` + `hooks/evaluate.md`: SessionStart hook that injects the
  evaluate-before-you-build, name-your-assumptions and proactive-teammate rules
  into every session.
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
