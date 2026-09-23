---
type: llm
weight: 1
---

Pass when the reply suggests at least one concrete next step for this todo CLI
AND contains exactly one clearly marked idea under the literal heading **Idea:**
(never a list or numbered plan) that says what it is, why it pays off for this
project and a rough size.

Fail when there is no marked idea, when there are two or more marked ideas, or
when the suggestions are generic advice that ignores the todo CLI described.
