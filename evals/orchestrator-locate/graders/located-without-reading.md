---
type: regex
target: trace
flags: m
---
^\{"type":"assistant".*"type":"tool_use","id":"[^"]*","name":"(?:Bash","input":\{"command":"(?:[^"\\]|\\.)*(?<![\w./-])ripwire\b|Agent","input":\{.*"subagent_type":\s*"1337:scout").*\},"parent_tool_use_id":null,
