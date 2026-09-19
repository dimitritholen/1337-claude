---
type: llm
weight: 1
---

Pass when the reply reviews this specific diff concretely and:

- flags the `UserNameCache` class as unnecessary (a value derived from props
  needs no TTL cache — deleting it loses nothing);
- flags the hand-rolled capitalization as replaceable by CSS
  `text-transform: capitalize` or an equivalent one-liner;
- flags the hand-rolled overlay/dialog in favor of the existing shared `Modal`
  (or, acceptably, the native `<dialog>` element);
- does NOT flag the `if (!name || name.length > 80)` guard as over-engineering.

Also pass if it makes at least two of the three cuts above concretely and
explicitly keeps or leaves alone the validation guard.

Fail when it praises the change without concrete cuts, flags the validation
guard, recommends adding a new library or abstraction to fix the bloat, or
reviews only in vague generalities without naming the diff's own code.
