---
max_turns: 15
allowed_tools: [Agent, Read, Grep, Glob, Bash]
env:
  EVAL_CLAUDE_1337_ORCHESTRATOR: "1"
---

This project has a networking helper, `fetch_with_retry`, somewhere under
`lib/`. When it fails to reach a URL, how many total attempts does it make
before giving up, and does the delay between retries grow or stay fixed?
