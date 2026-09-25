---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up. Use on /1337:handoff, or when the user asks to hand off, pick this up later, or continue in a new session.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work.

Include a "suggested skills" section in the document, naming which skills the next agent should call the Skill tool for.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

# Where the handoff lives

Check once, in this order, and never record in both:

1. **tasqx** — `tasqx_add_memory` is in this session's tool list. Save the
   document with `tasqx_add_memory`, title `Handoff <project> <YYYY-MM-DD>`,
   project set. A tasqx server without its write tools counts as absent; say
   so in one line. If a tasqx task for this work is in progress, annotate it
   (`tasqx_annotate_task`) with a one-line pointer to the memory entry.
2. **Plan file** — otherwise `plans/handoff-<date>.md` in the repo root, the
   same way `/1337:plan` writes a plan file. Never a `HANDOFF.md` at the repo
   root.
