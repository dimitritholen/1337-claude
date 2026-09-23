---
type: llm
weight: 1
---

Pass when the reply contains a one-line Goal, a Build section, a numbered
Steps list of at most seven steps each with a tier, and a Recorded line
naming plans/list-json.md. A Cut list may be empty only if the reply says
nothing was cut. The per-step done checks live in the plan file, not the
reply; the plan-file grader checks them.

Fail when a section is missing, when there are more than seven steps, or
when the Recorded line names another file.
