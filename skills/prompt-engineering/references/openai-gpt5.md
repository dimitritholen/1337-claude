# OpenAI GPT-5 family — model-specific prompting (May 2026)

Primary sources:
- [OpenAI Prompt guidance for GPT-5.4](https://developers.openai.com/api/docs/guides/prompt-guidance) — current mainline, best documented.
- [GPT-5.5 prompting guide](https://developers.openai.com/cookbook/examples/gpt-5/gpt-5-5_prompting_guide) — released April 2026.
- [GPT-5.1 prompting guide](https://cookbook.openai.com/examples/gpt-5/gpt-5-1_prompting_guide), [GPT-5.2 guide](https://cookbook.openai.com/examples/gpt-5/gpt-5-2_prompting_guide), [Codex prompting guide](https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide).
- [Latest model docs](https://developers.openai.com/api/docs/guides/latest-model).

The GPT-5 family fragmented quickly: 5, 5.1, 5.2 (more deliberate scaffolding), 5.3-Codex (coding-tuned), 5.4 (current mainline), 5.5 (latest). Each guide adds patterns; later models inherit the earlier patterns. This reference summarizes what's stable across the family and flags model-specific shifts.

## The GPT-5 prompting playbook

### 1. Outcome-first prompts

GPT-5.5 release notes call this out explicitly: "describe the expected outcome, success criteria, allowed side effects, evidence rules, and output shape. Avoid step-by-step process guidance unless the exact path matters."

This is the opposite of 2023-era prompting. Don't write the recipe; write the success criteria.

### 2. Reasoning effort is a last-mile knob, not the primary lever

OpenAI defaults are:

- `none` — execution-heavy: workflow steps, field extraction, support triage, structured transforms. Often performs well for action-selection on 5.4.
- `low` — latency-sensitive tasks where a small amount of reasoning helps.
- `medium` — most production workloads, especially research-heavy or multi-doc synthesis. **GPT-5.5 defaults to medium**.
- `high` / `xhigh` — only when evals show measurable gain. Diminishing returns and cost both spike.

OpenAI's explicit guidance: before raising effort, first add `<completeness_contract>`, `<verification_loop>`, and `<tool_persistence_rules>` to your prompt. If those don't help, *then* raise effort.

### 3. Canonical prompt blocks (use them)

OpenAI ships these as copy-pasteable blocks in their docs. They're battle-tested:

**Output contract:**
```
<output_contract>
- Return exactly the sections requested, in the requested order.
- If the prompt defines a preamble, analysis block, or working section, do not treat it as extra output.
- Apply length limits only to the section they are intended for.
- If a format is required (JSON, Markdown, SQL, XML), output only that format.
</output_contract>
```

**Verification loop (lightweight; before high-impact actions):**
```
<verification_loop>
Before finalizing:
- Check correctness: does the output satisfy every requirement?
- Check grounding: are factual claims backed by the provided context or tool outputs?
- Check formatting: does the output match the requested schema or style?
- Check safety and irreversibility: if the next step has external side effects, ask permission first.
</verification_loop>
```

**Completeness contract (long-horizon multi-item work):**
```
<completeness_contract>
- Treat the task as incomplete until all requested items are covered or explicitly marked [blocked].
- Keep an internal checklist of required deliverables.
- For lists, batches, or paginated results: determine expected scope, track processed items, confirm coverage before finalizing.
- If any item is blocked by missing data, mark it [blocked] and state exactly what is missing.
</completeness_contract>
```

**Empty-result recovery (research / retrieval workflows):**
```
<empty_result_recovery>
If a lookup returns empty, partial, or suspiciously narrow results:
- do not immediately conclude that no results exist
- try at least one or two fallback strategies (alternate query wording, broader filters, prerequisite lookup, alternate source)
- only then report that no results were found, along with what you tried
</empty_result_recovery>
```

**Tool persistence (multi-step tool use):**
```
<tool_persistence_rules>
- Use tools whenever they materially improve correctness, completeness, or grounding.
- Do not stop early when another tool call is likely to materially improve correctness or completeness.
- Keep calling tools until: (1) the task is complete, and (2) verification passes.
- If a tool returns empty or partial results, retry with a different strategy.
</tool_persistence_rules>
```

**Citation lock-down (research / RAG):**
```
<citation_rules>
- Only cite sources retrieved in the current workflow.
- Never fabricate citations, URLs, IDs, or quote spans.
- Use exactly the citation format required by the host application.
- Attach citations to the specific claims they support, not only at the end.
</citation_rules>

<grounding_rules>
- Base claims only on provided context or tool outputs.
- If sources conflict, state the conflict explicitly and attribute each side.
- If the context is insufficient or irrelevant, narrow the answer or say you cannot support the claim.
- If a statement is an inference rather than a directly supported fact, label it as an inference.
</grounding_rules>
```

### 4. The phase parameter (GPT-5.3-Codex+)

Long-running agents emit "preamble" messages — short user-visible updates ("I'm going to start by checking the package.json...") before tool calls. Without the `phase` parameter on assistant items, the API can mistake a preamble for the final answer and stop early.

Operational rules:
- `phase` is on assistant output items only — never user messages.
- If you replay assistant history yourself, **preserve original phase values**.
- Easier path: use `previous_response_id` so OpenAI handles state.
- Missing/dropped phase causes "stops early" bugs that look like model regression but are integration regression.

This applies to GPT-5.3-Codex, GPT-5.4, and forward.

### 5. User-facing preambles (the "tell me what you're doing" pattern)

GPT-5.5 update: before any tool calls for a multi-step task, send a short user-visible message acknowledging the request and stating the first step. Keeps long-running tasks from feeling like the model crashed.

Sample:
```
<user_updates_spec>
- Send a 1-sentence acknowledgment + first step before the first tool call.
- Provide updates roughly every 30 seconds while working.
- Each update: 1 sentence on outcome + 1 sentence on next step.
- Do not narrate routine tool calls.
- For substantial work, you may send one longer plan after gathering enough context.
</user_updates_spec>
```

### 6. Verbosity / output-shape control

GPT-5.x has both an API-level `verbosity` parameter and prompt-level controls. Use both. GPT-5.4 onwards interprets length guidance literally:

```
<output_verbosity_spec>
- Default: 3-6 sentences or ≤5 bullets for typical answers.
- For yes/no + short explanation: ≤2 sentences.
- For complex multi-file tasks: 1 short overview paragraph then ≤5 bullets tagged: What changed / Where / Risks / Next steps / Open questions.
</output_verbosity_spec>
```

**Specific to 5.4 frontends and structured writing:** the model defaults to nested bullets and over-formatting. If you want clean prose:
```
Never use nested bullets. Keep lists flat. Use only `1. 2. 3.` numbered markers (not `1)`).
```

### 7. Reasoning + format coexistence

If a request requires reasoning *and* JSON, format usually wins drift battles. Prefer the structured outputs / JSON Schema feature on the API side rather than relying on prose instruction.

### 8. Smaller models in the family (5.4-mini, 5.4-nano)

OpenAI's explicit guidance:

**5.4-mini**:
- More literal than the mainline; makes fewer assumptions.
- Strong on clearly structured tasks; weaker on implicit workflows and ambiguity.
- May default to follow-up questions; suppress explicitly if you don't want them.
- Specify the **full execution order** when tools or side-effects matter.
- Don't rely on "you MUST" — use numbered steps and decision rules.
- Separate "do the action" from "report the action."
- Specify packaging directly (length, citation style, follow-up Q behavior).

**5.4-nano**:
- Use only for narrow, well-bounded tasks.
- Prefer closed outputs: enums, labels, short JSON, fixed templates.
- Don't try multi-step orchestration; route planning-heavy tasks to a stronger model.

### 9. Coding agents (5.3-Codex / 5.4)

Tactics from the Codex prompting guide:

- Use `rg` over `grep` (faster).
- For shell commands: only run via the terminal tool; never "run" tool names as bash.
- For patches: use the named `apply_patch` implementation, not bash.
- After changes: lightweight verification (build / smoke test / lint) before declaring done.
- AGENTS.md is automatically loaded by codex-cli — model is trained to closely adhere to its instructions.

### 10. Migration cadence

OpenAI's explicit advice for GPT-5.5 migration: **don't carry over your old prompt stack.** Start with the smallest prompt that preserves the product contract; tune reasoning effort, verbosity, tool descriptions, output format against representative examples.

For 5.4 → 5.5: medium reasoning is the new default. For latency-sensitive paths, evaluate `low` before `none` — multi-step decision-making still benefits from some reasoning.

### 11. Anti-patterns specific to GPT-5

- Adding "think step by step" to a reasoning model — actively counterproductive (per OpenAI's own docs).
- Step-by-step procedure when only the outcome matters — over-constrains the model.
- Skipping the phase parameter on long-running Codex flows — causes early-stop bugs.
- Using `xhigh` reasoning by default — high cost, often diminishing returns. Prove the gain on evals first.
- Free-form output for multi-stage agents — use the canonical blocks instead.
- Mid-conversation instruction changes without scope tags — use `<task_update>` blocks with explicit scope ("for the next response only" / "the task has changed").
