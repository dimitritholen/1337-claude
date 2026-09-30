# Google Gemini 3 — model-specific prompting (May 2026)

Primary sources:
- [Gemini API: Prompt design strategies](https://ai.google.dev/gemini-api/docs/prompting-strategies) — last updated April 28, 2026.
- [Gemini 3 prompting guide on Vertex AI / Gemini Enterprise Agent Platform](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/start/gemini-3-prompting-guide) — last updated April 30, 2026.
- [Gemini 3 Developer Guide](https://ai.google.dev/gemini-api/docs/gemini-3).
- [Lee Boonstra, *Prompt Engineering* (Google whitepaper, Sept 2024 / updated 2025)](https://www.kaggle.com/whitepaper-prompt-engineering) — the canonical 60+ page Google reference, still the most-cited Gemini-era guide.

Gemini 3 is meaningfully different to prompt than Gemini 2.x. The most common porting bug is over-prompting: prompts that worked for 2.x cause Gemini 3 to over-analyze.

## What changed between Gemini 2.x and Gemini 3

Gemini 3's default behavior is **direct and concise**. Old patterns inverted:

| Gemini 2.x pattern | Gemini 3 reality |
|---|---|
| Long elaborate CoT scaffolds | Use `thinking_level: "high"` + simple prompt |
| Lower temperature for determinism | **Keep at default 1.0** — lowering causes looping/degraded reasoning |
| Verbose prompt patterns to coax structure | Direct one-line task descriptions work |
| Repeating constraints every turn | Only restate when the model drifts |
| "Be helpful and detailed" framing | Default is concise; explicitly request "chatty" if you want it |

## Core Gemini 3 rules (from Google's current docs)

### 1. Be precise and direct
> "State your goal clearly and concisely. Avoid unnecessary or overly persuasive language." — Gemini 3 prompting guide

> "Gemini 3 responds best to direct, clear instructions. It may over-analyze verbose or overly complex prompt engineering techniques used for older models." — Gemini 3 Developer Guide

### 2. Consistent structure
XML-style tags (`<context>`, `<task>`) **or** Markdown headings — both work. Pick one and use it throughout the prompt. Don't mix.

### 3. Define ambiguous parameters explicitly
If you use a domain-specific term, define it in the prompt. Gemini 3 will be precise about whatever you specify; it will not infer specialized definitions.

### 4. Output verbosity
Default is concise. To get a more conversational/detailed response, explicitly request it: *"Explain this as a friendly, talkative assistant."*

### 5. Place the question at the end of long context
> "When working with large datasets (entire books, codebases, or long videos), place your specific instructions or questions at the end of the prompt, after the data context. Anchor the model's reasoning to the provided data by starting your question with a phrase like, 'Based on the information above...'." — Gemini 3 Developer Guide

This matches the universal long-context guidance but Gemini's docs are the most explicit about the anchor phrase.

### 6. Temperature = 1.0; do not lower it
This is unusual industry-wide and worth flagging. Google's exact wording:
> "We strongly recommend keeping the temperature parameter at its default value of 1.0. Gemini 3's reasoning capabilities are optimized for the default temperature setting and don't necessarily benefit from tuning temperature. Changing the temperature (setting it to less than 1.0) may lead to unexpected behavior, looping, or degraded performance, particularly with complex mathematical or reasoning tasks."

If your team's defaults set temperature low for "deterministic outputs," remove that on Gemini 3.

### 7. Avoid broad negative constraints

From the Vertex AI guide:
> "Providing open-ended system instructions like 'do not infer' or 'do not guess' may cause the model to over-index on that instruction and fail to perform basic logic or arithmetic or synthesize information found in different parts of a document."

Replace broad negatives with scoped positives: *"Use only the provided text for your deductions and avoid using outside knowledge."*

### 8. Thinking levels (Gemini 3 specific)

`thinking_level: "high"` for hard reasoning; `"low"` + system instruction `"think silently"` for low-latency. Migration tip from Google: if you previously used thinking budgets, switch to thinking levels per the cookbook migration guide.

### 9. Multimodal and long-form video

- Gemini 3 Pro can process up to ~2 hours of video.
- For time-based questions: ask specifically ("summarize events between 5:30 and 8:00").
- For multimodal grounding: state what to compare ("compare the transcript to the written proposal").
- Test the new `media_resolution_high` setting if you relied on dense document parsing behavior in 2.x.

### 10. Image generation (Gemini 3 Pro Image / 3.1 Flash Image)

- Uses reasoning before generation; can ground via Google Search before producing imagery.
- Multi-turn editing via "Thought Signatures" preserves visual context between turns.
- Conversational editing: "make the background a sunset" — works without re-uploading the source image.

## The 5-block reliable pattern (Boonstra whitepaper + practitioner consensus)

For Gemini specifically, this five-block layout is what Google's whitepaper structures everything around and what most production users converge on:

```
<role>
You are <one-sentence persona>.
</role>

<goal>
<single-sentence outcome>
</goal>

<constraints>
- <hard rule 1>
- <hard rule 2>
- US English / 3 bullets ≤120 words / etc.
</constraints>

<examples>
<example>
<input>...</input>
<output>...</output>
</example>
</examples>

<output_format>
<exact format spec or schema>
</output_format>
```

The Boonstra whitepaper additionally documents **step-back prompting**: ask the model to first abstract / step back before answering the specific question. Effective for complex domain QA where direct factual lookup misses the structural reasoning.

## Migration from Gemini 2.x to 3 (Google's official tldr)

1. **Strip CoT scaffolding.** Use `thinking_level: "high"` and simplify the prompt.
2. **Remove explicit temperature setting.** Use the default of 1.0.
3. **Test PDF / document parsing.** Try `media_resolution_high` if you relied on specific 2.x behavior.
4. **Expect token usage shifts.** PDFs may use more tokens; videos use less.
5. **Trim repeated instructions.** Gemini 3 maintains conversational context; restate only on drift.
6. **Audit for accidental over-prompting.** If your 2.x prompt is >300 words, try cutting it 50% and see if quality changes — often it doesn't.

## Working with knowledge cutoffs

If you depend on currency, Google's docs recommend an explicit reminder:

> *"For time-sensitive user queries that require up-to-date information, you MUST follow the provided current time (date and year) when formulating search queries in tool calls. Remember it is 2026 this year."*

And for grounding:

> *"You are a strictly grounded assistant limited to the information provided in the User Context. In your answers, rely **only** on the facts that are directly mentioned in that context."*

These are lifted verbatim from the current Google docs and tested in production by the Gemini team.

## Anti-patterns specific to Gemini 3

- Long elaborate prompts ported from Gemini 2.x or other providers.
- Lowering temperature for "more deterministic" output → loops.
- Broad negative constraints ("do not infer") → blocks legitimate reasoning.
- Forgetting the anchor phrase ("Based on the information above...") on long context.
- Assuming 2M-token windows mean you can dump everything — placement still matters.
- Treating thinking_level as the only knob — pair it with prompt simplification.
