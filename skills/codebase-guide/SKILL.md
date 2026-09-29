---
name: codebase-guide
description: Write a visual, single-file HTML onboarding report for the repo in the working directory, always in one fixed design (bundled template.html), so a beginner understands it on the first read and an expert finds any file in five minutes. Use on /1337:codebase-guide, or when the user asks for a codebase guide, onboarding doc, architecture overview or "explain this repo". Writes one HTML file, no other edits.
---

You write one HTML report that teaches any developer what this codebase
does, how it is built and where everything lives.

# Scope

- Default output: `docs/codebase-guide.html`. Use the path the user gives.
- Target: the repo in the session's working directory. A named module gets
  depth; the whole repo gets breadth.

# Analyze first

Read before you write. Base every claim on code you read, and flag anything
unclear or apparently unused instead of guessing (a `callout caveat`).

1. **Purpose**: README, CLAUDE.md/AGENTS.md, docs.
2. **Entry points** and the main components with their dependencies.
3. **One or two real flows**, traced through actual functions and files.
4. **Patterns and conventions** that recur, and the reason for each.
5. **Core data types**: where data comes from and where it goes.
6. **Feature-to-file map**: every feature, and the common tasks.

# Template

Read `${CLAUDE_PLUGIN_ROOT}/skills/codebase-guide/template.html` before
writing. It is a worked sample of a fictional project, "Quill".

- Keep the `<head>`, all CSS, the theme tokens, the layout and the script
  exactly as they are. Replace only the masthead, the `.toc` entries and the
  content of `<main>`, and drop the sample comments.
- Reuse the template's components and classes. Do not invent styles. If
  something truly has no component, add the smallest CSS for it using the
  existing tokens (`--paper-2`, `--rule`, `--ink-2`, `--c1`…`--c6`).
- Tables and `<details>` have no component. Add this one block at the end
  of the `<style>` element and use it for sections 6 and 8:

  ```css
  .map { width: 100%; border-collapse: collapse; font: .92rem/1.5 var(--sans); }
  .map th, .map td { text-align: left; padding: 9px 12px 9px 0; border-bottom: 1px solid var(--rule); vertical-align: top; }
  .map th { font: 600 .68rem/1 var(--sans); letter-spacing: .12em; text-transform: uppercase; color: var(--ink-3); }
  details { border: 1px solid var(--rule); border-radius: 10px; background: var(--paper-2); padding: 12px 18px; margin: 14px 0; }
  summary { cursor: pointer; font: 600 1rem var(--sans); }
  ```

- Extend the sidebar `<ol>` to all eight sections, in the template's
  `<li><a href="#id"><span>NN</span>Title</a></li>` form.
- Metadata: real repository, the commit hash you read, today's date, an
  honest reading time. Fill the colophon the same way.
- One file, works offline: no external fonts, scripts, images or styles or
  other external URLs. The HTML is well formed: tags balanced, ids unique.

# Sections, in order

Each is `<section class="section" id="…">` with a `.section-head`
(`.section-num`, `h2`, optional `.section-intro`).

1. **In one minute** (`in-one-minute`): 3–5 sentences in `.prose` (first one
   `.lead.dropcap`), a `.facts` strip with real numbers, and the big-picture
   diagram in a `.figure` (`.figure-frame` svg, `figcaption`, `.legend`).
2. **Key words** (`key-words`): `dl.glossary` of `.term` entries (`dt`,
   `dd`, optional `.see` pointing to the defining file).
3. **The main parts** (`main-parts`): `.parts` grid, one `article.part cN`
   per component with `part-head`, `part-root`, `part-what`, `ul.resp`,
   `ul.files` and `.talks` chips. Give each `id="part-<name>"`, and reuse its
   colour class in the diagrams. Add a folder-map diagram here or in
   section 1. Unclear or unused code goes in a `.callout.caveat`.
4. **How it runs** (`how-it-runs`): a sequence or flow `.figure` of one real
   run, then `ol.steps` whose `.step-n` numbers match the `d-badge` numbers
   in the SVG; each step has `.where` (path and `code.fn`). Side notes go in
   `.callout.note`.
5. **Patterns to know** (`patterns`): one `article.pattern` each with
   `.pattern-tag`, `h3`, a short description, a `figure.code` excerpt (real,
   5–15 lines; `code-head` with the path and line range; `pre` with
   `data-lang`, `data-start` and `data-hl` set to real line numbers; escape
   `<` and `&`) and a `p.why`.
6. **Where to find things** (`where-to-find`): `table.map` with "I want to…"
   in the first column and the file or folder (`code.path`) in the second.
   Cover every feature and common task.
7. **Run it yourself** (`run-it`): setup, run and test commands copied from
   the repo (README, Makefile, package.json, pyproject.toml) in
   `figure.code` blocks with `data-lang="sh"`.
8. **Going deeper** (`going-deeper`): invariants, trade-offs, limits and
   gotchas, each in a `<details><summary>` block.

# Diagrams

Use only the template's `d-*` classes
and `cN` colour tokens: `d-node`, `d-data`, `d-actor`, `d-title`, `d-sub`,
`d-edge`, `d-elabel`, `d-lifeline`, `d-activation`, `d-badge`, `d-frame`.
Label boxes with real names, give unique ids to `title`, `desc` and markers,
and add a one-line `figcaption` to each.

# Style

Short sentences, plain words, each term defined on first use, an analogy
where it helps. Good: "The runner is like a race referee: it starts both
lanes, times them, and writes down the results." Bad: "The runner
orchestrates lane execution and persists telemetry." Summary on top, expert
detail in `<details>`. Only real repo-relative paths and real symbol names.

# Verify before finishing

- Every feature appears in section 6.

Final reply: the output path and a three-line summary.
