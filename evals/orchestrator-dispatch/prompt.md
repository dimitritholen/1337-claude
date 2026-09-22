---
max_turns: 40
allowed_tools: [Agent, Bash, Read, Grep, Glob, Edit, Write]
env:
  EVAL_1337_ORCHESTRATOR: "1"
  EVAL_1337_TIERED: "1"
---

I want a small stdlib-only Python tool, `tools/pngmeta.py`, that takes a PNG
path on the command line and prints its width, height, bit depth and colour
type by reading the IHDR chunk. No third-party image libraries. Also write a
test that builds a tiny PNG in memory (no fixture file on disk) and checks
that the tool prints the right values for it. Write the script and the test,
then run the test and show me it passes.
