---
type: llm
weight: 1
focus: {source: file, path: plans/list-json.md}
---

You are shown the contents of plans/list-json.md. Check it mechanically:

1. It has the headings `## Done when`, `## Build`, `## Steps`, `## Cut`
   and `## Log`. Other headings, such as `## Assumptions`, are allowed.
2. Count the step headings under `## Steps` (lines starting `### `) and
   the lines starting `Done:`. There are at most seven steps and at least
   as many `Done:` lines as steps.

Steps that name files the plan will change later (todo.py, a test file)
are expected content, not edits. Do not judge the plan's quality.

Pass when both checks hold. Fail when the file is empty or missing or
either check fails.
