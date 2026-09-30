# Agentic systems and context engineering

This is the part where prompt engineering becomes systems engineering. The references here are the most important ones; nothing in this file is theoretical.

## Primary sources

- Anthropic Engineering, [*Effective context engineering for AI agents*](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) (Sep 29, 2025) — the canonical write-up of Anthropic's current view.
- Anthropic, [*Building effective agents*](https://www.anthropic.com/research/building-effective-agents) — definition of agents as "LLMs autonomously using tools in a loop" plus workflow patterns.
- Anthropic, [*How we built our multi-agent research system*](https://www.anthropic.com/engineering/multi-agent-research-system) — production case study for sub-agent architectures.
- Anthropic, [*Writing tools for AI agents*](https://www.anthropic.com/engineering/writing-tools-for-agents) — tool design as part of context.
- LangChain, *Context engineering for agents* — the **write / select / compress / isolate** taxonomy that's now industry standard.
- Andrej Karpathy, X thread (June 2025) — CPU/RAM/OS framing for context engineering.
- Chroma research, *Context Rot* — the empirical degradation pattern as context grows.

## Why context engineering exists

Two empirical realities make this a real engineering problem rather than a "just use a bigger window" problem:

1. **Attention is finite and has a budget.** Transformer attention is O(n²); every added token depletes the model's effective focus. Performance does *not* scale linearly with context length. Anthropic explicitly calls out: *"as the number of tokens in the context window increases, the model's ability to accurately recall information from that context decreases"* — this is **context rot**, and it shows up in every model tested.

2. **Models are trained on shorter sequences.** Position encoding interpolation gets you longer windows but with degraded position understanding. The result is a *performance gradient*, not a hard cliff: the model is still capable at long context, but recall and long-range reasoning are measurably worse than at short context.

Combined with Liu et al.'s lost-in-the-middle finding, the operational principle is: **context is finite, expensive, and best treated like RAM in an OS — actively curated, not passively dumped.**

## The "right altitude" for system prompts

Anthropic's framing of the most common system prompt failure modes (both extremes are bad):

- **Too brittle**: hardcoded if-else logic in prose, trying to specify exact behavior for every case. Creates fragility, maintenance hell, and blocks the model from generalizing usefully.
- **Too vague**: "you are a helpful assistant" + falsely assuming shared context. Leaves the model without enough signal about expected outputs.

The Goldilocks zone: *"specific enough to guide behavior effectively, yet flexible enough to provide the model with strong heuristics."*

Anthropic's recommended structure:

```xml
<background_information>
  Why this exists, who the user is, what they're trying to accomplish.
</background_information>

<instructions>
  How to behave. Heuristics, not flowcharts.
</instructions>

## Tool guidance
  When to use which tool. Decision rules.

## Output description
  What "done" looks like. Format. Verification.
```

The prompt should be **minimal but complete**. Minimal does not mean short. It means every sentence is pulling weight.

## Tool design as context design

Tools are part of the context. Tool descriptions, schemas, and naming all consume tokens and shape behavior. Anthropic's rules from *Writing tools for AI agents*:

- **Self-contained**: each tool does one thing; doesn't depend on side knowledge outside its description.
- **Robust to error**: returns useful errors that help the agent recover.
- **Minimal functional overlap**: if two tools could plausibly be used for the same task, the agent will fumble routing.
- **Descriptive parameters**: names like `target_user_id` not `id`; types and constraints explicit.
- **Token-efficient outputs**: paginate, compress, summarize verbose tool results. Don't return 50KB of JSON when the agent needs three fields.

The litmus test: *"If a human engineer can't definitively say which tool should be used in a given situation, an AI agent can't be expected to do better."*

Common failure mode: bloated tool sets with 20+ overlapping tools. Curate down. Anthropic's Claude Code uses a small set of high-leverage primitives (Read / Write / Bash / Glob / Grep / Edit) rather than dozens of specialized tools, and offloads specialization to skills.

## Just-in-time vs. up-front context loading

Two strategies, both legitimate:

**Up-front retrieval** (RAG, embedding-based pre-inference):
- Pre-fetch likely-relevant documents and stuff them into context at start.
- Faster (no extra round trips).
- Works well for stable, well-indexed corpora (legal, finance docs, product manuals).

**Just-in-time retrieval** (Claude Code style):
- Maintain lightweight identifiers (file paths, IDs, query strings).
- Let the agent dereference what it actually needs via tools.
- Mirrors human cognition (we don't memorize whole books; we look things up).
- Better for dynamic environments (live filesystems, evolving databases).
- Slower per-step but uses far less context, which compounds in long-horizon tasks.

**Hybrid is usually best.** Anthropic's Claude Code: load CLAUDE.md / AGENTS.md upfront for stable project context; use grep/glob/file_read for dynamic discovery. The boundary depends on volatility — pre-load stable context, retrieve dynamic context.

A useful intuition: **filenames, folder paths, and timestamps are themselves signal.** A file at `tests/test_utils.py` versus `src/core_logic/test_utils.py` carries different meaning to the agent without ever being read. Naming is part of the context.

## Long-horizon survival kit

When tasks span many hours or many context windows (large refactors, deep research, multi-day projects), three patterns from Anthropic:

### Compaction

Take a conversation nearing the context limit, summarize, restart with the summary. The art:

- **Maximize recall first.** Tune the compaction prompt against complex traces; ensure no critical info is lost.
- **Then improve precision.** Trim superfluous content (redundant tool outputs, completed action confirmations).
- **Tool-result clearing** is the safest light-touch compaction — once a tool was called and the result used, the raw payload can usually be dropped. Now a first-class platform feature.

In Claude Code specifically: Anthropic preserves architectural decisions, unresolved bugs, implementation details, and the five most recently accessed files; discards redundant tool outputs and completed-and-confirmed actions.

When to use compaction: tasks needing conversational flow / back-and-forth / many small adjustments.

### Structured note-taking (agentic memory)

The agent maintains a NOTES.md / memory file outside the context window. Reads it back when needed.

- Simplest implementation: instruct the agent to maintain a TODO list in a file; check it at the start of each context window.
- Anthropic's memory tool (public beta as of Sonnet 4.5 launch) formalizes this with a file-based system.
- Famously demonstrated by Claude Plays Pokémon: the agent maintains training tallies, route maps, combat strategy notes — coherent over thousands of game steps.

When to use notes: iterative work with milestones (coding projects, research with discrete sub-questions, multi-step builds with intermediate state).

### Sub-agent architectures

Lead agent coordinates with a high-level plan; sub-agents handle isolated focused tasks with clean context windows. Each sub-agent might use 10k+ tokens internally, but returns a 1–2k-token distilled summary.

Reported substantial improvement over single-agent baselines on complex research tasks (Anthropic's multi-agent research system).

When to use sub-agents: complex research with parallel exploration, fan-out across many items, tasks where isolating context prevents pollution between sub-tasks.

### LangChain's four context strategies (the unifying framing)

| Strategy | What it does | Example |
|---|---|---|
| **Write** | Persist context externally | NOTES.md, memory tool, scratchpads |
| **Select** | Retrieve what's relevant via RAG | Embedding search, BM25, file-based grep |
| **Compress** | Summarize and compact | Compaction, tool-result clearing |
| **Isolate** | Separate contexts for different agents | Sub-agents, multi-agent architectures |

Most production agent systems use all four. Knowing which to reach for in which failure mode is the actual skill.

## Multi-window agent workflows (Anthropic's playbook)

For tasks that span multiple context windows from the start (large code migrations, research projects):

1. **Different first window**: use the first context window to set up a framework — write tests, create setup scripts, lay out the structure. Future windows iterate on a TODO list.
2. **Tests in structured format**: `tests.json` or similar. Tell the model: *"It is unacceptable to remove or edit tests because this could lead to missing or buggy functionality."*
3. **Quality-of-life scripts**: `init.sh` to bring up servers, run tests, check linters. Saves repeated work each context window.
4. **Fresh start vs compaction**: when a window is cleared, sometimes starting *fresh* is better than compacting. Modern Claude is good at recovering state from filesystem. Tell it explicitly: *"call pwd; review progress.txt, tests.json, and the git logs; manually run through a fundamental integration test."*
5. **Verification tools**: as autonomous duration grows, the agent needs to verify correctness without you. Playwright MCP for UIs, computer use for visual checks, test suites for code.
6. **Tell the agent its budget**: if your harness compacts automatically, tell the model so it doesn't artificially wrap up early. Anthropic's recommended phrasing:
   ```
   Your context window will be automatically compacted as it approaches its limit, allowing you to continue working indefinitely. Do not stop tasks early due to token budget concerns. As you approach your token budget limit, save your current progress and state to memory before the context window refreshes. Always be persistent and complete tasks fully.
   ```

## Action safety and reversibility

For agents that take real actions, separate reversible from irreversible:

- **Reversible / local**: edit a file, run tests, create a branch — proceed, summarize after.
- **Irreversible / shared**: delete files, force-push, send messages, modify production, drop database tables — confirm first.

Anthropic's recommended block (paraphrased):
```
Consider the reversibility and impact of your actions. Take local reversible actions freely. For destructive or shared-system actions, ask before proceeding. Don't bypass safety checks (--no-verify, --force) as a shortcut.
```

## Tool result lifecycle (specific gotcha)

Once a tool result has been consumed and acted on, the raw payload is usually dead weight in the context. Strategies:

- **Drop entirely** if the result was confirmed-and-acted-on.
- **Replace with summary** if the result might be referenced later.
- **Keep raw** only if accuracy of detailed values matters (e.g., financial data, exact strings).

Anthropic now ships tool-result clearing as a platform feature; in homegrown harnesses you implement it yourself in the message-history layer.

## Common agent failure modes (and what to fix first)

| Symptom | Suspect first | Then |
|---|---|---|
| "Model got dumber recently" | Context rot from message history bloat | Compaction / clear tool results |
| Wrong tool selected | Tool description ambiguity / overlap | Curate tool set, sharpen descriptions |
| Loops over the same dead-end | Missing fallback strategy | Add `<empty_result_recovery>` |
| Stops too early | Model treating partial as done | `<completeness_contract>`, raise effort |
| Stops too early on long tasks | Token budget anxiety | Tell the model the budget will compact |
| Ignores recent instruction | Buried in middle of context | Move to top or bottom; lost-in-the-middle |
| Overengineers solutions | Default 4.x tendency | Anti-overengineering block (Anthropic ships one) |
| Spawns subagents unnecessarily | Default 4.5/4.6 tendency | Explicit subagent guidance |
| Generic AI-slop frontends | Claude 4.7 default style | Specify concrete alternative or ask for 4 directions |

## When **not** to use agents

Anthropic's *Building Effective Agents* makes this explicit: workflows (deterministic LLM calls in a known sequence) beat agents (LLM autonomously deciding tool calls in a loop) for most production tasks. Agents win when:

- The decision space is genuinely open-ended.
- The number of steps can't be predicted in advance.
- Recovery from errors is the norm, not the exception.

If you can write the flowchart, write the workflow. Agents are for problems where you can't.
