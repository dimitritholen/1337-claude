# Skills

The `/1337:` commands this plugin adds.

- `/1337:review` — reviews the current diff (or a named branch/PR) for
  over-engineering and hands back a delete-list: what to cut and what existing
  code, stdlib or platform feature replaces it. Given a spec (a tasqx memory
  doc or task, or a file), or when `/1337:implement` calls it, it also checks
  the diff against that spec: what is missing, extra or divergent. Read-only.
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
  cheapest model tier per step (Haiku/Sonnet/Opus) for dispatch. With a
  stored OpenRouter or TypeSafe key, the tier per step comes from
  [Jev](https://typesafe.ai), TypeSafe's decision model, through
  `skills/tier/route.py` (plain python3, stdlib HTTP to OpenRouter's decisions
  endpoint or the TypeSafe API); a step Jev is unsure about moves one tier up.
  Without a key it sizes by hand. Read-only.
- `/1337:plan` — turns a request into the smallest plan that still reaches
  the goal: ordered, builder-sized steps with a done check each, recorded as
  tasqx tasks when the tasqx MCP tools are present, else as
  `plans/<slug>.md`. When a spec exists (a `Spec: <feature>` tasqx memory
  entry or `plans/<slug>-spec.md`), the plan follows it and splits it into
  vertical slices. Writes the plan only, never code.
- `/1337:grill` — interviews you about a plan or idea, one round of numbered
  questions at a time with a recommended answer each, until the decisions
  are settled; records them as it goes.
- `/1337:spec` — turns the current conversation into a spec without further
  questions, saved as a tasqx memory entry or `plans/<slug>-spec.md`. Writes
  the spec only, never code. The spec carries an Expectations block (acceptance,
  claims, context, edge cases, measurable styling), which you approve and which
  becomes the tests. You call it yourself; Claude never starts it.
- `/1337:implement` — builds a plan or spec one task at a time: picks the
  tier (routed in tiered mode), has the step built test-first with
  `/1337:tdd`, verifies it, then runs `/1337:review` in spec mode before the
  next task. `/1337:implement --one` builds one task and stops, so you can
  `/clear` between tasks. You call it yourself; Claude never starts it.
- `/1337:exploratory-test` — exploratory QA of the running app: drives it like
  a user, in `change` mode (the surfaces a diff touches), `smoke` mode (a quick
  pass) or `full` (the whole app), and reports confirmed findings by severity. Needs a
  per-project contract in `docs/agents/qa.md`. The `1337:qa` agent runs it
  from the build flow.
- `/1337:tdd` — red-green-refactor reference for building features or fixing
  bugs test-first: what a good test is, where it goes, the anti-patterns.
  Edits tests and code.
- `/1337:diagnose` — a diagnosis loop for hard bugs, regressions, flaky tests
  and slow code. Also fires when you report something broken or ask why X
  happens.
- `/1337:domain-modeling` — sharpens the project's vocabulary and decisions
  while you design, writing them to `CONTEXT.md` and ADRs under `docs/adr/`.
- `/1337:unslop` — an editing pass that strips AI patterns from prose (docs,
  articles, PR text) and gives it a human voice. Edits text.
- `/1337:prompt-engineering` — source-cited reference for writing, reviewing
  and debugging prompts and agent instructions for Claude, GPT and Gemini,
  with per-vendor deep dives under `references/`. Also fires when you ask
  for help with a prompt.
- `/1337:promptimize <rough prompt>` — turns a rough prompt into one
  optimized prompt: asks about the gaps when needed, reviews it critically,
  rewrites it with `/1337:prompt-engineering`, and outputs only the final
  prompt in a code block.
- `/1337:merge-conflicts` — resolves an in-progress merge or rebase conflict
  by tracing why each side made its change. Edits the conflicting files.
- `/1337:handoff` — writes a handoff document so a fresh session can pick up
  the work: a tasqx memory entry when tasqx is available, else
  `plans/handoff-<date>.md`. You call it yourself; Claude never starts it.
- `/1337:terse` — reports or changes the [terse mode](terse-mode.md) level
  (`off`, `on`, `hard`) set in /config. On/hard inject the rules at
  SessionStart; overruns are nudged next turn, not blocked.
- `/1337:visual` — makes image, SVG, video and speech files through an
  OpenRouter model; see [visual generation](visual-generation.md).
  `/1337:visual setup` stores the key once.

## Pipeline

For work bigger than one step: `/1337:grill` to settle the decisions,
`/1337:spec` to write them down with an approved Expectations block, `/1337:plan`
to slice the spec into tasks that each name the expectation rows they satisfy,
then `/1337:implement`, which runs `/1337:tdd` for each task, then
`1337:qa` (`/1337:exploratory-test` in smoke mode, once per user-facing
pull request, skipped for internal-only changes or when `docs/agents/qa.md` is
missing) and `/1337:review` in spec mode. Stuck on a bug along the way:
`/1337:diagnose`. Pausing: `/1337:handoff`.

A task goes scout, builder, checker, review; the pull request then gets one
qa smoke run (about 10-15 minutes) before it is opened or merged. qa is the
only step that runs the app; on `FAIL` its blocker and major findings go back
to the builder, at most two qa rounds, while minor and polish findings become
tasks. The full pass runs nightly on main: see [the nightly recipe](qa-nightly.md).

[Back to README](../README.md)
