---
type: regex
target: trace
flags: m
match: not_contains
---
^\{"type":"assistant".*"type":"tool_use","id":"[^"]*","name":"(?:Read"|Bash","input":\{"command":"(?:[^"\\]|\\.)*(?:(?<![\w./-])(?<!\|\s*)(?:cat|head|tail|less|more|nl|bat|awk)\s+(?:-\S+\s+)*(?:\\"|[^\s|;&<>"\\-])|(?<![\w./-])sed\s+(?:-[a-zA-Z]+\s+)*-n|\$\(\s*<)).*\},"parent_tool_use_id":null,
