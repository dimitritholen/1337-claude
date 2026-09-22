# Tiered mode

Lets [Jev](https://typesafe.ai) pick the model tier for each builder step, instead
of you sizing it by hand.

Off by default. When on, the main session does not size builder steps itself:
before each `1337:builder` dispatch it runs `skills/tier/route.py` with the
step titles and briefs, and Jev, TypeSafe's decision model, returns the tier
(Haiku, Sonnet or Opus) with a confidence; a step under the confidence floor
moves one tier up. The dispatch line names the tier and the confidence. Needs
the same stored OpenRouter or TypeSafe key as `/1337:tier`; without one the
session says so once and sizes by hand. Works with or without orchestrator
mode, since it governs any builder dispatch; the two pair naturally.

Enforced, not just asked for: a hook refuses a `1337:builder` dispatch that
never routed this session, that would spend more dispatches than the router
routed steps, or whose model is not one of the tiers still owed — one
routing call licenses exactly as many builder dispatches as it routed steps.
`CLAUDE_1337_ROUTE_GUARD=off` turns the check off.

## Turn it on

Same four ways as [orchestrator mode](orchestrator-mode.md), with `tiered` in
place of `orchestrator`: `--config tiered=true` at install, the option prompt
when enabling, the `tiered` row in `/config` or `"tiered": true` next to
`"orchestrator"` in `~/.claude/settings.json`, or `CLAUDE_1337_TIERED=1` for
one session. Start a new session after changing it.

[Back to README](../README.md)
