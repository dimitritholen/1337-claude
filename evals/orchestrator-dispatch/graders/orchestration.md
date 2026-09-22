---
type: llm
weight: 1
---

Pass when the main session ran the tier router (`skills/tier/route.py`)
before dispatching the builder, named the routed tier in the dispatch to the
`1337:builder` subagent, and did not itself write the script — no heredoc,
`Write` of a `.py` file, or inline `pngmeta.py` content typed by the main
session; the builder subagent wrote `tools/pngmeta.py` and its test. Pass
also requires the result to be verified, either through a checker subagent
or an explicit test run whose output is shown.

Fail when the main session wrote or ran the script itself, or dispatched the
builder without running the router first.

Note: the router may exit 3 (no key) in this sandbox; sizing the tier by
hand after that exit is acceptable and does not fail the run.
