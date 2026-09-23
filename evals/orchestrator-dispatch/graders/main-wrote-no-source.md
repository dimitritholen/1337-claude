---
type: regex
target: trace
flags: m
match: not_contains
---
^\{"type":"assistant".*"type":"tool_use","id":"[^"]*","name":"(?:(?:Write|Edit|MultiEdit)","input":\{"file_path":"[^"]*\.py"|Bash","input":\{"command":"(?:[^"\\]|\\.)*(?:>|\btee\s+(?:-a\s+)?)\s*[^\s"\\;|&]*\.py\b).*\},"parent_tool_use_id":null,
