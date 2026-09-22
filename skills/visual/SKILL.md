---
name: visual
description: Make image, SVG, video or speech files through an OpenRouter model picked from a Jev-ranked, priced list, and store the OpenRouter key once. Use on /1337:visual, "/1337:visual setup", when the user asks to generate, draw, render or narrate something as a file, when a prompt carries a "[1337 visual]" context block from the hook, or when a Jev-backed script reports a missing key.
---

You turn a request for a picture, a vector drawing, a video clip or spoken
audio into a file on disk, made by the cheapest OpenRouter model that fits,
chosen by the user from a short priced list. You never spend credit without
that choice.

# The flow

1. **The hook asks.** A UserPromptSubmit hook (`skills/visual/route.py`)
   watches every prompt. When the prompt hits a word prefilter (image, logo,
   svg, video, voice, ...) and an OpenRouter key is stored, it asks Jev,
   TypeSafe's decision model, what the prompt wants (text or code, raster
   image, vector SVG, video, speech) and, for a visual answer, ranks the six
   cheapest models of that kind. It injects a `[1337 visual]` block.
2. **The user picks.** On that block, before anything else, ask with
   `AskUserQuestion` exactly as the block says: header "Model", Jev's pick
   first and marked Recommended, then cheap to expensive, a price in every
   label, "Stay with Claude" last. One question, never twice for one prompt.
3. **You generate.** On a model choice run the command the block gives:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/visual/generate.py" \
     --model <chosen id> --modality raster_image|vector_svg|video|speech \
     --prompt "<the user's prompt, verbatim>" [--out <path>] \
     [--endpoint auto|chat|images] [--aspect 16:9] [--duration 8] [--voice alloy]
   ```

   It prints one JSON line with `path`, `media_type`, `bytes` and `cost`.
   Report the path and the cost in one line. On "Stay with Claude" carry on
   as usual and do not mention the models again. `--endpoint auto` (default)
   posts to chat/completions and retries against /api/v1/images on a 404.

Without the hook block (a direct `/1337:visual <request>`), do the same by
hand: run `skills/visual/catalogue.py <modality> 6` for the list, ask the
question, then generate.

# Where the file goes

`--out` wins. Else `assets/<slug of the prompt>.<ext>` under the current
directory. Nothing is ever overwritten: a second file gets `-2`. The
extension follows what the model returned: Recraft vector models return a
real SVG, raster models PNG or JPEG, video MP4, speech MP3.

# Setup, once

`/1337:visual setup` runs:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/visual/setup-key.py"
```

It opens the browser on OpenRouter's OAuth page, takes the callback on
127.0.0.1, checks the key and stores it in `~/.config/1337/credentials`
(mode 0600). If the browser cannot reach this machine (a Windows browser
outside WSL, a remote box), the same run serves a paste page whose URL is
on its stderr; `--tty` reads a hidden prompt instead. Nothing prints the
key. After that no session asks again: the tier router, the visual hook and
the generator all read the same file, and `OPENROUTER_API_KEY` in the
environment wins over it.

When a prompt looks visual and no key is stored, the hook injects a short
note instead of a list. Ask once with `AskUserQuestion` whether to store a
key now or carry on without; on "without", do not ask again this session.

# Errors

Exit 6 from generate.py (model unusable: HTTP 403 upstream, e.g. an 18+
attestation the account lacks) prints the upstream message to the user in one
line, drops that model from the ranked choice, and asks once more with the
remaining models; if none remain, say so and stop. This is the one exception
to "do not ask twice for the same prompt", because the first answer turned
out impossible, not declined.

# Prices

Labels show what OpenRouter bills: image models per 1K image output tokens
(a picture is roughly 1K to 4K tokens, so multiply by two to four for a
per-picture guess), video per second, speech per 1K characters. The
generator reports the real cost after the fact. Models that need a
reference image on every request (Recraft "Styles") are never offered.

# Knobs

- `CLAUDE_1337_VISUAL=0` — the hook stays silent.
- `CLAUDE_1337_VISUAL_FLOOR` — Jev confidence under which the hook stays
  silent or drops the recommendation (0.5).
- `OPENROUTER_BASE_URL`, `CLAUDE_1337_CREDENTIALS` — API and key file
  overrides, for tests.
- `CLAUDE_1337_POLL_SECONDS` — video job poll interval (5).

Rules: never call generate.py before the user chose; never print or echo a
key; a hook or API failure means silence and the normal reply, not an
apology.
