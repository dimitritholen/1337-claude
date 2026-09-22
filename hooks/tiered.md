# Tiered mode

Every `1337:builder` dispatch gets its model from Jev, TypeSafe's decision
model, not from your own read of the step.

- Split the change into steps first, as `/1337:tier` does: five or fewer,
  each one builder brief (files it touches, the change, done condition).
  Then run the router once with all of them. Write the JSON to a file under
  the scratchpad or temp directory and pass its path; send titles and briefs
  only, never file contents:
  ```bash
  python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" /path/to/steps.json
  ```
  where the file holds `{"task": "<one or two lines>", "steps": [{"id": 1,
  "title": "<step>", "brief": "<files, the change>"}]}`.
- Call `1337:builder` with `model` set to the `tier` the router printed for
  that step. A step marked `escalated: true` already moved one tier up; do
  not raise it again.
- A single-step change still goes through the router: one step, one call.
- This is enforced, not advice: a hook refuses a `1337:builder` dispatch when
  the router never ran this session, when every routed step is already
  spent, or when the dispatched model is not one of the tiers still owed,
  and its message says which. One routing call licenses exactly as many
  builder dispatches as it routed steps — dispatch more than that and route
  again first. `CLAUDE_1337_ROUTE_GUARD=off` turns the check off.
- A failed check goes back to the builder one tier above the routed tier,
  once; if it fails again, take over the diagnosis yourself. The guard
  allows that one retry once the step's routed slot is spent — one tier up
  from what it routed, never a bigger jump, never twice, and never for a
  step routed to Opus.
- Exit 3 means no key: say so in one line, offer `/1337:visual setup` once,
  and size the rest of the session's steps by hand from the Tiers section
  of the tier skill. Exit 4 means the call failed: size this dispatch by
  hand and try the router again on the next one. Never retry in a loop.
- Name the tier and Jev's confidence in the line that dispatches each step,
  so the user can see why a step went to Opus.
- The dispatch nudge fires in tiered mode when code steps run without a builder
  dispatch, and means the router was never consulted; dispatch the next step
  through it.
