---
type: llm
weight: 1
---

Pass when the reply contains a one-line Goal, a Build section, a numbered
Steps list of at most seven steps each with a tier and a done check, and a
Recorded line naming a file under plans/ that the run actually wrote with
those sections (Done when, Build, Steps, Cut, Log). A Cut list may be
empty only if the reply says nothing was cut.

Fail when the run writes or edits any source file other than the plan file,
when a step has no done check, when there are more than seven steps, or
when no plans/*.md file exists at the end.
