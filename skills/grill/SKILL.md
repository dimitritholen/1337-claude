---
name: grill
description: Grill the user relentlessly about a plan, decision, or idea, sharpening the domain model and recording settled decisions as it goes. Use on /1337:grill, or when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Format a round like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.

## With docs

As terms and decisions settle, don't let them sit only in the transcript. Apply
the [domain-modeling](../domain-modeling/SKILL.md) skill (`/1337:domain-modeling`)
right there in the round: sharpen the term or record the decision in
`CONTEXT.md`, or offer an ADR under `docs/adr/` when it earns one.

When tasqx MCP tools are present (`tasqx_add_memory` is in this session's tool
list), also record each settled decision there: the ruling in the first line,
the why under it, this session as source — unless the repo already has its own
ADR or docs home (`CONTEXT.md`, `docs/adr/`), which wins and is the only place
the decision goes.
