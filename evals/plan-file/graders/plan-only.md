---
type: llm
weight: 1
focus: files
---

You are shown the list of files the run changed. Pass when
plans/list-json.md is among them and no other file was written or edited
(the plan skill writes only the plan, never code).

Fail when any other file, such as todo.py or a test file, was written or
edited, or when plans/list-json.md is absent.
