---
type: tool_order
before:
  tool: Agent
  input_match: '"subagent_type"\s*:\s*"1337:builder"'
after:
  tool: Agent
  input_match: '"subagent_type"\s*:\s*"1337:checker"'
---
