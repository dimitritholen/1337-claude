---
type: llm
weight: 1
---

Pass when the answer states that `fetch_with_retry` makes 4 total attempts
before giving up, that the delay between retries doubles (grows) rather
than staying fixed, and cites `lib/net.py` (bare filename, a path ending in
it, or a path/line reference such as `lib/net.py:9`) as the source.

Fail when the answer gets the attempt count or the backoff direction wrong,
or cites no source file. How the answer was obtained is judged by other
graders, not this one.
