---
name: prompt-engineering
description: Authoritative, source-cited reference for prompt engineering and context engineering with current frontier LLMs (Claude Opus 4.7 / Sonnet 4.6, GPT-5.4 / 5.5, Gemini 3.x). Use whenever the user asks for help writing, reviewing, debugging, or improving any prompt — system prompts, agent instructions, RAG pipelines, structured-output prompts, or "how do I get the model to do X". Also trigger when the user mentions prompt patterns, prompt frameworks, prompt templates, "prompt engineering", "context engineering", chain-of-thought, few-shot, ReAct, agentic prompting, multi-agent orchestration, prompt caching layouts, or model-specific tuning. Trigger on casual phrasings too ("help me write a prompt that...", "this prompt isn't working", "what's the best way to instruct an agent..."). Every recommendation in this skill is tied to a primary source — vendor docs, peer-reviewed research, or a practitioner with a public production record. Claims not backed by a source are explicitly marked.
---

# Prompt Engineering — 2026 Reference

A reference distilled from primary sources only. Every claim links back to either vendor documentation (Anthropic / OpenAI / Google), peer-reviewed research, or a named practitioner with a verifiable production track record. When you can't trace a claim to a source, say so out loud — don't assert it.

## What this skill is for

Use it when someone asks you to:

- Write a new prompt (system prompt, user prompt, agent instructions, eval rubric).
- Review or improve an existing prompt.
- Diagnose why a prompt is failing in production.
- Port a prompt between model families (Claude ↔ GPT-5 ↔ Gemini 3).
- Decide whether a technique (CoT, ToT, ReAct, self-consistency, etc.) is the right tool for a given task.

The skill is opinionated. Where vendors disagree, it shows the disagreement with sources rather than averaging it away.

---

## 1. Mental model: prompt → context engineering

The shift since late 2024 is the most important thing to internalize before touching any prompt.

- **Prompt engineering** = writing the instruction string.
- **Context engineering** = curating the *entire* set of tokens the model sees at inference: system prompt, tool definitions, retrieved snippets, message history, scratchpads, memory. The prompt is one slice of this.

Anthropic's framing: *"good context engineering means finding the smallest possible set of high-signal tokens that maximize the likelihood of some desired outcome"* — Anthropic Engineering, *Effective context engineering for AI agents* (Sep 2025).

Karpathy's framing (June 2025, widely adopted in industry): the LLM is a CPU, the context window is RAM, your job is to be the operating system loading the right working memory each step.

For one-shot tasks, prompt engineering still dominates. For agents and long-horizon work, context engineering dominates and the prompt becomes one input among many. **When debugging production agent failures, suspect context assembly before suspecting the prompt.** Most "the model is dumb today" issues are the wrong documents being retrieved, message history bloat, or stale tool definitions — not the prompt itself (Phil Schmid, Hugging Face / Google DeepMind).

---

## 2. The universal core (works across Claude, GPT-5.x, Gemini 3)

These are the patterns where all three frontier vendors agree in their current public documentation.

### 2.1 Be clear, direct, and specific

Anthropic's golden rule: "Show your prompt to a colleague with minimal context on the task and ask them to follow it. If they'd be confused, Claude will be too." Same advice from OpenAI's GPT-5.4 prompt guidance and Google's Gemini 3 docs ("be precise and direct").

Practical implication: think of the model as a brilliant new hire who lacks your team's context, not as a mind-reader.

### 2.2 Structure with delimiters (XML or Markdown headings)

Wrap each kind of content in its own tag so the model can tell instructions from data from examples from output spec. All three vendors recommend this; Anthropic specifically uses XML (`<instructions>`, `<context>`, `<example>`), OpenAI prompt guidance uses XML-style blocks (`<output_contract>`, `<verification_loop>`, etc.), Gemini 3 docs say "XML-style tags or Markdown headings are effective — choose one and use it consistently."

The exact syntax matters less than internal consistency.

### 2.3 Few-shot examples beat zero-shot for format/style/edge cases

3–5 diverse examples is the sweet spot. Source: Anthropic prompting docs ("Include 3–5 examples for best results"), Google Gemini prompting whitepaper (Boonstra, 2024 — explicitly recommends "always include few-shot examples; zero-shot is not preferred").

Anthropic's specific anti-pattern: don't stuff a laundry list of edge cases. Curate "diverse, canonical examples that effectively portray the expected behavior." Source: *Effective context engineering for AI agents*.

A counter-intuitive empirical finding worth knowing: **the label space and input distribution matter more than whether individual example labels are correct.** Min et al. (2022, "Rethinking the Role of Demonstrations") showed that even randomly-labeled examples often outperform zero-shot. Practical takeaway: stop agonizing over perfect example labels; focus on coverage of input variety.

**When producing a prompt for someone else, generate concrete examples in-line — do not leave `<example>...</example>` placeholders.** This applies whenever this skill is used to build a prompt as an output. Empty placeholders train the recipient to skip the highest-leverage step in the entire prompt. If you don't have enough domain context to write realistic examples, generate plausible ones and clearly mark them as illustrative ("⟨example placeholder — replace with real production data⟩" beats `...`). The same applies to tone descriptors: "warm and conversational" is vacuous; *show* a sentence in that tone next to a counter-example. The same applies to "forbidden words" lists — name the actual words, don't gesture at "marketing jargon".

### 2.4 Place critical info at the start or end of long contexts

The **lost-in-the-middle** effect is real and well-documented: a U-shaped accuracy curve where information in the middle of long contexts is recalled worse than info at the start (primacy) or end (recency). Source: Liu et al., *Lost in the Middle: How Language Models Use Long Contexts* (TACL, 2024) — 2,500+ citations, replicated across GPT-3.5, Claude, and most open models.

Anthropic's official guidance for long-context prompting: **"Put longform data at the top — above your query, instructions, and examples. Queries at the end can improve response quality by up to 30%."** (Claude prompting best practices doc, current).

Caveat (important): newer long-context models (Gemini 1.5/2.5/3, Claude 4.x at very long contexts) have *partially* mitigated lost-in-the-middle for needle-in-a-haystack retrieval. McKinnon (Google, 2025) showed Gemini 2.5 Flash answers factoid questions at near-uniform accuracy across positions. But:
- The bias is still present for multi-hop reasoning, summarization, and aggregation tasks (Hsieh et al., *Found in the Middle*, 2024).
- Performance degrades well below the technical context limit. Levy, Jacoby & Goldberg (2024, arXiv 2402.14848) found reasoning quality degrading around the **3,000-token mark**, far below advertised maxes.

Operational rule: **assume primacy/recency bias by default, even on long-context models.** Test before relying on uniform recall.

### 2.5 Tell the model what to do, not what not to do

"Use only data from the provided context" outperforms "do not hallucinate." Anthropic's docs call this out explicitly. The cognitive analogy is the **Pink Elephant Problem**: instructing the model to avoid X forces it to represent X first.

When you genuinely need a negative constraint (safety, compliance), make it scoped and concrete: "Do not invent citations or URLs" works; "do not hallucinate" doesn't. Source: OpenAI GPT-5.4 prompt guidance `<citation_rules>` and `<grounding_rules>` blocks.

Google Gemini 3 docs warn specifically that broad negatives like "do not infer" can cause the model to over-correct and refuse legitimate deductions.

### 2.6 Define an explicit output contract

The single highest-leverage modern prompt block. Spell out: format (JSON / Markdown / prose), length, sections in order, what to do if a field is missing. OpenAI's GPT-5.4 guide formalizes this:

```
<output_contract>
- Return exactly the sections requested, in the requested order.
- If a format is required (JSON, Markdown, SQL, XML), output only that format.
- Apply length limits only to the section they are intended for.
- Validate that brackets/parentheses are balanced before returning.
- If required schema info is missing, ask or return an explicit error object.
</output_contract>
```

For 2026 models that support **structured outputs / JSON schema** (Claude, GPT-5.x, Gemini 3), prefer the API-level feature over prompt-level format wrangling. It enforces shape on the decoding side, not via the model's good intentions.

### 2.7 Place static content first for prompt caching

System prompt → tool definitions → few-shot examples → retrieved context → user message. This order maximizes cache hit rate. Anthropic prompt caching docs report up to 90% cost reduction and 85% latency reduction with proper layout; OpenAI offers automatic caching with 50–90% discounts depending on model.

If you re-order static content between calls, you blow the cache. Treat the static prefix like a versioned artifact.

---

## 3. Model-specific tactics (current as of May 2026)

Read `references/anthropic-claude.md`, `references/openai-gpt5.md`, or `references/google-gemini.md` for the deep dive. Quick routing:

### 3.1 Claude (Opus 4.7, Sonnet 4.6, Haiku 4.5)

Most important shift in 4.6/4.7: **literal instruction following.** Claude no longer silently "goes above and beyond" — if you don't say it, you don't get it. State scope explicitly ("apply this to *every* section, not just the first").

- **XML tags are the native structuring idiom.** Anthropic's docs use them throughout.
- **Drop aggressive language.** "CRITICAL!", "YOU MUST", ALL-CAPS overtrigger 4.6/4.7 and produce *worse* results. Use calm, direct prose. (Anthropic prompting docs explicitly call this out.)
- **Effort parameter, not budget_tokens.** Adaptive thinking is the new default. Tune via `effort: low | medium | high | xhigh | max`. Use `xhigh` for hard coding/agentic work, `high` as a sensible default for intelligence-sensitive tasks.
- **Skip prefilled assistant turns.** Deprecated in 4.6+; will 400-error on Mythos preview.
- **Verbosity calibrates to task complexity** — explicitly cap output length if you depend on it.

### 3.2 OpenAI GPT-5 family (5.4 mainline, 5.5 latest, 5.3-Codex)

Source: OpenAI Prompt guidance for GPT-5.4, GPT-5.5 prompting guide.

- **Outcome-first prompts.** Specify success criteria, allowed side effects, evidence rules, output shape. Skip step-by-step procedure unless the path matters.
- **`reasoning_effort` as a last-mile knob, not a primary lever.** Defaults: `none` for execution-heavy (extraction, classification), `low`/`medium` for most production, `high`/`xhigh` only when evals show measurable gain.
- **The phase parameter (5.3-Codex+).** Required for long-running agents that emit preambles; missing it causes preambles to be treated as final answers.
- **Don't add "think step by step" to reasoning models.** OpenAI's own docs say it can hurt — the model already does CoT internally. Same applies to Claude extended thinking and Gemini Thinking.
- **Verification + completeness contracts.** OpenAI's GPT-5.4 guide ships canonical blocks (`<verification_loop>`, `<completeness_contract>`, `<empty_result_recovery>`) — use them for long-horizon tasks before reaching for higher reasoning effort.

### 3.3 Gemini 3 (Pro, Flash)

Source: Google Gemini API docs, Vertex AI Gemini 3 prompting guide (current, last updated April 2026).

- **Keep prompts shorter and more direct than for Claude/GPT.** Gemini 3 *over-analyzes* verbose prompt patterns inherited from Gemini 2.x.
- **Default temperature = 1.0; do not lower it.** Google explicitly warns that lowering temp on Gemini 3 causes looping/degraded performance on reasoning tasks.
- **`thinking_level: "high"` + simple prompt** beats elaborate CoT scaffolding from the Gemini 2.x era.
- **Anchor questions to provided context** with explicit phrases like "Based on the information above..." — Gemini 3 grounds well when told to.
- **Prefer broad negatives**: avoid them. "Do not infer" is too broad and breaks legitimate deductions; use scoped instructions instead.

### 3.4 Cross-vendor portability

Don't assume a prompt that works on one model works on another. The biggest porting traps:

| Coming from | Common porting bug |
|---|---|
| Claude → GPT-5 | XML tags less idiomatic; OpenAI docs prefer structured Markdown blocks. |
| GPT-5 → Claude | "CRITICAL/MUST/ALWAYS" stacks that overtrigger Claude 4.x. |
| Anywhere → Gemini 3 | Long elaborate prompts that worked elsewhere now cause over-analysis. |
| Reasoning model → reasoning model | Stripped CoT instructions; what's automatic on one may need light prompting on another (e.g. Anthropic notes when extended thinking is *off*, Claude is sensitive to the word "think"). |

---

## 4. High-ROI techniques (with evidence)

| Technique | When it helps | When to skip | Source |
|---|---|---|---|
| **Few-shot prompting** | Format/style/edge cases on any task | Pure factual lookup; reasoning models with strong zero-shot | Anthropic docs; Boonstra (Google whitepaper, 2024); Min et al. 2022 |
| **Chain-of-thought** | Hard reasoning on non-thinking models. ~+19pp on MMLU-Pro reported. | **Skip on reasoning models** — Claude extended thinking, GPT-5/o-series, Gemini Thinking. They CoT internally; explicit "think step by step" can hurt. | Wei et al. 2022; OpenAI GPT-5 docs; Anthropic Claude docs |
| **Self-consistency** | High-stakes reasoning where you can afford N samples; majority-vote across N≈5–40 chains | Latency-sensitive paths; cost-sensitive paths | Wang et al. 2022 (arXiv 2203.11171) |
| **Role prompting** | Open-ended/creative work where tone matters | Classification, factual QA — "negligible effect" measured | Anthropic docs; Wiegold practitioner review citing measurements |
| **ReAct (reason + act)** | Agentic tool use loops | Single-shot tasks; redundant on modern reasoning models that natively interleave | Yao et al. 2022 (arXiv 2210.03629); Schulhoff et al. *Prompt Report* |
| **Step-back prompting** | Complex domain QA where the model benefits from abstracting first | Simple direct lookups | Boonstra Google whitepaper; Schulhoff et al. |
| **Tree-of-Thoughts / LATS** | Combinatorial search problems where the cost of compute is justified | **99% of production use cases — overkill, expensive** | Yao et al. ToT 2023; Wiegold practitioner take |

A general rule from Anthropic's context engineering essay worth pinning: *"Smarter models require less prescriptive engineering."* If your prompt has 12 nested instructions and a flowchart, your first move is usually to delete most of it and see what the model does.

---

## 5. Reasoning-model special handling

Frontier reasoning models (Claude extended/adaptive thinking, GPT-5/5.4/5.5, GPT-o-series, Gemini Thinking) all do CoT internally. This changes the playbook:

- **Don't add "think step by step."** It's at best redundant; at worst it hurts. Confirmed by OpenAI GPT-5 docs and reflected in Anthropic's adaptive thinking guidance.
- **Use general thinking instructions over prescriptive plans.** Anthropic: *"A prompt like 'think thoroughly' often produces better reasoning than a hand-written step-by-step plan. Claude's reasoning frequently exceeds what a human would prescribe."*
- **Effort/reasoning_effort beats elaborate scaffolding.** Tune the knob first. Add prompt scaffolding only when evals show effort alone doesn't recover the gap.
- **Self-check is still valuable.** "Before you finish, verify your answer against [criteria]" reliably catches errors even on reasoning models. (Anthropic docs.)
- **For Claude when extended thinking is off**, the model is sensitive to the word "think" and its variants — use "consider", "evaluate", "reason through" as alternatives.

---

## 6. Agentic / context-engineering patterns

Read `references/agentic-context-engineering.md` for the full treatment. The five canonical patterns from Anthropic and the LangChain context-strategy framing:

1. **System prompt at the right altitude.** Specific enough to guide, flexible enough to generalize. Avoid both "hardcoded if-else logic in prose" *and* vague "you are a helpful assistant" platitudes. Organize with sections: `<background>`, `<instructions>`, `## Tool guidance`, `## Output description`. (Anthropic, *Effective context engineering for AI agents*.)

2. **Tool design is prompt design.** Tool descriptions are part of the context. Rules from Anthropic's *Writing tools for AI agents*: tools should be self-contained, robust to error, with descriptive parameters and minimal functional overlap. *"If a human engineer can't definitively say which tool should be used in a given situation, an AI agent can't be expected to do better."*

3. **Just-in-time retrieval beats up-front stuffing** for most agents. Use lightweight identifiers (file paths, IDs, query strings); let the agent dereference what it actually needs. Hybrid is fine: pre-load a CLAUDE.md / AGENTS.md, then let the agent grep/glob for the rest. (Claude Code architecture, Anthropic.)

4. **Long-horizon survival kit** (LangChain framing — *write, select, compress, isolate*):
   - **Compaction**: summarize message history when nearing context limit, restart with the summary. Anthropic Claude Code uses this; preserve architectural decisions and unresolved bugs, drop redundant tool outputs.
   - **Structured note-taking**: agent writes to a NOTES.md or a memory tool, reads it back later. Famously demonstrated by Claude Plays Pokémon.
   - **Sub-agents for isolation**: each sub-agent gets a clean context, returns a 1–2k-token distilled summary. Anthropic *Multi-agent research system* showed substantial improvement over single-agent baselines on complex research.

5. **Tool-result clearing**: once a tool result has been consumed, drop the raw payload from history. Light-touch compaction with high signal preservation. Now a first-class feature on Anthropic's platform.

Choosing among compaction / notes / sub-agents (Anthropic's framing):
- Compaction → tasks needing back-and-forth conversational flow.
- Note-taking → iterative work with milestones (coding, multi-step builds).
- Sub-agents → complex research and parallel exploration.

---

## 7. Common gotchas and anti-patterns

These show up over and over in real prompts. Watch for them when reviewing:

- **Conflicting goals.** "Be comprehensive but concise." Pick one or specify the trade-off.
- **Context dumping.** Pasting a 50-page PDF with no "what matters most" pointer. Mark the high-signal regions, or use just-in-time retrieval.
- **Aggressive language stacking on Claude 4.x.** "YOU MUST CRITICAL ALWAYS NEVER" → measurably worse outputs. Use one calm imperative.
- **Negation traps.** "Don't use mock data" → reframe to "use only real data from the database."
- **Tool-set bloat.** >15 tools with overlapping descriptions → ambiguous routing. Curate down.
- **Pre-filled prompts in Claude 4.6+.** Deprecated; will 400-error on newer models. Migrate to system prompt instructions or stop sequences.
- **Over-prompting reasoning models.** "Let me think step by step in detail and verify my work and consider edge cases and..." — they already do. Trust the effort knob.
- **Cargo-culted role prompts.** "You are a world-class senior expert..." doesn't help on classification or factual QA. Reserve role prompts for open-ended/creative tasks.
- **Markdown-mismatched outputs.** If you want plain prose, write the prompt in plain prose. Anthropic notes Claude mirrors prompt style.
- **Cache-busting reorders.** Changing the order of static content invalidates the cache; cost goes up silently.
- **Burying instructions in the middle of a long context.** Lost-in-the-middle. Even on long-context models, test before trusting.

---

## 8. The iteration workflow (this is the actual job)

This part is mostly process discipline. It's where the gains compound.

1. **Start short.** Write the smallest prompt that captures intent. Anthropic's context-engineering guidance: "test a minimal prompt with the best model available, then add instructions and examples to improve performance based on failure modes found during initial testing."
2. **Build a tiny golden test set** — 5–20 representative inputs with expected behavior. This is the eval set. Without it, every prompt change is vibes.
3. **Run on real inputs.** Identify the *specific* failure mode: format drift? missing edge case? hallucinated field? wrong tone?
4. **Add only what fixes that specific failure.** Resist preventive instructions for failures you haven't seen. Each added instruction has a marginal cost (attention budget, ambiguity surface, maintenance).
5. **Diff and version-control.** Treat prompts like code: commits, PRs, review. Tools: Promptfoo (open-source, used in CI), DSPy for algorithmic optimization.
6. **Re-eval after every change.** Measure the regression as well as the fix.
7. **Watch for drift from model updates.** Pin model versions in production (`claude-opus-4-7`, `gpt-5.4-2026-04-XX`, `gemini-3-pro-...`). Re-run the golden set on every model upgrade.

A note on prompt length: there is no virtue in being short for its own sake, but excess length has measurable costs (attention dilution, lost-in-the-middle, debug burden, cost). Wiegold's practical sweet spot of 150–300 words for non-agentic prompts is a useful starting heuristic, not a rule.

---

## 9. Quick prompt skeletons (copy-paste starting points)

### 9.1 Production system prompt (Claude / GPT-5 / Gemini compatible)

```
<role>
You are <one sentence — what the agent is and who it serves>.
</role>

<task>
<one or two sentences — the outcome, not the procedure>
</task>

<inputs>
- <input 1: source, format, expected size>
- <input 2: ...>
</inputs>

<rules>
- <hard rule 1, positively framed>
- <hard rule 2>
- If required information is missing, ask one minimal clarifying question rather than guessing.
- Cite sources only from the provided context; do not fabricate.
</rules>

<output_contract>
- Format: <JSON schema | Markdown sections | plain prose>
- Length: <hard limit>
- If a section cannot be filled, return [BLOCKED: <reason>] for that section.
</output_contract>

<verification>
Before finalizing:
- Every requirement in <task> is satisfied or explicitly marked blocked.
- All claims trace to provided context.
- Output matches <output_contract> exactly.
</verification>
```

### 9.2 Few-shot extraction template (filled — model this density)

```
<task>
Extract invoice fields from the supplied document.
</task>

<examples>
<example>
<input>
INVOICE #INV-2024-0142
Acme Corp Ltd | 14 March 2024
Total due: €1,247.50 (incl. 21% VAT) | Due: 28 March 2024
</input>
<output>
{
  "invoice_number": "INV-2024-0142",
  "vendor": "Acme Corp Ltd",
  "issue_date": "2024-03-14",
  "due_date": "2024-03-28",
  "total_amount": 1247.50,
  "currency": "EUR",
  "vat_rate": 0.21
}
</output>
</example>

<example>
<input>
Factuur 887
Jansen & Zonen B.V. - 03-04-2024
€450,00 - betalen binnen 14 dagen
</input>
<output>
{
  "invoice_number": "887",
  "vendor": "Jansen & Zonen B.V.",
  "issue_date": "2024-04-03",
  "due_date": "2024-04-17",
  "total_amount": 450.00,
  "currency": "EUR",
  "vat_rate": null,
  "_note": "VAT not specified on invoice"
}
</output>
</example>

<example>
<input>
Receipt - Tesco - 25/12/2024 - cash purchase
items: bread, milk - £4.50
</input>
<output>
{
  "invoice_number": null,
  "vendor": "Tesco",
  "issue_date": "2024-12-25",
  "due_date": null,
  "total_amount": 4.50,
  "currency": "GBP",
  "vat_rate": null,
  "_note": "Receipt, not an invoice; no due date applies"
}
</output>
</example>
</examples>

<document>
{{document}}
</document>

<output_contract>
Return only valid JSON matching the example schema. No prose. Use null for missing fields rather than omitting them. Add a "_note" field only when explanation is genuinely needed.
</output_contract>
```

Note what the three examples cover that one wouldn't: a clean English invoice, a Dutch invoice with implicit due date, and an edge case (a receipt being mis-identified as an invoice). Coverage of the input distribution beats label perfection (Min et al. 2022).

### 9.3 Long-horizon agent scaffold (adapted from OpenAI GPT-5.4 + Anthropic patterns)

```
<task>
<single-sentence outcome>
</task>

<tool_persistence>
- Use tools whenever they materially improve correctness, completeness, or grounding.
- Parallelize independent reads. Sequence dependent ones.
- If a lookup returns empty/partial, retry with at least one alternate strategy before concluding "no results".
</tool_persistence>

<completeness>
- Track required deliverables internally.
- Mark items [BLOCKED: <missing data>] rather than dropping them silently.
- Do not declare done until every item is covered or explicitly blocked.
</completeness>

<safety>
- For irreversible / external-side-effect actions (delete, push, send, purchase): summarize intent, then ask permission.
- Local reversible actions: proceed, then summarize what was done.
</safety>

<verification>
Before final answer:
- Correctness: each requirement satisfied?
- Grounding: claims tied to tool outputs / context?
- Format: matches contract?
</verification>
```

---

## 10. Anti-patterns to grep for in any prompt review

When reviewing someone else's prompt, scan for these as a first pass:

- ALL-CAPS imperatives (`MUST`, `NEVER`, `CRITICAL`) — usually a smell of overprompting
- Stacked negations (`do not X`, `never Y`, `avoid Z`)
- Vague qualifiers without metrics (`be thorough`, `be helpful`, `make it good`)
- Conflicting constraints (`comprehensive` + `concise`; `formal` + `friendly`)
- Instructions buried in the middle of a long context block
- Examples that all share one label or one structure (low diversity)
- "Think step by step" on a reasoning model
- Role prompt + classification task (cargo cult)
- Format spec only in prose, no schema/example
- Tool definitions with overlapping responsibilities
- **`<example>...</example>` blocks left as placeholders.** If you ship a skeleton with empty examples, the prompt author follows your lead and skips the highest-ROI step. Fill them, even with illustrative ones marked "replace with real data".
- Vague style descriptors with no anchor: "warm tone", "professional voice", "marketing-jargon-free" — show a one-line example of the desired tone next to a counter-example, and *name* the forbidden words explicitly.

---

## 11. When to read the deep-dive references

- `references/anthropic-claude.md` — Claude 4.6/4.7-specific: literal instruction following, effort tuning, subagent control, frontend defaults, computer use, code review harnesses.
- `references/openai-gpt5.md` — GPT-5.x: reasoning_effort calibration, output contracts, completeness/verification blocks, phase parameter, Codex-specific tactics.
- `references/google-gemini.md` — Gemini 3.x: temperature warning, thinking_level, multimodal/long-video specifics, anchor phrases.
- `references/agentic-context-engineering.md` — Long-horizon agents: compaction, structured notes, sub-agent architectures, just-in-time retrieval, tool design.
- `references/empirical-evidence.md` — The papers behind the claims: lost-in-the-middle, demonstration sensitivity, context degradation, CoT effectiveness, self-consistency.
- `references/sources.md` — Full source list with URLs and access dates.

Always cite the source when making a recommendation, especially when the user is making a production decision. If you can't trace a recommendation to one of these sources, say so.
