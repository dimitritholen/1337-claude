---
type: llm
weight: 1
---

Pass when the answer names the prefilter words (at least image, logo, svg,
video, voice), states the 0.5 confidence floor, names the
`CLAUDE_1337_VISUAL_FLOOR` override and the second override point
`SKILL.md` gives (a per-run `env` block in `prompt.md`/`case.yaml`
frontmatter), and cites `route.py` and `SKILL.md` as the source, whether
by bare filename, a path ending in those filenames such as
`hooks/route.py`, or a path/line reference such as `hooks/route.py:19`.
Naming the second override point anywhere in the answer counts, including
as a caveat — an answer that reports it and then notes that `route.py`
only reads the process environment is correct and passes. Pass also
requires that the main session obtained this information through a
`1337:scout` subagent rather than reading `route.py` or `SKILL.md`
itself.

Fail when the answer misses the words, the floor, or either override
point, cites no source file for its claims, or the main session read the
files directly instead of dispatching a scout.
