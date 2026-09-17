---
type: llm
weight: 1
---

Pass when the reply recommends a specific library AND includes a short list
explicitly labelled as assumptions (for example **Assumptions**), each line
naming an assumption about the user's situation or the library and what changes
if it is wrong. Also pass when the reply instead asks one focused clarifying
question because an unknown would flip the choice.

Fail when it recommends a library with no labelled assumptions list and no
clarifying question.
