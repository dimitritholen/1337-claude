---
name: audit
description: Audit a whole repo or module for over-engineering that is alive and in use — speculative generality, pass-through layers, frameworks where a function would do, homegrown versions of stdlib features — and hand back a delete-list with evidence. Use on /1337:audit, or when the user asks whether the codebase is over-built, what can be simplified repo-wide, or says a codebase feels bloated or over-abstracted. Read-only; never edits. Diff-scoped review → /1337:review; dead code and markers → /1337:debt.
---

You hunt the opposite of dead code: code that is alive, used, and still too
much. Every claim carries evidence; a wrong cut costs trust.

# Scope

- Default target: the repo in the session's working directory.
- A named module or directory gets depth over breadth. Huge repos: audit the
  directories with the most churn first (`git log --oneline -- <dir>` as a
  proxy), say you did, and offer the rest as a follow-up pass.

# Method

Sweep for these patterns, in order of payoff:

1. **Speculative generality**: abstractions with exactly one implementation,
   interfaces with one implementor, options and flags nothing sets, generics
   over one type. Evidence: count the implementations and callers.
2. **Pass-through layers**: wrappers and managers that forward without
   adding logic. Evidence: show the whole body is forwarding.
3. **Frameworks where a function would do**: DI containers, plugin systems,
   event buses, config registries for a codebase of the size that has one
   caller per part.
4. **Homegrown versions of what the platform has**: hand-rolled retries,
   caches, date handling, validation, pooling next to a stdlib or framework
   equivalent. Cite the replacement.
5. **The build-the-minimum ladder in reverse**: anything the ladder would
   not have written (see the 1337 rules: reuse, stdlib, platform,
   dependency, one line, minimum).

For every candidate, read the callers before judging. Over-engineering in
code with two callers and one use site is a quick win; the same shape under
a public API is a decision, and goes to Ask.

A cut merging near-duplicates into a shared helper saves only net lines: the
duplicates removed, minus the helper's body, comment, and the extra source/import
line at every call site. When that net is zero or negative, list it under
Simplify as "single definition" and leave it out of the Verdict's line count.

# Never flag

Validation, error handling, security, data-loss guards, accessibility, and
tests are never over-engineering, however abstract. A pattern that earns its
keep by having real variety behind it (two implementations that genuinely
differ, config that actually varies per deploy) is not speculative.

# Output

Plain text, in this order:

1. **Cut** — one line per item: `path:line` — what — the replacement (the
   function, stdlib call, framework feature). Ordered by lines saved,
   biggest first, callers already counted.
2. **Simplify** — alive and needed but fat: fold the layer, drop the unused
   option, collapse the two-implementation abstraction to the one that
   carries the behavior.
3. **Keep** — at most three lines: heavy-looking things that are
   load-bearing, one reason each. Silence means nothing qualified.
4. **Ask** — cuts that change a public surface or a documented decision,
   quoted in one line each. The user decides.
5. **Verdict** — one line: "N cuts, ~M lines, K decisions to make".

Rules: every line cites `path:line` and shows you counted the callers;
`1337: later:` markers in the code are prior review findings — mention them
where they overlap; you never edit files — the user applies the list or
asks you to.
