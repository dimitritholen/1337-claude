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
  `catalogue.py`, `route.py`, `generate.py`, `critique.py`, `ranking.py`,
  `preview.py`), each described below.
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
  six cheapest catalogue models (`ranking.rank_models`, the Jev-ranking
  helper shared with `critique.py`'s escalation), and one additionalContext block telling
  Claude to ask with a single AskUserQuestion call, one question per
  modality (Jev's pick first and Recommended, prices in every label,
  stay-with-Claude last), and run generate.py once per chosen model. A
  prompt saying transparent, transparency, alpha or "dark and light" keeps
  only `catalogue.py`'s alpha-capable raster models (when at least one
  remains) and adds `--transparent` to the raster generate.py command. The
  raw user prompt is also written verbatim to a
  `tempfile.mkdtemp(prefix="1337-request-")` file and every suggested
  command carries `--request-file <path>` (a write failure drops the flag
  silently, never the hook), so the critique pass sees the user's own
  words even when the brief Claude writes drops a detail.
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
  A raster or vector write (not video, not speech) is always followed by a
  `critique.run()` call in-process (imported lazily, since `critique.py`
  imports this module): `--rounds N` (default 2) and `--critic <model id>`
  pass through, `--no-critique` or `CLAUDE_1337_CRITIQUE=0` skip it. The
  JSON line gains the critique result under `critique` and a top-level
  `final`; `path` and `cost` stay the original generation's, so `cost` plus
  `critique.cost` is the total spend. `--trim` runs before the critique, so
  the critic judges the trimmed file. `--request`/`--request-file`
  (mutually exclusive, never sent to the generator) pass the user's own
  verbatim message through to `critique.run(request=...)`, so the critic
  weighs it alongside the generator prompt. Same as `--preview`: a critique
  failure (no key, API error, unparseable reply) is never fatal, only a
  stderr note and `{"error": ...}` under `critique`, since the paid file is
  already written.
  Exit 3 no key, 4 API failure, 5 failed video job, 6 model unusable
  for this account, 7 `--transparent` on a non-alpha model, 8 `--reference`
  on a model with no image input. Test: `tests/generate.test.sh` (stand-in
  OpenRouter).
- `skills/visual/critique.py`: judges a generated raster or vector file
  against its prompt with a vision-model critic (`DEFAULT_CRITIC`,
  overridable by `--critic`, then `CLAUDE_1337_CRITIC`), and fixes what it
  finds. The critic answers strict JSON (`pass`, a list of defects each
  with a type, where, a normalised bounding box, a 1-5 severity and a fix
  instruction); `pass` is computed locally, severity >= 3 fails it, never
  trusted from the model's own claim. The critic is called at temperature 0
  so the same image scores consistently. `request` (CLI `--request`/
  `--request-file`, mutually exclusive), when given, is the user's own
  verbatim message: the critic sees it as a second, clearly labelled
  section alongside the prompt ("The user's original request, verbatim:"
  vs. "The prompt sent to the image generator:"), told to judge
  `prompt_adherence` against both and, where they differ, that the request
  wins — so a detail the user asked for but the generator prompt dropped
  still counts as a defect. Without it, the payload is unchanged. An SVG is rasterised through
  `preview.py`'s headless-Chrome machinery, its window sized from the
  SVG's own `viewBox` aspect ratio (long edge 1024px, `preview.dims_svg`),
  or sent as SVG source text when no browser is on PATH. While not passing
  and rounds used are under `--rounds` (default 2), the defects drive one
  more generation (the current file as `--reference` when
  `catalogue.reference_supported` allows it), written next to the original
  as `<stem>.rN.<ext>` — an original that is itself an `.rM` file (an
  escalated run continuing an earlier critique) has that suffix stripped
  and its number carried forward, so naming continues (`x.r1.png` ->
  `x.r2.png`) instead of nesting (`x.r1.r1.png`); the final file is the
  passing one, else the lowest-scored (a fix can make things worse), ties
  to the later file. `--defects-file <path>` (a JSON list of defects, or
  `{"defects": [...]}`) seeds the first judged result instead of calling
  the critic, for a run continuing an earlier critique with a new
  `--model`; `--tried <id,id,...>` lists model ids already attempted. When
  the final result still has `pass` false, an `escalation` block is added:
  up to 10 priced, reference-taking models of the same modality, not yet
  tried and priced at or above the current model (`catalogue.models`,
  `ranking.rank_models` for the ranking, shared with `route.py`'s own
  model choice), cut to the 3 highest by Jev probability (ties by lower
  price), Jev's recommended pick always first, plus a `command` holding a
  literal `<MODEL>` placeholder — `--rounds` at least 1 even when the
  failed run used `--rounds 0` (judge-only), so the escalated run actually
  generates something — that writes the prompt, final defects and
  (when set) the request to a fresh temp dir and re-invokes this file with
  `--defects-file`/`--tried`/`--model <MODEL>` (plus `--request-file` when a
  request was given). Any failure building
  it (no key, Jev, catalogue, no candidates) never raises: `escalation_error`
  instead, the same "must never fail" rule as a critic failure. Also
  importable as `from critique import run`, called by `generate.py` after
  every raster/vector write; `run()` never prints or exits. Exit 0 done
  (pass or not), 2 bad args/missing file/unsupported type, 3 no key, 4 API
  or catalogue failure, 9 the critic reply is still unparseable after one
  retry. Test: `tests/critique.test.sh` (stand-in OpenRouter and Jev, fake
  `google-chrome`).
- `skills/visual/ranking.py`: `price_label(entry)`, `criterion(entry)` and
  `rank_models(entries, state, question, floor, timeout)` — the one Jev
  Choice pattern `route.py`'s per-modality model ranking and
  `critique.py`'s escalation ranking both use: each catalogue entry gets a
  `probability` field from Jev's answer, and the return is
  `(ranked, recommended)`, `recommended` `None` when Jev's own confidence
  is under `floor` (`ranked` then keeps cheapest-first order). Covered by
  `tests/visual-route.test.sh` and `tests/critique.test.sh`; no test file
  of its own.
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
  stored OpenRouter or TypeSafe key. The API timeout is 20 seconds by default;
  `CLAUDE_1337_TIER_TIMEOUT` (seconds, float) overrides it. Test:
  `tests/tier-route.test.sh` (stand-in API, no key).
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
  `CLAUDE_1337_SUBAGENT_RULES=0` disables). A read-only agent type
  (`CLAUDE_1337_SUBAGENT_READONLY`, default `scout|checker|explore`, an
  empty string giving nobody the short digest) gets the digest with its
  "Work on the minimum" and "Evaluate the task briefly" sections cut, since
  it has nothing to build or evaluate for scope. Test:
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
  judges every redirect/`tee` target: only the ~/.claude data allowlist
  (`~/.claude/projects`, `~/.claude/todos`, `~/.claude/.1337-*` state — config,
  hooks, agents, skills, commands and the installed plugin under
  `~/.claude/plugins` stay off-limits) and temp dirs, with code files refused
  even under temp dirs (Write too). jq missing refuses.
  A relative target is resolved against a preceding literal `cd`/`pushd` only
  while every operator since it is `&&` (a failed `cd` after `;` or `||` would
  leave the shell in the repo) (#726).
  It also refuses Bash that dumps a file's contents
  (`cat`, `head`, `sed -n`, a pathless `rg` or `grep -r`, `cp`/`mv` out of
  the tree, an inline interpreter opening a file, and, inside the git
  allowlist, `git show <rev>:<path>`, `git cat-file`, `git grep` or a
  `-c alias.*` config; every `git diff` form stays allowed), in every
  segment and behind `command`/`builtin`/`exec`/`env`, the same way `hooks/read-cap.sh` refuses
  Read/Grep/Glob. Small allowed edits are capped at 3 per session
  (`CLAUDE_1337_EDIT_CAP`), a budget ripwire's own symbol edit (the one
  sanctioned Bash write) draws on too.
  Subagent Bash calls otherwise pass untouched, but one check still applies
  to them (#723): `git checkout -- <path>`/`git checkout .`, `git restore`,
  `git reset --hard/--merge/--keep`, `git stash` beyond `list`/`show`, and
  `git clean` are refused, since a subagent reverting another parallel
  builder's finished work in the shared tree is the incident this guards
  against; `CLAUDE_1337_SUBAGENT_GIT_GUARD=off` disables it.
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
  retry even without review (a leading `[harness: ...]` line the harness
  sometimes prepends to a subagent result is skipped first); an async
  checker's verdict, when its synchronous result is only the launch stub, is
  read from the matching `<task-notification>`'s `<result>` instead. A `git
  diff` with git global options in front (`git -C <path> diff`) counts. The gate anchors on the last dispatch that
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
- `hooks/lib/tokenize.sh`: sourced helper, the one Bash lexer both
  `hooks/orchestrator-guard.sh` and `hooks/read-cap.sh` judge a command with.
  `tokenize` reads a command on stdin (portable awk) and prints one `S`
  record per segment (split on `|` `;` `&` `&&` `||` newlines and `( )`,
  with the inside of every `$( )`, backtick and `<( )` a segment of its
  own), fields separated by `\037`: segment id, piped flag, the index of
  the command word after the `VAR=val`, command/builtin/exec/env and
  keyword prefixes, a `command -v` lookup flag, the assignment indices,
  the words (quotes removed) and the redirects with their targets, and the
  operator that ended the segment (`tok_sep`: `&&`, `||`, `;`, `|`, `&`, `nl`,
  a paren, or empty) and its nesting depth inside groups and substitutions
  (`tok_depth`); plus `B` heredoc bodies and `X` constructs it does not judge.
  Quoted text and heredoc bodies are data. `tok_parse` splits one `S` record
  into `tok_*` variables; `tok_input_redirects` (on top of the current
  `tok_parse` state) sets `tok_inputs` to a command-less segment's `<` targets
  (fd digits stripped, `/dev/null`/`/dev/stdin` dropped) — the `$(< file)`
  shape neither hook's own reader dispatch sees, since there is no command
  word to switch on; each hook still applies its own path policy on top
  (`hooks/orchestrator-guard.sh` exempts a scratch operand, `hooks/read-cap.sh`
  does not, matching how it already treats `cat /tmp/x`). Covered by
  `tests/orchestrator-guard.test.sh` and `tests/read-cap.test.sh`.
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
