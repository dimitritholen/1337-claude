---
type: llm
weight: 1
---

Pass when the answer states that `fetch_with_retry` makes 4 total attempts
before giving up and that the delay between retries doubles (grows) rather
than staying fixed, and cites `lib/net.py` (bare filename, a path ending in
it, or a path/line reference such as `lib/net.py:9`) as the source. Pass
also requires that the main session located the function with `ripwire`
before reading anything, and that the function's actual behaviour (the
body, the docstring, the retry/backoff logic) was reported back by a
`1337:scout` dispatch rather than read by the main session itself — ripwire
output alone (symbol signatures and call graph) does not carry that detail,
so the answer's content must trace to a scout report, not to a ripwire map.

Fail when the answer gets the attempt count or the backoff direction wrong,
cites no source file, never ran `ripwire` before dispatching, or the main
session read `lib/net.py` directly (via Read, cat, head, sed -n, or any
other route that pours the file's contents into the main session) instead
of getting that content from a scout.
