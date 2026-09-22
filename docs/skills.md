# Skills

The `/1337:` commands this plugin adds.

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
  cheapest model tier per step (Haiku/Sonnet/Opus) for dispatch. With a
  stored OpenRouter or TypeSafe key, the tier per step comes from
  [Jev](https://typesafe.ai), TypeSafe's decision model, through
  `skills/tier/route.py` (plain python3, stdlib HTTP to OpenRouter's decisions
  endpoint or the TypeSafe API); a step Jev is unsure about moves one tier up.
  Without a key it sizes by hand. Read-only.
- `/1337:plan` — turns a request into the smallest plan that still reaches
  the goal: ordered, builder-sized steps with a done check each, recorded as
  tasqx tasks when the tasqx MCP tools are present, else as
  `plans/<slug>.md`. Writes the plan only, never code.
- `/1337:visual` — makes image, SVG, video and speech files through an
  OpenRouter model; see [visual generation](visual-generation.md).
  `/1337:visual setup` stores the key once.

[Back to README](../README.md)
