#!/usr/bin/env python3
"""UserPromptSubmit hook: route a visual request to an OpenRouter model.

Reads the hook payload on stdin and stays silent (exit 0, no output)
unless the prompt matches the word prefilter and an OpenRouter key is
stored. A prompt whose stripped text starts with <task-notification> or
<system-reminder> is a system event, not typed input, and is skipped
before the prefilter even runs. Then one Jev Choice says what the prompt asks for (text_or_code,
raster_image, vector_svg, video, speech). The floor applies to the summed
probability of the visual modalities, so a prompt split between SVG and
PNG is not read as doubt; under it means silence. A prompt can carry more
than one modality: every visual one at or above the multi threshold
counts, the likeliest always. Without per-option probabilities the old
rule holds: Jev's pick, its confidence over the floor. Per requested
modality the six cheapest catalogue entries go into one more Choice,
all modalities concurrently: Jev's pick is the recommendation, the
probabilities are the ranking. The output is hook JSON with
additionalContext telling Claude to ask with one AskUserQuestion call,
one question per modality, before anything else (Jev's pick first and
marked Recommended, then cheap to expensive, a price in every label,
plus a stay-with-Claude option) and then run generate.py once per chosen
model.

Budget: the hook runs under a 10-second timeout, so every network call
gets what is left of an internal 9-second deadline, at most 2.5 seconds
each. Any failure exits 0 silently: a routing miss costs nothing, a
blocked prompt would.

CLAUDE_1337_VISUAL=0 disables the hook. CLAUDE_1337_VISUAL_FLOOR moves
the confidence floor (0.5), CLAUDE_1337_VISUAL_MULTI the probability from
which a further modality counts as requested (0.3). Stdlib only, through
lib/ and catalogue.py.
"""

import concurrent.futures
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
SYSTEM_EVENT = re.compile(r"^\s*<(task-notification|system-reminder)\b")
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
VISUAL = [m for m in MODALITIES if m != "text_or_code"]
HEADERS = {"raster_image": "Image model", "vector_svg": "SVG model",
           "video": "Video model", "speech": "Speech model"}  # AskUserQuestion caps at 12
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


def options(ranked, recommended):
    lines = []
    for i, entry in enumerate(ranked, 1):
        tag = " (Recommended)" if entry is recommended else ""
        lines.append(
            f"{i}. {entry['id']}{tag} — {entry['name']}, {price_label(entry)}, "
            f"Jev {entry['probability']:.2f}"
        )
    lines.append(f"{len(ranked) + 1}. Stay with Claude — no OpenRouter call, Claude writes or "
                 "describes it by hand.")
    return lines


def context(prompt, picks):
    """picks: [(modality, ranked, recommended)], likeliest modality first."""
    generate = os.path.join(HERE, "generate.py")
    command = (f"python3 \"{generate}\" --model <chosen id> --modality {{modality}} --prompt "
               "<the user's prompt, verbatim> [--out <path named in the prompt>]")
    if len(picks) == 1:
        modality, ranked, recommended = picks[0]
        lines = [
            f"[1337 visual] This prompt asks for a {modality.replace('_', ' ')}, which an "
            "OpenRouter model can make for a few cents. Before anything else, ask with "
            "AskUserQuestion (one question, header \"Model\") which model should make it, "
            "options in exactly this order and wording:",
        ]
        lines += options(ranked, recommended)
        lines.append(
            f"On a model choice run: {command.format(modality=modality)}, then report the path "
            "and cost it prints. On \"Stay with Claude\" carry on as usual. "
            "Do not ask twice for the same prompt."
        )
        return "\n".join(lines)
    names = " and a ".join(m.replace("_", " ") for m, _, _ in picks)
    lines = [
        f"[1337 visual] This prompt asks for a {names}, which OpenRouter models can make for "
        "a few cents each. Before anything else, ask with one AskUserQuestion call holding "
        f"{len(picks)} questions, one per format, which model should make each, options in "
        "exactly this order and wording:",
    ]
    for modality, ranked, recommended in picks:
        lines.append(f"Question with header \"{HEADERS[modality]}\" (--modality {modality}):")
        lines += options(ranked, recommended)
    lines.append(
        f"For every question answered with a model run: {command.format(modality='<its --modality>')}"
        ", one run per format, each with its own --out when the prompt names paths; then "
        "report every path and cost printed. A question answered \"Stay with Claude\" means "
        "Claude makes that format by hand. Do not ask twice for the same prompt."
    )
    return "\n".join(lines)


def emit(text):
    json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                      "additionalContext": text}}, sys.stdout)
    print()


def requested(answer, floor, multi):
    """The visual modalities the prompt asks for, likeliest first; [] means silence."""
    probabilities = answer.get("probabilities")
    if isinstance(probabilities, dict) and any(m in probabilities for m in VISUAL):
        p = {m: float(probabilities.get(m) or 0.0) for m in VISUAL}
        if sum(p.values()) < floor:
            return []
        ranked = sorted(VISUAL, key=lambda m: -p[m])
        return [ranked[0]] + [m for m in ranked[1:] if p[m] >= multi]
    modality = answer.get("choice")  # no per-option probabilities: the single-choice rule
    if modality not in VISUAL or float(answer.get("confidence") or 0.0) < floor:
        return []
    return [modality]


def pick_models(prompt, modality, floor, started):
    """(modality, ranked, recommended) for one modality, or None without candidates."""
    entries = [e for e in catalogue.models(modality, timeout=budget(started))
               if e["price"] is not None and not e["reference_required"]][:CANDIDATES]
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
    return modality, ranked[:SHOWN], recommended


def route(prompt, started):
    floor = float(os.environ.get("CLAUDE_1337_VISUAL_FLOOR", "0.5"))
    multi = float(os.environ.get("CLAUDE_1337_VISUAL_MULTI", "0.3"))
    answer = jev.decide(
        {"prompt": prompt},
        {"modality": jev.choice(
            "What does the user ask to be produced? Pick text_or_code unless the prompt "
            "clearly asks for a new image, drawing, video or spoken audio file.",
            MODALITIES)},
        timeout=budget(started),
    )["answers"]["modality"]
    modalities = requested(answer, floor, multi)
    if not modalities:
        return None

    # One thread per modality, each call still capped by budget(); a modality
    # whose catalogue or Jev call fails drops out, the others still get asked.
    picks = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(modalities)) as pool:
        futures = [pool.submit(pick_models, prompt, m, floor, started) for m in modalities]
        for modality, future in zip(modalities, futures):
            try:
                pick = future.result()
            except Exception as e:
                print(f"1337 visual: {modality}: {type(e).__name__}: {e}", file=sys.stderr)
                continue
            if pick:
                picks.append(pick)
    return context(prompt, picks) if picks else None


def main():
    if os.environ.get("CLAUDE_1337_VISUAL", "1").lower() in ("0", "off", "false"):
        return 0
    started = time.monotonic()
    try:
        payload = json.load(sys.stdin)
        prompt = payload.get("prompt") if isinstance(payload, dict) else None
    except ValueError:
        return 0
    if not isinstance(prompt, str) or SYSTEM_EVENT.match(prompt):
        return 0
    if not PREFILTER.search(prompt):
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
