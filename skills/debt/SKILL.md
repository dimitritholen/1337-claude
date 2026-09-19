---
name: debt
description: Sweep a repo or directory for accumulated debt — TODO/FIXME/HACK markers, dead code, obsolete workarounds, stale dependencies — and hand back a delete-ledger ordered by payoff. Use on /1337:debt, or when the user asks what can be deleted, what is dead, to clean up, pay down debt or find quick wins. Read-only; never edits.
---

You sweep the codebase for weight the project carries for nothing and hand
back a ledger of what to delete. Deleting is the cheapest maintenance there
is, but a wrong "delete this" costs trust — evidence for every line.

# Scope

- Default target: the repo in the session's working directory.
- If the user names a directory or module, sweep that. A named subdirectory
  gets depth; the whole repo gets breadth.

# Method

Sweep in this order, stopping when the ledger is long enough to act on:

1. **Markers**: `TODO`, `FIXME`, `HACK`, `XXX`, `WORKAROUND`, plus
   commented-out code blocks. Greppable, high signal.
2. **Dead code**: exported functions, classes and flags with no callers.
   Never claim "unused" from a single grep — check call sites, string
   references, config and templates, then label it verified or suspected.
   The assumptions rule applies with full force here.
3. **Obsolete workarounds**: guards for versions, platforms or bugs that the
   current manifests and configs show are gone (check `package.json`,
   `requirements.txt`, `go.mod`, CI matrices, and so on).
4. **Stale dependencies**: declared but unimported, or imported from one
   line that a stdlib call could replace.

# Output

Plain text, in this order:

1. **Delete** — one line per item, ordered by payoff: `path:line` — what —
   why it is safe, with the evidence ("zero references outside this file,
   checked via grep for `<symbol>`"). Mark any item you could not fully
   verify as **suspected** and say what would settle it.
2. **Ask** — markers that are decisions in disguise ("TODO: decide whether
   we keep the flag"), quoted in one line each. Someone must decide; that is
   not yours to make.
3. **Verdict** — one line: "N items, ~M lines deletable, K suspected".

Rules: every delete line carries its evidence or its suspected label; do not
flag test fixtures, generated code, or vendored files as dead; a `TODO` with
a date or issue link that is still open is not debt, it is a plan.
