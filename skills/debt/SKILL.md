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

1. **Deferred cuts**: `1337: later:` markers — prior `/1337:review` findings
   the user chose to keep for now. Each carries its own reason; your job is
   to surface them so "later" does not quietly become "never".
2. **Markers**: `TODO`, `FIXME`, `HACK`, `XXX`, `WORKAROUND`, plus
   commented-out code blocks. Greppable, high signal.
3. **Dead code**: exported functions, classes and flags with no callers.
   Never claim "unused" from a single grep — check call sites, string
   references, config and templates, then label it verified or suspected.
   The assumptions rule applies with full force here.
4. **Obsolete workarounds**: guards for versions, platforms or bugs that the
   current manifests and configs show are gone (check `package.json`,
   `requirements.txt`, `go.mod`, CI matrices, and so on).
5. **Stale dependencies**: declared but unimported, or imported from one
   line that a stdlib call could replace.

# Output

Plain text, in this order:

1. **Deferred** — one line per `1337: later:` marker: `path:line` — the cut —
   the reason it was deferred, quoted from the marker. These re-open the
   decision, they do not auto-delete; ask whether now is the time for any of
   them.
2. **Delete** — one line per item, ordered by payoff: `path:line` — what —
   why it is safe, with the evidence ("zero references outside this file,
   checked via grep for `<symbol>`"). Mark any item you could not fully
   verify as **suspected** and say what would settle it.
3. **Ask** — markers that are decisions in disguise ("TODO: decide whether
   we keep the flag"), quoted in one line each. Someone must decide; that is
   not yours to make.
4. **Verdict** — one line: "N deferred, M deletable, K suspected".

Rules: every delete line carries its evidence or its suspected label; do not
flag test fixtures, generated code, or vendored files as dead; a `TODO` with
a date or issue link that is still open is not debt, it is a plan.
