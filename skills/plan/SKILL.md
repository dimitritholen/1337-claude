---
name: plan
description: Turn a feature request or task into the smallest plan that still reaches the goal — ordered, builder-sized steps with one done check each — and record it where the session can work it: as tasqx tasks when the tasqx MCP tools are present, else as a plan file under plans/. Use on /1337:plan, or when the user asks to plan, break down, sequence or "how would you approach" a change bigger than one step; /1337:plan alone reports the open plan and its next step. Writes only the plan, never code.
---

You plan the way a lazy senior dev does: understand the whole thing, then
write down the least work that gets there. A plan is a list of steps someone
else can take one at a time, not an essay.

# Scope

- Default target: the request in this conversation, or the one passed as the
  argument. No argument and no request means resume mode (below).
- One step of work needs no plan: say so in one line and stop.
- Read the code the plan touches before writing a step — a plan built on
  unopened files is a guess.

# Where the plan lives

Check once, in this order, and never record in both:

1. **tasqx** — `tasqx_add_task` is in this session's tool list. The plan
   becomes tasks. A tasqx server without its write tools counts as absent;
   say so in one line.
2. **Plan file** — otherwise `plans/<slug>.md` in the repo root: slug from
   the goal, kebab-case, at most five words. One file per plan.

# Method

1. **Goal** in one line: the outcome the user wants, not the solution they
   described. Judge every step against it. If the goal is unclear and it
   changes the plan, ask one question before writing anything.
2. **Search first.** Read the repo's docs and any open plan file that
   overlaps: a ruling already written down can change the plan.
3. **Shrink** before you split. Walk the ladder for every part of the
   request: Already in this codebase? → reuse it. Stdlib, platform or an
   installed dependency does it? → use it. One line or one config value does
   it? → that is the build. Cut what serves the described solution instead
   of the goal, and keep the cuts — they go in the plan so nobody rebuilds
   them. Lazy about the solution, never about reading: rung one is
   unreachable without searching the code for an existing helper first.
4. **Split** the minimal version into steps. Each step: a title, the files
   it touches, the change in one to three lines, one verifiable done check,
   what it comes after, and the cheapest tier that can build it (haiku for
   mechanical, sonnet for pattern-following, opus for reasoning-heavy, as
   /1337:tier sizes them). Order so every step leaves the tree building.
   Seven or fewer; more is two plans. A step whose brief needs more than
   three sentences of context is two steps.
5. **Never cut** for a smaller plan: validation, error handling, security,
   data-loss guards, accessibility and tests are never cut for brevity. A
   step that adds a test is a step, not padding.

# Record in tasqx

- `tasqx_list_projects`; use the project named after the repo, and
  `tasqx_create_project` only when none matches.
- One task per step: title, project, priority, estimate, and the plan's slug
  as a tag so the plan can be found again. Open each task with one
  annotation, a plain paragraph: what the step is, why, what done looks
  like, naming files and symbols since only bodies are searched.
  `tasqx_add_check` per done criterion, `tasqx_add_dependency` per
  after-link.
- The goal, the build in 1-3 lines and the cut list go in one
  `tasqx_add_memory` entry: the build ruling in the first line, the cuts
  and their why under it, the repo path as source. That is where "why did
  we not build X" is answered later.
- Do not start a timer or a task: planning ends where work begins.

# Record in a plan file

Write `plans/<slug>.md` in this shape, every section present, Assumptions
only when there are any:

    # <goal, one line>

    Status: open

    ## Done when
    - [ ] <criterion, verifiable>

    ## Build
    <the minimal version in 1-3 lines, naming what it reuses>

    ## Steps
    ### 1. <title> · <tier> · <estimate>
    Files: <path>, <path>
    Change: <1-3 lines>
    Done: <one check>
    After: — | <step numbers>
    - [ ] done

    ## Cut
    - <what> — why the goal survives without it

    ## Log
    - <date> plan written

Working the file is the tasqx workflow by hand: read the file before a
step, tick its box when its done check holds, add a Log line for every
decision or change of direction (what and why, a paragraph at most), and
set `Status: done` when the last box is ticked. The file is the only list;
never keep a parallel todo.

# Resume mode

`/1337:plan` with no request: with tasqx, `tasqx_list_tasks` (filter
`@working`, this repo's project) and name the first unblocked task; with
files, list `plans/*.md` whose `Status:` is open and the first unticked
step of each. One line per plan, then the next step. Nothing open means
say so.

# Output

Plain text, in this order, without repeating what was just written to the
store:

1. **Goal** — one line.
2. **Build** — 1-3 lines.
3. **Steps** — one line per step: `n. title · tier · estimate · after n`,
   or the tasqx task table (`#`, title, tier, estimate, blocked by).
4. **Cut** — one line per dropped piece with its why.
5. **Assumptions** — only when there are any.
6. **Recorded** — one line: the task numbers or the file path, and the
   first step to start.

Rules: cite `path:line` for anything a step depends on; if the user insists
on a piece you cut, it goes back as a step without re-arguing. You never write code here — the plan is the deliverable; the
user starts the first step or asks you to.
