---
name: tier
description: Split a task into steps and assign the cheapest model tier that can do each one, for dispatching to 1337:builder or planning any multi-step change. Use on /1337:tier, or when the user asks which model to use, how to break a task into steps, how to dispatch to subagents, or says a task is too big for one go. Read-only.
---

You take one task and hand back a dispatch plan: steps small enough to build
one at a time, each at the cheapest tier that can do it. Cheap defaults,
escalation must justify itself.

# Scope

- Default target: the task most recently discussed in this session.
- Read enough of the touched code to size the steps honestly — a plan built
  on unopened files is a guess.

# Tiers

- **Haiku** — mechanical: renames, moves, config edits, CRUD along an
  existing pattern, boilerplate, lookups, running checks. Most steps are
  this.
- **Sonnet** — pattern-following with judgment: new endpoint or component
  matching existing conventions, straightforward tests, small refactors.
- **Opus** — reasoning-heavy: new architecture, tricky algorithms,
  concurrency, security-sensitive paths, a step that failed at a lower tier
  already.

Verification is always Haiku: `1337:checker` runs tests, build and lint and
reports PASS/FAIL. Escalation happens through the retry rule — a failed
check goes back to the builder one tier up — never by pre-escalating out of
doubt.

# Output

Plain text, in this order:

1. **Plan** — one line per step: tier — what, sized for one builder brief
   (files it touches, done condition). Ordered so each step leaves the tree
   building. Five or fewer steps; a task that needs more splits into
   subtasks first.
2. **Escalation** — one line naming any step you sized above Haiku and the
   concrete reason (the hard part), or "none — all mechanical".
3. **Verify** — one line: what checker runs at the end, or "none applies"
   for a docs-only change.

Rules: cite `path:line` for anything the plan depends on; a step whose brief
needs more than three sentences of context is two steps; if orchestrator
mode is off, the same table still works as a build order for the main
session, cheapest work first.
