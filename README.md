<p align="center">
  <img src="assets/logo-1337-claude.png" alt="1337 Claude" width="420">
</p>

> My personal experimentation repo for Claude Code. This is where I test new
> workflows and prompts, hooks, output styles, token optimization and anything
> else an agent might do differently.

A Claude Code plugin that adds eight output-style voices, read-only skills
that keep code lean, and two opt-in modes that route work to cheaper models.

## Why it exists

Claude Code sessions tend to over-build, drift from a plan, and burn an
expensive model on lookups a cheap one could handle. This plugin adds the
guardrails and the routing to fix that, without changing how you prompt.

## What's special

- **Eight voices, one engineer.** The persona changes how Claude talks, never
  the code it writes. See [the voices](docs/output-styles.md).
- **Read-only skills that cut, not add.** `/1337:review`, `/1337:audit`,
  `/1337:debt` and friends look for what to delete before anything gets
  built. See [skills](docs/skills.md).
- **Visual work without leaving the chat.** Ask for a logo, an SVG, a clip or
  a voice-over and it picks a priced OpenRouter model for you, ranked by
  [Jev](https://typesafe.ai), TypeSafe's decision model. See
  [visual generation](docs/visual-generation.md).
- **Terse by default.** Replies over budget get blocked and resent shorter.
  See [terse mode](docs/terse-mode.md).
- **Orchestrator mode.** The main session only plans; scouts, builders and
  checkers do the reading, coding and testing on cheaper models. See
  [orchestrator mode](docs/orchestrator-mode.md).
- **Tiered mode.** Jev picks Haiku, Sonnet or Opus per step, enforced by a
  hook, not just asked for. See [tiered mode](docs/tiered-mode.md).

## Install

```bash
claude plugin marketplace add dimitritholen/1337-claude
claude plugin install 1337@1337-claude
```

Or load it straight from a checkout:

```bash
claude --plugin-dir ~/projects/1337-claude
```

## Visual work through OpenRouter

```mermaid
%%{init: {"theme":"base", "themeVariables": {"primaryColor":"#1a1a2e", "primaryBorderColor":"#FF1493", "primaryTextColor":"#00D9FF", "fontSize":"13px"}}}%%
flowchart TD
    A["You type: make a retro logo<br/>for my coffee shop"] --> B{"Does it mention a logo,<br/>image, video or voice?"}
    B -->|No| C["Claude answers as usual"]
    B -->|"Yes, a logo"| D{"OpenRouter key<br/>saved?"}
    D -->|No| E["Claude offers to set one up"]
    D -->|Yes| F["Jev works out the kind of file:<br/>a vector logo, SVG"]
    F -->|"Not a visual after all"| C
    F --> H["Look up the 6 cheapest<br/>SVG models and their prices"]
    H --> I["Jev picks the best fit,<br/>say Model X at $0.04"]
    I --> J["Claude asks you to choose,<br/>Jev's pick on top"]
    J -->|"You pick Model X"| M["generate.py makes the file"]
    J -->|"Stay with Claude"| L["Claude draws it itself"]
    M --> N["Saved as assets/make-a-retro-logo-<br/>for-my-coffee-shop.svg, cost $0.04"]

    linkStyle default stroke:#FF1493,stroke-width:2px

    classDef io fill:#1a1a2e,stroke:#00D9FF,stroke-width:2px,color:#00D9FF
    classDef decision fill:#1a1a2e,stroke:#FF6600,stroke-width:2px,color:#FFD700
    classDef jev fill:#1a1a2e,stroke:#FF1493,stroke-width:2px,color:#FFB6D9
    classDef generate fill:#1a1a2e,stroke:#FF8800,stroke-width:2px,color:#FFD700
    classDef terminal fill:#1a1a2e,stroke:#00D9FF,stroke-width:2px,color:#00D9FF

    class A,N io
    class B,D decision
    class F,H,I,J jev
    class M,L generate
    class E,C terminal
```

Ask for a logo, SVG, video or voice-over and a hook intercepts before Claude starts drawing ASCII. It calls [Jev](https://typesafe.ai) to detect the modality, pulls OpenRouter's six cheapest models of that kind, asks you to pick one with prices visible, and runs `generate.py` to write the file (never overwrites). Stay with Claude is always an option.

Details: [Visual generation](docs/visual-generation.md).

## More

- [The voices](docs/output-styles.md)
- [Skills](docs/skills.md)
- [Visual generation](docs/visual-generation.md)
- [Terse mode](docs/terse-mode.md)
- [Orchestrator mode](docs/orchestrator-mode.md)
- [Tiered mode](docs/tiered-mode.md)
- [Testing](docs/testing.md)
