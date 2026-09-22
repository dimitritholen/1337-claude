# Visual generation

Turns a prompt for an image, SVG, video or voice-over into an actual file,
picked and priced through OpenRouter.

Ask for a logo, an SVG illustration, a short clip or a voice-over and a
UserPromptSubmit hook steps in before Claude starts drawing ASCII. It asks
[Jev](https://typesafe.ai), TypeSafe's decision model, what the prompt wants (text or
code, raster image, vector SVG, video, speech), pulls OpenRouter's live model
list for that kind, and has Jev rank the six cheapest. It then injects one
instruction: ask with `AskUserQuestion` first. Jev's pick comes first, marked
Recommended, then cheap to expensive, a price in every label, and "Stay with
Claude" last. On a choice, `skills/visual/generate.py` makes the file (Recraft
vector models return a real SVG), writes it to the path named in the prompt or
to `assets/<slug>.<ext>` without ever overwriting, and prints the path and the
real cost.

## Setup

One key serves everything, stored once:

```bash
python3 skills/visual/setup-key.py    # or /1337:visual setup in a session
```

OAuth PKCE in the browser, a paste page for when the callback cannot reach the
machine, `--tty` for a hidden prompt. The key lands in
`~/.config/1337/credentials` (mode 0600); an `OPENROUTER_API_KEY` in the
environment wins over it. The hook costs one Jev decision per candidate
prompt (about a hundredth of a cent) and stays silent on a coding prompt, on
low confidence, on any failure, and with `CLAUDE_1337_VISUAL=0`.

## Rules for subagents

A SubagentStart hook injects a compact digest (minimum-work ladder,
assumptions discipline, tight replies) into every spawned subagent.
`CLAUDE_1337_SUBAGENT_MATCHER` scopes it by agent type,
`CLAUDE_1337_SUBAGENT_RULES=0` disables it.

## Review nudge

After a session's diff grows past 30 added lines, a Stop hook offers one
`/1337:review` pass before the session ends — once per session, never runs it
unasked. Opt out with `CLAUDE_1337_REVIEW_NUDGE=0`.

[Back to README](../README.md)
