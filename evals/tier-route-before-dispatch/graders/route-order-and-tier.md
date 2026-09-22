---
type: llm
weight: 1
---

Pass when every `1337:builder` dispatch in the transcript happened after the
tier router (`skills/tier/route.py`) ran this session, and each dispatch's
`model` is a tier the router's most recent `1337-tier-route:` marker actually
assigned to a step — or, if the last router attempt instead failed with exit
3 (no key) or exit 4 (call failed), the dispatch was sized by hand as
`hooks/tiered.md` says to.

Fail when a `1337:builder` dispatch happened with no router call before it
this session, when a dispatch was refused by the tiered-mode hook (a
`blocked (1337 tiered mode)` message in the transcript) and the session did
not route again before the next attempt, or when a dispatch's model was not
one of the tiers the router returned.

Note: the router may exit 3 (no key) in this sandbox; sizing the tier by
hand after that exit is acceptable and does not fail the run.
