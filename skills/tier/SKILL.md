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

# Route with Jev

With a stored OpenRouter or TypeSafe key, the tier per step comes from Jev,
TypeSafe's decision model, not from your own read. Split the task into steps first,
then run the router once with every step:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <<'EOF'
{"task": "<the task in one or two lines>",
 "steps": [{"id": 1, "title": "<step>", "brief": "<files, the change>"}]}
EOF
```

It prints one JSON object: per step the `tier`, Jev's `confidence` and
`probabilities`, and `escalated: true` where confidence fell under the floor
(0.5, or `CLAUDE_1337_TIER_FLOOR`) and the step moved one tier up. Use those
tiers in the plan and cite the confidence in the Escalation line. Send only
titles and briefs, never file contents: the router needs the shape of the
work, not the code.

A non-zero exit means no routing happened: 3 is a missing key (offer
`/1337:visual setup` once, which stores it for good), 4 a failed call, and
stderr says which. Size the steps by hand with the Tiers above and
say in one line that Jev was not used and why. Never retry in a loop.

# Output

Plain text, in this order:

1. **Plan** — one line per step: tier — what, sized for one builder brief
   (files it touches, done condition). Ordered so each step leaves the tree
   building. Five or fewer steps; a task that needs more splits into
   subtasks first.
2. **Escalation** — one line naming any step sized above Haiku and the
   concrete reason (the hard part, or Jev's confidence when the router
   escalated it), or "none — all mechanical".
3. **Verify** — one line: what checker runs at the end, or "none applies"
   for a docs-only change.

Rules: cite `path:line` for anything the plan depends on; a step whose brief
needs more than three sentences of context is two steps; if orchestrator
mode is off, the same table still works as a build order for the main
session, cheapest work first.
