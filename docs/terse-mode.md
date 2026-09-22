# Terse mode

Caps how many words Claude answers with.

A Stop hook measures every reply: if it exceeds the word budget (code fences
excluded) and the user did not ask why, how or for an explanation, the reply
is blocked and resent as the answer only. On by default at 40 words;
`/1337:terse hard` tightens it to one line, `/1337:terse off` disables it.
Levels persist in `~/.claude/.1337-terse`; `CLAUDE_1337_TERSE=0|on|hard`
overrides per session. Pair it with the `1337:silent` output style
(`/output-style`) for a no-persona, answers-only voice.

[Back to README](../README.md)
