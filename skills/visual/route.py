#!/usr/bin/env python3
"""UserPromptSubmit hook: route a visual request to an OpenRouter model.

Reads the hook payload on stdin and stays silent (exit 0, no output)
unless the prompt matches the word prefilter and an OpenRouter key is
stored. Then one Jev Choice says what the prompt asks for (text_or_code,
raster_image, vector_svg, video, speech); confidence under the floor or
text_or_code means silence. For a visual modality the six cheapest
catalogue entries go into one more Choice: Jev's pick is the
recommendation, the probabilities are the ranking. The output is hook
JSON with additionalContext telling Claude to ask with AskUserQuestion
before anything else (Jev's pick first and marked Recommended, then
cheap to expensive, a price in every label, plus a stay-with-Claude
option) and then run generate.py with the chosen id.

Budget: the hook runs under a 10-second timeout, so every network call
gets what is left of an internal 9-second deadline, at most 2.5 seconds
each. Any failure exits 0 silently: a routing miss costs nothing, a
blocked prompt would.

CLAUDE_1337_VISUAL=0 disables the hook. CLAUDE_1337_VISUAL_FLOOR moves
the confidence floor (0.5). Stdlib only, through lib/ and catalogue.py.
"""

import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, HERE)
from lib import jev, keys  # noqa: E402
import catalogue  # noqa: E402

PREFILTER = re.compile(
    r"\b(image|images|picture|pictures|illustration|illustrations|logo|logos|icon|icons|"
    r"svg|vector|render|rendering|banner|banners|poster|posters|video|videos|clip|clips|"
    r"animation|animations|voice|voices|speech|narrate|narration|tts|audio)\b",
    re.IGNORECASE,
)
MODALITIES = {
    "text_or_code": "Prose, code, data, a diagram in text, or anything Claude writes itself; "
                    "also questions about images or videos that need no new file made.",
    "raster_image": "A new picture as pixels: photo, painting, render, banner, poster, "
                    "icon or logo as PNG or JPEG.",
    "vector_svg": "A new drawing as vectors: an SVG, a scalable logo or icon, a vector "
                  "illustration, line art meant to scale.",
    "video": "A new video or animated clip.",
    "speech": "Spoken audio from text: narration, a voice-over, text-to-speech.",
}
DEADLINE = 9.0
CALL_TIMEOUT = 2.5
CANDIDATES = 6
SHOWN = 3


def budget(started):
    return min(CALL_TIMEOUT, DEADLINE - (time.monotonic() - started))


def price_label(entry):
    price, unit = entry["price"], entry["unit"]
    if unit in ("image token", "character", "video token"):
        return f"${price * 1000:.4f} per 1K {unit}s"
    return f"${price:.3f} per {unit}"


def criterion(entry):
    description = re.sub(r"\s+", " ", entry["description"])[:240]
    return f"{entry['name']}: {description} Price {price_label(entry)}."


def context(prompt, modality, ranked, recommended):
    lines = [
        f"[1337 visual] This prompt asks for a {modality.replace('_', ' ')}, which an "
        "OpenRouter model can make for a few cents. Before anything else, ask with "
        "AskUserQuestion (one question, header \"Model\") which model should make it, "
        "options in exactly this order and wording:",
    ]
    for i, entry in enumerate(ranked, 1):
        tag = " (Recommended)" if entry is recommended else ""
        lines.append(
            f"{i}. {entry['id']}{tag} — {entry['name']}, {price_label(entry)}, "
            f"Jev {entry['probability']:.2f}"
        )
    lines.append(f"{len(ranked) + 1}. Stay with Claude — no OpenRouter call, Claude writes or "
                 "describes it by hand.")
    generate = os.path.join(HERE, "generate.py")
    lines.append(
        f"On a model choice run: python3 \"{generate}\" --model <chosen id> --modality "
        f"{modality} --prompt <the user's prompt, verbatim> [--out <path named in the prompt>], "
        "then report the path and cost it prints. On \"Stay with Claude\" carry on as usual. "
        "Do not ask twice for the same prompt."
    )
    return "\n".join(lines)


def emit(text):
    json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                      "additionalContext": text}}, sys.stdout)
    print()


def route(prompt, started):
    floor = float(os.environ.get("CLAUDE_1337_VISUAL_FLOOR", "0.5"))
    answer = jev.decide(
        {"prompt": prompt},
        {"modality": jev.choice(
            "What does the user ask to be produced? Pick text_or_code unless the prompt "
            "clearly asks for a new image, drawing, video or spoken audio file.",
            MODALITIES)},
        timeout=budget(started),
    )["answers"]["modality"]
    modality = answer.get("choice")
    if modality not in MODALITIES or modality == "text_or_code":
        return None
    if float(answer.get("confidence") or 0.0) < floor:
        return None

    entries = [e for e in catalogue.models(modality, timeout=budget(started))
               if e["price"] is not None][:CANDIDATES]
    if not entries:
        return None
    by_id = {e["id"]: e for e in entries}
    answer = jev.decide(
        {"prompt": prompt, "modality": modality},
        {"model": jev.choice(
            "Which model should make what the prompt asks for? Weigh fit to the prompt "
            "against price; the cheapest model that can do it well wins.",
            {e["id"]: criterion(e) for e in entries})},
        timeout=budget(started),
    )["answers"]["model"]
    probabilities = answer.get("probabilities") or {}
    for e in entries:
        e["probability"] = float(probabilities.get(e["id"], 0.0))
    recommended = by_id.get(answer.get("choice"))
    if recommended is None or float(answer.get("confidence") or 0.0) < floor:
        recommended = None
    ranked = ([recommended] if recommended else []) + [e for e in entries if e is not recommended]
    return context(prompt, modality, ranked[:SHOWN], recommended)


def main():
    if os.environ.get("CLAUDE_1337_VISUAL", "1").lower() in ("0", "off", "false"):
        return 0
    started = time.monotonic()
    try:
        payload = json.load(sys.stdin)
        prompt = payload.get("prompt") if isinstance(payload, dict) else None
    except ValueError:
        return 0
    if not isinstance(prompt, str) or not PREFILTER.search(prompt):
        return 0
    try:
        if not keys.find("OPENROUTER_API_KEY"):
            emit("[1337 visual] This prompt may ask for an image, video or speech file, which "
                 "an OpenRouter model could make, but no OpenRouter key is stored. Ask once with "
                 "AskUserQuestion whether to store one now (run: python3 \""
                 + os.path.join(HERE, "setup-key.py") + "\", which opens the browser) or to "
                 "carry on without; on \"without\" do not ask again this session.")
            return 0
        text = route(prompt, started)
        if text:
            emit(text)
    except Exception as e:  # a routing miss must never block a prompt
        print(f"1337 visual: {type(e).__name__}: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
