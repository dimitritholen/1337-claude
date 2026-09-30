# Empirical evidence — the research behind the claims

Every recommendation in the main SKILL.md has at least one source. This file collects the academic / empirical sources, with the paper, the claim, the evidence type, and the production-relevance.

## Foundational surveys

### The Prompt Report (Schulhoff et al., 2024-2025)
- **Citation**: arXiv:2406.06608, latest version Feb 2025.
- **What it is**: The most comprehensive academic prompt engineering survey to date. Documents 58 LLM prompting techniques + 40 multimodal techniques, with a vocabulary of 33 standard terms.
- **Why it matters**: When you're trying to remember what a technique is called or how it relates to others, this is the reference. The Methodological Survey is grounded in PRISMA-guided review of 1,500+ papers.
- **Caveat**: comprehensive, not opinionated — lists techniques without telling you which to skip.

### A Systematic Survey of Prompt Engineering in Large Language Models (Sahoo et al., 2024-2025)
- **Citation**: arXiv:2402.07927, v2 March 2025.
- **What it is**: Categorizes prompt engineering by application domain and methodological foundation; covers zero-shot, few-shot, CoT, ToT, ReAct, RAG, etc.
- **Why it matters**: Application-oriented framing complements the Schulhoff survey's technique-oriented framing.

### Boonstra, *Prompt Engineering* whitepaper (Google, Sept 2024)
- **What it is**: 60+ page Google practitioner whitepaper, originally Vertex AI focused. Covers temperature/top-K/top-P, sampling, zero/one/few-shot, system/role/contextual, step-back, CoT, self-consistency, ToT, ReAct, automatic prompt engineering.
- **Why it matters**: One of the most-cited Gemini-era prompt engineering references. Practitioner-grade, includes specific recommended starting values.
- **Notable specific claim**: explicitly recommends **always using few-shot examples; zero-shot is not preferred**.

## Lost-in-the-middle and positional bias

### Liu et al., *Lost in the Middle: How Language Models Use Long Contexts* (TACL, 2024)
- **Citation**: doi:10.1162/tacl_a_00638. 2,500+ citations.
- **Finding**: U-shaped accuracy curve in multi-document QA — best at start (primacy) and end (recency) of context, ~30%+ accuracy drop in the middle. Replicated across GPT-3.5 and Claude.
- **Production implication**: Place critical instructions and high-priority context at the start or end of long prompts. Do not bury them in the middle.

### Hsieh et al., *Found in the Middle* (2024)
- **Citation**: arXiv:2403.04797.
- **Finding**: Models exhibit a U-shaped *positional attention bias* independent of content relevance. Models do attend to relevant middle context but get distracted by leading/ending context.
- **Production implication**: The bias is not just about retrieval — it's at the attention mechanism level. Re-ranking documents to place relevant ones at start/end actually helps.

### McKinnon (Google), *Retrieval Quality at Context Limit* (2025)
- **Citation**: arXiv:2511.05850.
- **Finding**: Gemini 2.5 Flash answers needle-in-a-haystack with near-uniform accuracy regardless of position, including near max context. Attributes improvement to ALiBi-style position encoding and training on needle-in-haystack tasks.
- **Production implication**: For *simple factoid lookup* on Gemini 2.5+ and likely Claude 4.x at moderate context, lost-in-the-middle is largely solved. For *aggregation, summarization, multi-hop reasoning*, the bias persists.

### Kuratov et al. / Levy, Jacoby & Goldberg, *Same Task, More Tokens* (2024)
- **Citation**: arXiv:2402.14848.
- **Finding**: Reasoning quality on standardized tasks degrades around the **3,000-token mark**, far below advertised context windows.
- **Production implication**: Even when you have a 200k or 1M token context, reasoning starts degrading at the low thousands. Long context is for retrieval, not for piling reasoning load.

### Hengle et al. / others, *Positional Biases Shift as Inputs Approach Context Window Limits* (2025)
- **Citation**: arXiv:2508.07479.
- **Finding**: Lost-in-the-middle effect interacts with input-length-relative-to-context-window. As input nears window size, primacy bias drops and the LiM effect attenuates. Effect is observable on inputs ~6k tokens but disappears in studies using ~100k inputs.
- **Production implication**: Don't generalize from one paper's evaluation length. Test your specific use case.

## Few-shot and demonstrations

### Min et al., *Rethinking the Role of Demonstrations* (EMNLP 2022)
- **Citation**: arXiv:2202.12837.
- **Finding**: Few-shot performance largely persists when example labels are *randomized*. The label space, format, and input distribution matter more than the correctness of individual labels.
- **Production implication**: Stop agonizing over "perfect" labels. Focus on coverage of the input distribution and consistent formatting. Do test with correct labels for your final eval; the finding is about robustness, not a recipe to use random labels.

### Lu et al., *Fantastically Ordered Prompts* (ACL 2022)
- **Citation**: arXiv:2104.08786.
- **Finding**: The *order* of few-shot examples can shift accuracy by tens of percentage points on some tasks.
- **Production implication**: Treat example order as a hyperparameter. If you have an eval set, search over orderings.

## Chain-of-thought and reasoning

### Wei et al., *Chain-of-Thought Prompting Elicits Reasoning* (NeurIPS 2022)
- **Citation**: arXiv:2201.11903.
- **Finding**: Adding "let's think step by step" or showing multi-step reasoning examples dramatically improves performance on arithmetic, commonsense, and symbolic reasoning. The effect emerges at scale (~100B+ params).
- **Production implication**: CoT is a high-ROI lever for non-reasoning models on hard tasks. Reported gains include ~+19pp on MMLU-Pro for standard models.

### OpenAI / Anthropic doc claim: *don't add explicit CoT to reasoning models*
- **Source**: OpenAI prompt engineering docs; Anthropic adaptive thinking docs.
- **Finding**: Reasoning models (Claude extended/adaptive thinking, GPT-5/o-series, Gemini Thinking) do CoT internally; explicit "think step by step" can hurt performance.
- **Production implication**: Use the effort/thinking knob, not prompt-level CoT scaffolding, on reasoning models.

### Wang et al., *Self-Consistency Improves Chain-of-Thought* (ICLR 2023)
- **Citation**: arXiv:2203.11171.
- **Finding**: Sampling N (e.g. 5-40) reasoning chains and majority-voting on the answer beats single-chain CoT on many reasoning benchmarks.
- **Production implication**: When accuracy matters more than latency/cost, self-consistency is the simplest reliable improvement. Skip when latency-sensitive.

### Yao et al., *Tree of Thoughts* (NeurIPS 2023)
- **Citation**: arXiv:2305.10601.
- **Finding**: Treats reasoning as tree search with backtracking; beats CoT on Game of 24, creative writing, mini-crosswords.
- **Production implication**: ToT is expensive (many model calls) and works best on combinatorial/search-shaped problems. For most production tasks, the cost is not justified.

## Agents

### Yao et al., *ReAct: Synergizing Reasoning and Acting* (ICLR 2023)
- **Citation**: arXiv:2210.03629.
- **Finding**: Interleaving reasoning traces and tool actions outperforms either alone on knowledge-intensive QA and decision-making tasks.
- **Production implication**: ReAct is the foundation of most modern agent loops. Modern reasoning models (Claude 4.x, GPT-5, Gemini 3) do this natively in adaptive thinking; you don't need to scaffold ReAct explicitly with them.

### Anthropic, *Building effective agents* (research blog, 2024)
- **Source**: anthropic.com/research/building-effective-agents.
- **Finding (qualitative, production)**: Workflows (deterministic LLM call sequences) outperform agents (autonomous tool loops) for most production tasks. Agents win when the decision space is open-ended and the step count can't be predicted.
- **Production implication**: If you can flowchart it, build a workflow. Save agents for problems you can't.

### Anthropic, *Multi-agent research system* (engineering blog, 2024)
- **Finding (qualitative)**: Sub-agent architectures showed *substantial improvement* over single-agent baselines on complex research tasks. Lead agent coordinates; sub-agents handle isolated focused subtasks with clean context windows; each returns 1-2k token distilled summaries.
- **Production implication**: For research/synthesis tasks with parallelizable substructure, multi-agent beats single-agent. For sequential tasks with shared state, single-agent is simpler.

## Context engineering / context rot

### Chroma research, *Context Rot* (2024-2025)
- **Source**: research.trychroma.com/context-rot.
- **Finding**: Across all tested models, recall accuracy degrades as context size grows — the curve is gradual on better models but always present.
- **Production implication**: Even on long-context models, every added token has a cost. Curate.

### Karpathy, *Context engineering* (X thread, June 2025)
- **Source**: x.com/karpathy/status/1937902205765607626.
- **Framing**: LLM = CPU; context window = RAM; prompt-engineer's job = OS, loading the right working memory each step.
- **Production implication**: Reframes the discipline: it's not about clever wording, it's about state management.

### Anthropic, *Effective context engineering for AI agents* (Sep 2025)
- **Source**: anthropic.com/engineering/effective-context-engineering-for-ai-agents.
- **Framing**: *"Find the smallest possible set of high-signal tokens that maximize the likelihood of the desired outcome."*
- **Production implication**: This sentence captures the entire discipline. Pin it.

## Role prompting

### Practitioner consensus + measurements
- **Sources**: Anthropic prompting docs (notes role prompting "boosts performance on domain-specific tasks"); Wiegold practitioner review citing measurements.
- **Finding (mixed)**: Role prompting helps on open-ended creative work and complex domain tasks where tone/expertise framing matters. Measured to have negligible effect on classification and factual QA.
- **Production implication**: Use role prompts where they help. Don't cargo-cult them into every prompt.

## Negation / Pink Elephant Problem

- **Sources**: practitioner-documented across vendors; Gemini 3 docs explicitly warn that broad negatives like "do not infer" backfire.
- **Finding**: Negative instructions force the model to first represent the forbidden concept, and broad negatives can over-correct beyond the intended scope.
- **Production implication**: Reframe negatives as scoped positives. "Do not invent citations" → "Cite only sources retrieved in this workflow."

## How to read this evidence

Three things to internalize:

1. **Empirical results have version dependencies.** A 2023 finding on GPT-3.5 may not hold on Claude 4.7. Always check whether the evidence is recent enough and on a model close enough to yours.

2. **Production decisions need eval sets.** No paper substitutes for a 5-50 example eval set on *your* task. Use the literature to generate hypotheses; use evals to choose between them.

3. **Vendor docs > blog posts > Twitter threads.** When sources conflict, Anthropic/OpenAI/Google's official docs win because they're tested against the actual model and updated when behavior changes. Practitioner blogs are useful for synthesis and field reports; treat them as well-informed opinion.
