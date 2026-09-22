# CLAUDE.md

This repo is the source of the `1337` Claude Code plugin. Everything here must
work when the plugin is installed and used in any folder, not only this one.

## Layout

- `.claude-plugin/plugin.json`: plugin manifest; the name `1337` gives every
  skill the `/1337:` prefix.
- `.claude-plugin/marketplace.json`: makes this repo the `1337-claude` marketplace,
  so the plugin installs as `1337@1337-claude`.
- `skills/<name>/SKILL.md`: one folder per skill.
- `lib/keys.py` + `lib/jev.py`: stdlib-only helper every script that talks
  to Jev imports (`sys.path.insert(0, <plugin root>)`, then `from lib import
  keys, jev`). `keys.get(NAME)` reads the environment, then
  `~/.config/1337/credentials` (0600, `NAME=value` lines; path override
  `CLAUDE_1337_CREDENTIALS`); `keys.set` writes it. `jev.decide(state,
  questions, timeout=...)` posts to TypeSafe direct when `TYPESAFE_API_KEY`
  exists, else to OpenRouter's decisions endpoint with `OPENROUTER_API_KEY`;
  one retry on 408/429/5xx after at most a second. Test: `tests/lib.test.sh`
  (stand-in server, no key).
- `skills/visual/setup-key.py`: one-time OpenRouter key onboarding. OAuth
  PKCE against `openrouter.ai/auth` with a callback server on 127.0.0.1, a
  nonce-guarded paste page for when the callback cannot reach this machine,
  `--tty` for a hidden prompt; checks the key at `/api/v1/key`, stores it
  through `lib/keys.set`, never prints it. Test: `tests/setup-key.test.sh`
  (stand-in OpenRouter, no browser).
- `skills/visual/route.py`: UserPromptSubmit hook (wired in
  `hooks/hooks.json`, 10-second timeout). Silent unless the prompt hits a
  word prefilter and an OpenRouter key is stored; then one Jev Choice for
  the modality, one over the six cheapest catalogue models, and
  additionalContext telling Claude to ask with AskUserQuestion (Jev's pick
  first and Recommended, prices in every label, stay-with-Claude last) and
  run generate.py. `CLAUDE_1337_VISUAL=0` disables. Test:
  `tests/visual-route.test.sh` (stand-in Jev and catalogue).
- `skills/visual/generate.py`: makes the file once a model is chosen:
  raster and vector through chat completions with the image modality
  (extension from the data URL's media type, so Recraft vector gives
  `.svg`), video through the async videos job, speech through the audio
  endpoint. Writes `--out` or `assets/<slug>.<ext>`, never overwrites,
  prints path and cost. Exit 3 no key, 4 API failure, 5 failed video job.
  Test: `tests/generate.test.sh` (stand-in OpenRouter).
- `skills/visual/catalogue.py`: `models(modality)` lists OpenRouter's
  generation models for `raster_image`, `vector_svg`, `video` or `speech`
  with one price and unit each (image token, second or video token,
  character), cheapest first, live on every call. Test:
  `tests/catalogue.test.sh` (fixture JSON shaped like the live lists).
- `skills/tier/route.py`: python3 script that asks Jev, TypeSafe's decision
  model, for the model tier per plan step through `lib/jev.py`. Needs a
  stored OpenRouter or TypeSafe key. Test: `tests/tier-route.test.sh`
  (stand-in API, no key).
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
  `hooks/orchestrator.md` at SessionStart and refuses large main-session
  edits and Bash file writes (redirects, heredocs, `tee`, `sed -i`).
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
