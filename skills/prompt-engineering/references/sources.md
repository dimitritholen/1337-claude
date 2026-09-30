# Sources

Every recommendation in this skill traces to one of these. Accessed May 1, 2026.

## Vendor primary sources

### Anthropic
- **Claude prompting best practices** (canonical reference, Opus 4.7 / 4.6, Sonnet 4.6, Haiku 4.5)
  https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- **Effective context engineering for AI agents** (Sep 29, 2025)
  https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- **Building effective agents**
  https://www.anthropic.com/research/building-effective-agents
- **How we built our multi-agent research system**
  https://www.anthropic.com/engineering/multi-agent-research-system
- **Writing tools for AI agents — with AI agents**
  https://www.anthropic.com/engineering/writing-tools-for-agents
- **Best Practices for Claude Code**
  https://www.anthropic.com/engineering/claude-code-best-practices
- **Best practices for prompt engineering** (claude.com blog, Feb 2026)
  https://claude.com/blog/best-practices-for-prompt-engineering
- **Anthropic interactive prompt engineering tutorial**
  https://github.com/anthropics/prompt-eng-interactive-tutorial
- **Prompt caching docs**
  https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- **Adaptive thinking docs**
  https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking
- **Effort parameter**
  https://platform.claude.com/docs/en/build-with-claude/effort

### OpenAI
- **Prompt guidance for GPT-5.4** (current mainline model docs)
  https://developers.openai.com/api/docs/guides/prompt-guidance
- **Using GPT-5.5** (latest, April 2026)
  https://developers.openai.com/api/docs/guides/latest-model
- **GPT-5.5 prompting guide** (cookbook, April 2026)
  https://developers.openai.com/cookbook/examples/gpt-5/gpt-5-5_prompting_guide
- **GPT-5.2 prompting guide**
  https://cookbook.openai.com/examples/gpt-5/gpt-5-2_prompting_guide
- **GPT-5.1 prompting guide**
  https://cookbook.openai.com/examples/gpt-5/gpt-5-1_prompting_guide
- **GPT-5 prompting guide** (original)
  https://cookbook.openai.com/examples/gpt-5/gpt-5_prompting_guide
- **Codex prompting guide**
  https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide
- **Reasoning best practices**
  https://developers.openai.com/api/docs/guides/reasoning-best-practices
- **Structured outputs**
  https://developers.openai.com/api/docs/guides/structured-outputs

### Google
- **Gemini API: Prompt design strategies** (April 2026)
  https://ai.google.dev/gemini-api/docs/prompting-strategies
- **Gemini 3 prompting guide on Vertex AI / Gemini Enterprise Agent Platform** (April 2026)
  https://docs.cloud.google.com/vertex-ai/generative-ai/docs/start/gemini-3-prompting-guide
- **Gemini 3 Developer Guide**
  https://ai.google.dev/gemini-api/docs/gemini-3
- **Lee Boonstra, Prompt Engineering whitepaper (Sept 2024)**
  https://www.kaggle.com/whitepaper-prompt-engineering
  Author profile: https://www.leeboonstra.dev/

## Academic sources (with arXiv IDs)

### Surveys / taxonomies
- **Schulhoff et al., *The Prompt Report: A Systematic Survey of Prompt Engineering Techniques*** (v6, Feb 2025)
  arXiv:2406.06608 — https://arxiv.org/abs/2406.06608
- **Sahoo et al., *A Systematic Survey of Prompt Engineering in Large Language Models: Techniques and Applications*** (v2, March 2025)
  arXiv:2402.07927 — https://arxiv.org/abs/2402.07927
- **Vatsal & Dubey, *A Survey of Prompt Engineering Methods in Large Language Models for Different NLP Tasks*** (July 2024)
  arXiv:2407.12994 — https://arxiv.org/abs/2407.12994

### Long context / positional bias
- **Liu et al., *Lost in the Middle: How Language Models Use Long Contexts*** (TACL, 2024) — 2,500+ citations
  doi:10.1162/tacl_a_00638
- **Hsieh et al., *Found in the Middle: Calibrating Positional Attention Bias Improves Long Context Utilization*** (2024)
  arXiv:2406.16008 / earlier arXiv:2403.04797
- **McKinnon (Google), *Retrieval Quality at Context Limit*** (2025)
  arXiv:2511.05850
- **Levy, Jacoby & Goldberg, *Same Task, More Tokens: the Impact of Input Length on the Reasoning Performance of Large Language Models*** (2024)
  arXiv:2402.14848
- **Hengle et al., *Positional Biases Shift as Inputs Approach Context Window Limits*** (2025)
  arXiv:2508.07479

### Few-shot / demonstrations
- **Min et al., *Rethinking the Role of Demonstrations: What Makes In-Context Learning Work?*** (EMNLP 2022)
  arXiv:2202.12837
- **Lu et al., *Fantastically Ordered Prompts and Where to Find Them*** (ACL 2022)
  arXiv:2104.08786

### Chain-of-thought and self-consistency
- **Wei et al., *Chain-of-Thought Prompting Elicits Reasoning in Large Language Models*** (NeurIPS 2022)
  arXiv:2201.11903
- **Wang et al., *Self-Consistency Improves Chain of Thought Reasoning in Language Models*** (ICLR 2023)
  arXiv:2203.11171
- **Kojima et al., *Large Language Models are Zero-Shot Reasoners*** (NeurIPS 2022) — origin of "let's think step by step"
  arXiv:2205.11916

### Tree-of-thoughts / search-based reasoning
- **Yao et al., *Tree of Thoughts: Deliberate Problem Solving with Large Language Models*** (NeurIPS 2023)
  arXiv:2305.10601

### Agents
- **Yao et al., *ReAct: Synergizing Reasoning and Acting in Language Models*** (ICLR 2023)
  arXiv:2210.03629

### Transformer / attention foundations (referenced indirectly)
- **Vaswani et al., *Attention Is All You Need*** (NeurIPS 2017) — context rot is downstream of O(n²) attention
  arXiv:1706.03762

## Practitioner sources with verifiable production track records

- **Andrej Karpathy** (X / Twitter, June 2025) — context engineering CPU/RAM/OS framing
  https://x.com/karpathy/status/1937902205765607626
- **Phil Schmid** (Hugging Face / Google DeepMind) — context engineering essays
  philschmid.de
- **LangChain**, *Context engineering for agents* (write/select/compress/isolate)
  https://blog.langchain.com/context-engineering-for-agents/
- **Simon Willison** — daily-updated AI newsletter; tracks prompt engineering closely
  https://simonwillison.net/
- **Thomas Wiegold**, *Prompt Engineering Best Practices 2026* (Feb 2026, AI consultant Sydney)
  https://thomas-wiegold.com/blog/prompt-engineering-best-practices-2026/

## Tooling references

- **Promptfoo** — open-source CI/CD prompt evaluation, ~51k+ developers
  https://www.promptfoo.dev/
- **DSPy** — algorithmic prompt optimization framework (Stanford)
  https://dspy.ai/
- **Chroma research, Context Rot**
  https://research.trychroma.com/context-rot

## Versioning and access

This list reflects sources current as of May 1, 2026. Re-check vendor docs (Anthropic / OpenAI / Google) on every model release — they update materially with each version. The academic side moves slower; surveys are typically valid for 12-18 months.
