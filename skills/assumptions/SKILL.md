---
name: assumptions
description: Audit a plan, spec, PRD, design doc or diff for unchecked assumptions that would flip the decision, each with what changes if it is wrong. Use on /1337:assumptions, or when the user asks what a plan assumes, whether a plan is safe to act on, or to pressure-test a design before building. Read-only.
---

You audit a plan for load-bearing assumptions: the things it silently treats as
true that would change the design if false. The output is a short list, not an
essay.

# Scope

- Default target: the plan, spec or diff most recently discussed in this
  session. If the user names a document, read that.
- No target in sight means ask for one. Do not audit nothing.

# Method

Walk the plan and collect every claim it acts on: chosen technology, data
model, API or flag behavior, version or limit, price or quota, traffic or team
size, "X already does this", "nothing else uses this", "safe to delete",
backward compatibility, anything that may have changed since your training
data ends.

Then, per claim, in order:

1. Verify what is cheap to check now — read the code, run the command, open
   the installed package, check the config. A checked fact is not an
   assumption; it drops off the list and counts toward the verified list.
2. An unchecked claim that would NOT change the design if wrong is not
   load-bearing. Drop it. Do not pad the list.
3. One unchecked claim that would flip the whole plan? Ask the one question
   that resolves it before writing the list, if the user is present to answer.

Never state an unverified claim in the same voice as a verified one.

# Output

Plain text, in this order:

1. **Verified** — one line per checked fact: the fact and the `path:line` or
   command output that settles it. This section proves the plan rests on
   ground you actually stood on.
2. **Assumptions** — one line each, ordered by blast radius, biggest first:
   the assumption — what changes if it is wrong. No empty section: nothing
   assumed means say so and show the verified list.
3. **Verdict** — one line: "safe to act on the verified facts alone",
   "holds if <assumption> holds", or "do not build before resolving <N>".

Rules: cite `path:line` for every verified claim; never guess; do not
re-argue a decision the user already made this session — audit what the
decision still depends on.
