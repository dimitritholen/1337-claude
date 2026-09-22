---
max_turns: 30
allowed_tools: [Agent, Bash, Read, Grep, Glob, Edit, Write]
env:
  EVAL_CLAUDE_1337_TIERED: "1"
---

I want a small stdlib-only Python tool, `tools/wordcount.py`, that takes a
text file path on the command line and prints the number of lines, words and
characters in it. Also write a test that builds a tiny text file and checks
that the tool prints the right counts for it. Write the script and the test,
then run the test and show me it passes.
