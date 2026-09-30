# Anthropic Claude — model-specific prompting (May 2026)

Primary source: [Anthropic Claude prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) — the canonical reference, currently covering Opus 4.7 / 4.6, Sonnet 4.6, Haiku 4.5. Secondary: [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) (Sep 2025).

## What changed in Claude 4.6 / 4.7 (most important shifts)

These are the behavioral changes that break old prompts most often:

### 1. Literal instruction following
4.7 will not silently generalize. If you tell it "fix the bug on line 42," it fixes line 42 — not the related bug on line 50 it noticed. State scope explicitly: *"Apply this formatting to every section, not just the first one."* Anthropic call out this trade-off as a feature: more precision, less thrash.

### 2. Calibrated verbosity
4.7 calibrates response length to its judgment of task complexity, rather than a fixed verbosity. Simple lookups → short. Open-ended analysis → long. If your product depends on a specific length, prompt for it.

### 3. Less aggressive language, please
> "Where you might have said 'CRITICAL: You MUST use this tool when...', you can use more normal prompting like 'Use this tool when...'." — Anthropic prompting docs

Aggressive imperatives now overtrigger (the model uses tools too often, takes too many actions, etc.) and produce *worse* results than calm direct prose. This was specifically observed in 4.5/4.6 and continues in 4.7.

### 4. Adaptive thinking is the default
The old `thinking: {type: "enabled", budget_tokens: 32000}` is deprecated. The current pattern:

```python
thinking={"type": "adaptive"}
output_config={"effort": "high"}  # or low / medium / high / xhigh / max
```

Effort levels (4.7):
- `max` — diminishing returns, can overthink. Test before adopting.
- `xhigh` — best for hard coding/agentic work.
- `high` — sensible default for intelligence-sensitive tasks.
- `medium` — cost-sensitive workloads with intelligence trade-off.
- `low` — short, scoped, latency-sensitive. **4.7 respects `low` strictly** and may under-think; either accept that or raise effort.

### 5. Prefilled assistant turns: deprecated
On Claude 4.6+ and Mythos preview, prefilling the *last* assistant turn returns 400. Migrate to:
- Output formatting: use `<output_contract>` blocks in the system prompt.
- Eliminating preambles: instruct directly ("answer immediately, no preamble").
- Continuations: structure as new user turns or use `stop_sequences`.

## XML tags: still the native idiom

Anthropic's docs use XML tags everywhere because Claude is trained on them. Use them:

```xml
<instructions>...</instructions>
<context>...</context>
<example>...</example>
<documents>
  <document index="1">
    <source>filename.pdf</source>
    <document_content>...</document_content>
  </document>
</documents>
```

Nest tags when content has natural hierarchy. Use consistent tag names across prompts in a system.

## Long-context prompting

Anthropic's specific guidance for inputs >20k tokens:

1. **Put longform data at the top** — above query, instructions, examples. Reported up to 30% quality lift on multi-document tasks.
2. **Wrap each document** in `<document>` with `<source>` and `<document_content>` subtags.
3. **Ground responses in quotes**: ask Claude to first quote relevant passages, then answer. This cuts through noise.

## Tool use

- 4.7 uses tools *less often* than 4.6 by default and reasons more. If you want more tool calls, raise `effort` rather than prompting.
- For parallel tools: Claude 4.x natively parallelizes; you can push to ~100% with the explicit prompt block from the docs (`<use_parallel_tool_calls>`).
- For action-vs-suggestion ambiguity: 4.7 may suggest where you wanted action. If unsure, add `<default_to_action>` block; if you want hesitancy, add `<do_not_act_before_instructions>`.

## Subagent orchestration (4.6+)

- 4.6 has a strong predilection for subagents — sometimes spawns them where a direct grep would be faster.
- 4.7 spawns *fewer* subagents by default; if you need fan-out, prompt for it.
- Steerable both ways with a clear rule like: *"Use subagents when tasks can run in parallel, require isolated context, or involve independent workstreams. For simple sequential tasks, work directly."*

## Coding / agentic coding gotchas

Calibrated for 4.6/4.7 from the Anthropic docs:

- **Overengineering**: 4.5/4.6 tend to add abstractions, defensive code, premature flexibility. The official anti-overengineering block is in the prompting docs and is worth pasting verbatim into coding agents.
- **Test-passing over correctness**: Claude can hard-code to pass tests. Use the official "high-quality, general-purpose solution" block.
- **File creation churn**: 4.x sometimes creates scratch files for iteration. Tell it to clean up.
- **Hallucinations on unread code**: `<investigate_before_answering>` block is the canonical fix — never speculate about code you haven't opened.

## Frontend / design defaults (4.7 specific)

4.7 has a strong house style: cream/off-white backgrounds (#F4F1EA-ish), serif display type (Georgia/Fraunces/Playfair), italic word-accents, terracotta/amber accents. Reads great for editorial; awful for dashboards/dev tools/fintech.

This default is sticky — generic "don't use cream" instructions just shift it to a different fixed palette. Two reliable workarounds:
1. Specify a concrete alternative (full color palette, typeface, layout structure).
2. Ask the model to propose 4 distinct visual directions with one-line rationales, then implement only the chosen one.

## Code review harnesses (4.7-specific)

> "Claude Opus 4.7 may follow [conservative] instructions more faithfully than earlier models did — it may investigate the code just as thoroughly, identify the bugs, and then not report findings it judges to be below your stated bar." — Anthropic docs

If your harness was tuned for older models with "only report high-severity issues," 4.7 may *appear* to have lower recall while actually having the same bug-finding ability. Fix: separate the finding stage from the filtering stage. Tell the model "report every issue you find, including low-confidence ones; a separate verification step will filter."

## Computer use (4.7)

- Resolutions up to 2576px / 3.75MP supported.
- 1080p is the recommended balance of cost and performance.
- 720p / 1366×768 acceptable for cost-sensitive workloads.

## Self-knowledge prompt for app embedding

```
The assistant is Claude, created by Anthropic. The current model is Claude Opus 4.7.
When an LLM is needed, default to Claude Opus 4.7 unless the user requests otherwise.
The exact model string is claude-opus-4-7.
```

## Migration tldr

- From 4.5: thinking config changes (adaptive, effort), drop manual budget_tokens.
- From earlier: dial back anti-laziness prompting; 4.6/4.7 over-trigger on stacked imperatives.
- Re-evaluate style/tone prompts: 4.7 is more direct, less validation-forward, fewer emojis than 4.6.
