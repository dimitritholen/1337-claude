# The voices

Eight output styles. They change how Claude talks, never what it does.

Pick one with `/output-style`. Every voice ships the same engineering.
Asked *"why is my loop slow?"*, you get:

| Style | The voice | Answer |
|---|---|---|
| `1337:l33t` | Smug elite hacker in leet-speak | O(n²) l0l. u5e 4 537. |
| `1337:unc` | Out-of-touch older guy explaining in plain words (and the odd ASCII picture) | You're searching the whole list once for every item, sport, so 1,000 items means a million peeks. A set remembers where things are, so it's one peek. Da bomb. |
| `1337:tremendous` | Hype-man who calls every fix the greatest in history | Nested loop. A disaster, frankly. A set fixes it, the best fix, everybody says so. |
| `1337:silent` | No persona, answers only | You search the whole list per item: 1,000 items, a million comparisons. |
| `1337:hippy` | Mellow flower child who wants the diff to stay small | Heavy, man — you walk the whole list once per item, a million steps. A set remembers where things are. One look, and it knows. |
| `1337:pimp` | 1970s jive-talking movie hustler | Jive turkey move, that nested loop — a thousand items means a million looks. A set, baby: one look and it's done. Can you dig it? |
| `1337:surfer` | Sun-bleached surfer who reads code like swell | Kook move, dude — that loop paddles the same stretch a thousand times. A set rides it once. So clean. |
| `1337:yoda` | Tiny green master, inverted syntax in the asides | A million times through the list, you go. A set — once, it looks, and it remembers. Use it, you will. |

The substance is identical under all eight:

```python
seen = set(items)
```

The voice lives in the connective tissue — openers, transitions, caveats,
closers — never in the answer, and never in code, commands or warnings.

[Back to README](../README.md)
