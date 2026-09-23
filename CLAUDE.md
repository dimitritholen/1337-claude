# CLAUDE.md

This repo is the source of the `1337` Claude Code plugin. Everything here must
work when the plugin is installed and used in any folder, not only this one.

## Layout

- `.claude-plugin/plugin.json`: plugin manifest; the name `1337` gives every
  skill the `/1337:` prefix.
- `.claude-plugin/marketplace.json`: makes this repo the `1337-claude` marketplace,
  so the plugin installs as `1337@1337-claude`.
- `skills/<name>/SKILL.md`: one folder per skill.
- `skills/visual/`: the visual routing set (`SKILL.md`, `setup-key.py`,
  `catalogue.py`, `route.py`, `generate.py`, `preview.py`), each described below.
- `lib/keys.py` + `lib/jev.py`: stdlib-only helper every script that talks
  to Jev imports (`sys.path.insert(0, <plugin root>)`, then `from lib import
  keys, jev`). `keys.get(NAME)` reads the environment, then
  `~/.config/1337/credentials` (0600, `NAME=value` lines; path override
  `CLAUDE_1337_CREDENTIALS`); `keys.set` writes it. `jev.decide(state,
  questions, timeout=...)` posts to TypeSafe direct when `TYPESAFE_API_KEY`
  exists, else to OpenRouter's decisions endpoint with `OPENROUTER_API_KEY`;
  one retry on 408/429/5xx after at most a second. Test: `tests/lib.test.sh`
  (stand-in server, no key).
- `lib/png.py`: stdlib-only 8-bit, non-interlaced PNG codec (`from lib
  import png`). `decode(raw)` reads colour types 0, 2, 3, 4 and 6 into
  `(width, height, rows)`, rows always expanded to RGBA; `encode(width,
  height, rows)` writes RGBA (colour type 6) with adaptive per-row
  filtering (least signed-byte sum among the five PNG filter types) and
  zlib level 9 — an unfiltered zlib-9 encode of a real generated image was
  3.1 MB where Chrome's re-encode of the same pixels was 1.0 MB; `bbox(...)`
  finds the non-transparent bounding box for `--trim`. Test:
  `tests/png.test.sh` (round trip, one decode per filter type, adaptive vs.
  all-None size, bbox on a known rectangle).
- `skills/visual/setup-key.py`: one-time OpenRouter key onboarding. OAuth
  PKCE against `openrouter.ai/auth` with a callback server on 127.0.0.1, a
  nonce-guarded paste page for when the callback cannot reach this machine,
  `--tty` for a hidden prompt; checks the key at `/api/v1/key`, stores it
  through `lib/keys.set`, never prints it. Test: `tests/setup-key.test.sh`
  (stand-in OpenRouter, no browser).
- `skills/visual/route.py`: UserPromptSubmit hook (wired in
  `hooks/hooks.json`, 10-second timeout). Silent on a prompt whose stripped
  text starts with `<task-notification>` or `<system-reminder>` (a
  background-agent event, not typed input), and otherwise silent unless the
  prompt hits a word prefilter and an OpenRouter key is stored; then one Jev
  Choice for the modality (floor on the summed visual probability; a prompt
  can carry more than one modality, each at 0.3 or more,
  `CLAUDE_1337_VISUAL_MULTI`), one concurrent Choice per modality over its
  six cheapest catalogue models, and one additionalContext block telling
  Claude to ask with a single AskUserQuestion call, one question per
  modality (Jev's pick first and Recommended, prices in every label,
  stay-with-Claude last), and run generate.py once per chosen model. A
  prompt saying transparent, transparency, alpha or "dark and light" keeps
  only `catalogue.py`'s alpha-capable raster models (when at least one
  remains) and adds `--transparent` to the raster generate.py command.
  `CLAUDE_1337_VISUAL=0` disables. Test:
  `tests/visual-route.test.sh` (stand-in Jev and catalogue).
- `skills/visual/generate.py`: makes the file once a model is chosen:
  raster and vector through chat completions with the image modality
  (extension from the data URL's media type, so Recraft vector gives
  `.svg`), video through the async videos job, speech through the audio
  endpoint. `--prompt-file <path>` reads the prompt from a UTF-8 file
  instead of the shell (exactly one of `--prompt`/`--prompt-file` required),
  for a long or heavily-quoted brief. Writes `--out` or `assets/<slug>.<ext>`,
  never overwrites, prints path and cost. `--transparent` (raster only) posts `background:
  "transparent"`, `output_format: "png"` to `/api/v1/images` instead,
  refusing before any request when `catalogue.has_alpha` says the model has
  no real alpha channel (most diffusion models only paint a fake
  checkerboard). An SVG output has Recraft's C2PA `<metadata>` block, root
  `width`/`height`, `preserveAspectRatio="none"` and `style="display:
  block;"` stripped (viewBox kept, synthesized from width/height first if
  missing). `--trim` (PNG only, no-op elsewhere) crops fully-transparent
  margins through `lib/png.py`, leaving `--trim-margin` pixels (default 32)
  clamped to the image. `--reference <file>` (raster or vector, PNG/JPEG/WebP/SVG
  by extension or magic bytes, refused over 20 MB) sends the file as a data
  URL alongside the prompt so the model edits or varies it: a second
  `image_url` content part on chat/completions, an `image` list on
  `/api/v1/images` (unverified against a live edit call). Refused before any
  request when `catalogue.reference_supported` says the model takes no image
  input. `--preview` calls `preview.py`'s `make_preview()` in-process on the
  written file and adds a `preview` path to the JSON line; a preview
  failure never fails the command, since the paid file is already written.
  Every successful generation appends a line to a cost log (`CLAUDE_1337_VISUAL_LOG`,
  else `visual.jsonl` next to the credentials file; a logging failure is a
  stderr note, never a non-zero exit). `generate.py --cost [--since 24h|7d|30m|<ISO
  date>]` sums that log and prints the total, call count and calls without
  a known price, no key or network needed.
  Exit 3 no key, 4 API failure, 5 failed video job, 6 model unusable
  for this account, 7 `--transparent` on a non-alpha model, 8 `--reference`
  on a model with no image input. Test: `tests/generate.test.sh` (stand-in
  OpenRouter).
- `skills/visual/preview.py`: `<file>...` [`--out path.png`] writes a
  self-contained HTML contact sheet showing each file twice, on GitHub dark
  (`#0d1117`) and white (`#ffffff`), with name and dimensions when known
  (`lib/png.py` for PNG, the SVG's `viewBox`), images embedded as data URLs.
  Renders it through whichever of `google-chrome`, `google-chrome-stable`,
  `chromium`, `chromium-browser` is first on PATH
  (`--headless=new --screenshot=... --window-size=... --allow-file-access-from-files
  --hide-scrollbars --default-background-color=00000000`, 30 s timeout) into
  one PNG. Default output a `tempfile.mkdtemp(prefix="1337-preview-")`
  temp dir; `--out` names the PNG, the HTML goes next to it. Prints the PNG
  path, or the HTML path (with one stderr note) when there is no browser or
  it fails — never a non-zero exit for that. Exit 2 a missing input file.
  Test: `tests/preview.test.sh` (fake `google-chrome` on a temp PATH).
- `skills/visual/catalogue.py`: `models(modality)` lists OpenRouter's
  generation models for `raster_image`, `vector_svg`, `video` or `speech`
  with one price and unit each (image token, second or video token,
  character), cheapest first, live on every call. Raster (and vector)
  entries also carry `alpha` (`has_alpha`): true when the listing's
  `supported_parameters` names `background`, else a small id-prefix
  allowlist (`openai/gpt-*image*`), the one source `generate.py` imports
  for its `--transparent` refusal; and `reference_supported`
  (`reference_supported`): true when the listing's `architecture.input_modalities`
  names `image`, the one source `generate.py` imports for its `--reference`
  refusal, callable with just a model id (it fetches the live listing
  itself then). Test: `tests/catalogue.test.sh` (fixture JSON shaped like
  the live lists).
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
  The orchestrator cases seed their workspace from a `scaffold.sh`, so they
  need `--scaffold`, `--allow-tools` and a case filter:
  `claude plugin eval . --scaffold --allow-tools Bash,Edit,Write --case 'orchestrator-*'`
  (`--case` takes one glob; a second `--case` flag silently overrides the first).
  A Bash grant needs the sandbox backend installed: `bubblewrap` and `socat`.
  On a machine whose `~/.docker` holds symlinks inside it (WSL Docker Desktop
  links `contexts` and `features.json` into the Windows profile), the Bash
  sandbox refuses to run and the case errors out before any grader; `DOCKER_CONFIG`
  does not help because the default `~/.docker` is always scanned. Make
  `~/.docker/contexts` a plain directory or run those cases elsewhere.
- `hooks/stop-review.sh`: Stop hook that once per session offers a
  `/1337:review` pass when the session diff adds 30+ lines
  (`CLAUDE_1337_REVIEW_NUDGE=0` opts out). Test: `tests/stop-review.test.sh`.
- `hooks/dispatch-nudge.sh`: Stop hook, active in orchestrator or tiered mode,
  that once per session nudges to dispatch when the main session codes three
  times without dispatching 1337:builder (`CLAUDE_1337_DISPATCH_NUDGE=0` opts
  out). Test: `tests/dispatch-nudge.test.sh`.
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
- `tools/replay.sh <transcript.jsonl>`: replays a real session transcript's
  tool_use calls through the current `hooks/orchestrator-guard.sh` and
  `hooks/read-cap.sh`, printing a TSV plus an allowed/refused/flip summary
  so a hook change can be checked against real sessions, not just the
  crafted payloads in their own test suites. Test: `tests/replay.test.sh`
  against the redacted `tests/fixtures/replay-sample.jsonl`.
- Orchestrator mode, opt-in via the `orchestrator` option in `plugin.json`
  `userConfig` (or `CLAUDE_1337_ORCHESTRATOR=1`, or `EVAL_CLAUDE_1337_ORCHESTRATOR=1`
  for eval cases): `agents/` holds `scout`,
  `builder` and `checker`; `hooks/orchestrator-guard.sh` injects
  `hooks/orchestrator.md` at SessionStart and refuses large main-session
  edits (max of old and new lines, `CLAUDE_1337_MAX_LINES`, default 20) and
  any main-session Bash segment whose first word is off an allowlist
  (read-only inspection, git bookkeeping subcommands, `sed` without `-i`,
  the plugin's own scripts, the test runners, `claude`, `tasqx`, `ripwire`;
  `CLAUDE_1337_BASH_ALLOW` adds words). A small shell lexer in the hook
  splits the command, keeps quoted text and heredoc bodies as data, and
  judges every redirect/`tee` target: only ~/.claude and temp dirs, with
  code files refused even under temp dirs (Write too). jq missing refuses.
  It also refuses Bash that dumps a file's contents
  (`cat`, `head`, `sed -n`, a pathless `rg` or `grep -r`, `cp`/`mv` out of
  the tree, an inline interpreter opening a file, and, inside the git
  allowlist, `git show <rev>:<path>`, `git cat-file`, `git grep` or a
  `-c alias.*` config; every `git diff` form stays allowed), in every
  segment and behind `command`/`builtin`/`exec`/`env`, the same way `hooks/read-cap.sh` refuses
  Read/Grep/Glob. Small allowed edits are capped at 3 per session
  (`CLAUDE_1337_EDIT_CAP`), a budget ripwire's own symbol edit (the one
  sanctioned Bash write) draws on too.
  Test: `tests/orchestrator-guard.test.sh`.
- `hooks/read-cap.sh`: PreToolUse hook, orchestrator mode only, capping the
  main session's Reads (`CLAUDE_1337_READ_CAP`) and Grep/Glob calls
  (`CLAUDE_1337_GREP_CAP`) per user turn; both default 0, refusing every call
  of that kind and pointing to ripwire for code or `1337:scout` for anything
  else, a positive integer allows that many, and `off` (not `0`) disables the
  cap for that kind. Subagent calls always pass the cap, but a subagent's
  first Grep or Glob is nudged once toward ripwire instead. Test:
  `tests/read-cap.test.sh`.
- Tiered mode, opt-in via the `tiered` option in `plugin.json` `userConfig`
  (or `CLAUDE_1337_TIERED=1`, or `EVAL_CLAUDE_1337_TIERED=1` for eval cases):
  `hooks/tiered-rules.sh` prints
  `hooks/tiered.md` at SessionStart, with `${CLAUDE_PLUGIN_ROOT}` replaced
  by the real path, so the main session runs `skills/tier/route.py` before
  every builder dispatch and uses Jev's tier as the model. Test:
  `tests/tiered-rules.test.sh`.
- `hooks/route-guard.sh`: PreToolUse hook on Agent/Task, tiered mode only,
  that enforces the rule above instead of leaving it to prose: it refuses a
  `1337:builder` dispatch whose session never ran the router, whose routed
  steps are already all spent, or whose model is not one of the tiers still
  owed, reading the `1337-tier-route:`/`1337-tier-failed:` markers
  `skills/tier/route.py` prints; once a step's slot is spent it allows
  exactly one further dispatch at that step's routed tier plus one (Opus
  steps get none), consumed the same way and never stacking with an owed
  tier's own priority. `CLAUDE_1337_ROUTE_GUARD=off` disables it.
  Test: `tests/route-guard.test.sh`.
- `hooks/review-gate.sh`: PreToolUse hook on Bash|Agent|Task, orchestrator
  mode only, that enforces a review checkpoint: after a `1337:builder`
  dispatch, it refuses to `git commit` or dispatch another builder until a
  `git diff` has run and `/1337:review` has been called, unless the change is
  at or under `CLAUDE_1337_REVIEW_MIN_LINES` (default 20). For dispatch only,
  a `1337:checker` result starting with `FAIL` on its first line sanctions a
  retry even without review. A `git diff` with git global options in front
  (`git -C <path> diff`) counts. The gate anchors on the last dispatch that
  actually ran from `hooks/lib/builder-dispatches.jq`, ignoring ones a
  PreToolUse hook refused. `CLAUDE_1337_REVIEW_GATE=off` disables it. Test:
  `tests/review-gate.test.sh`.
- `hooks/lib/builder-dispatches.jq`: shared jq filter that lists
  `1337:builder` dispatches (Agent or Task tool_use) from a transcript slice,
  excluding ones a PreToolUse hook refused before they ran. Both
  `hooks/review-gate.sh` and `hooks/route-guard.sh` call it to anchor on the
  last dispatch that actually spent the slot. Test:
  `tests/builder-dispatches.test.sh`.
- `hooks/lib/git-subcommand.sh`: sourced helper; `git_subcommand WORD...`
  (the words after `git`) sets `git_sub` and `git_sub_at`, skipping git
  global options (`-C`/`-c` with bare or quoted values, `--no-pager`,
  `--git-dir`, `--work-tree` and the like). An option it cannot parse comes
  back as `git_sub` starting with `-`, which `hooks/orchestrator-guard.sh`
  refuses and `hooks/read-cap.sh` counts as a read. Test:
  `tests/git-subcommand.test.sh`.
- `hooks/lib/mask-quotes.sh`: sourced helper; `mask_quotes` reads a Bash
  command on stdin and blunts the separator characters (whitespace, `;`,
  `|`, `&`, `<`, `>`) inside single- or double-quoted spans, so a quoted
  `;` or `|` (a commit message, an echo argument) is not mistaken for a real
  segment split. `$( )` and backticks stay live even inside double quotes,
  since the shell executes them there. `hooks/read-cap.sh` masks a command
  this way before splitting it into segments or picking out its first word
  (`hooks/orchestrator-guard.sh` has its own lexer). Covered by
  `tests/read-cap.test.sh`.
- `.claude/skills/seed-corpus/`: repo-local skill (not shipped) for turning a
  shell test suite into a JSONL corpus of captured checks, one row per
  execution with payload, exit code, and error fragment. Worked example:
  `tests/guard-corpus.jsonl` and `tests/guard-corpus.test.sh` (task #657).

All shell suites run together with `tests/run-all.sh`; a change to `hooks/` or
`skills/` is not done until it is green.

Behaviour that users should get goes in the plugin, never in this file.

## Try it locally

Run Claude with the plugin loaded straight from this folder, then pick the
style:

```bash
claude --plugin-dir ~/projects/1337-claude
```

Inside the session: `/output-style` and choose `1337:l33t`. After editing
plugin files, run `/reload-plugins` or restart.
