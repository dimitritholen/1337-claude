#!/usr/bin/env python3
"""Make an image, SVG, video or speech file through OpenRouter.

    generate.py --model <id> --modality raster_image|vector_svg|video|speech
                --prompt <text> [--out <path>] [--aspect 16:9] [--duration 8]
                [--voice alloy] [--transparent]

Raster and vector go through POST /api/v1/chat/completions with
modalities ["image"]; the first message.images entry is a data
URL whose media type names the extension (image/svg+xml gives .svg).
Video posts /api/v1/videos, polls the job every few seconds until it is
completed or failed, then downloads the first content URL. Speech posts
/api/v1/audio/speech (mp3) and writes the bytes; the voice is --voice,
else the model's first supported voice from the model list.

--transparent (raster only) posts background: "transparent" and
output_format: "png" to /api/v1/images, for models verified to give a
real alpha channel there (2026-09-22: openai/gpt-5-image-mini, a real
RGBA PNG). catalogue.has_alpha decides which models qualify; a model
without native alpha is refused before any request is sent, since a
diffusion model such as FLUX.2 Klein, Krea or Muse would only spend
credit on a fake checkerboard.

The file goes to --out, else assets/<slug of the prompt>.<ext> under the
current directory, never overwriting (a -2, -3 suffix instead). Stdout
is one JSON line: path, model, modality, media_type, cost (USD from the
API's usage, or null when it reports none). Exit: 0 written, 2 usage
(including --transparent on a non-raster modality), 3 no key, 4 API
failure, 5 the video job failed, 6 the model is unusable for this
account (upstream said why), 7 --transparent on a model with no native
alpha channel. OPENROUTER_BASE_URL redirects the API;
CLAUDE_1337_POLL_SECONDS sets the poll interval (5).
Stdlib only.
"""

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, HERE)
from lib import keys  # noqa: E402
import catalogue  # noqa: E402

MODALITIES = ("raster_image", "vector_svg", "video", "speech")
EXTENSIONS = {
    "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif",
    "image/svg+xml": "svg", "image/avif": "avif",
    "video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov",
    "audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/wav": "wav", "audio/x-wav": "wav",
    "audio/ogg": "ogg", "audio/pcm": "pcm",
}
HTTP_TIMEOUT = 120.0
VIDEO_WAIT = 900.0


class ApiError(Exception):
    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


class JobFailed(Exception):
    pass


class ModelUnusable(Exception):
    """Upstream refused with 403: the account cannot use this model."""

    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def base_url():
    return (os.environ.get("OPENROUTER_BASE_URL") or "https://openrouter.ai").rstrip("/")


def request(method, url, key, body=None, accept="application/json"):
    """One HTTP call. Returns (headers, raw bytes). Raises ApiError."""
    if url.startswith("/"):
        url = base_url() + url
    headers = {"Authorization": f"Bearer {key}", "Accept": accept}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as response:
            return response.headers, response.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        try:
            message = json.loads(detail).get("error", {}).get("message") or detail
        except (ValueError, AttributeError):
            message = detail
        if e.code == 403:
            raise ModelUnusable(e.code, str(message)) from e
        raise ApiError(f"{method} {url.replace(base_url(), '')} answered {e.code}: "
                       f"{str(message)[:300]}", status=e.code) from e
    except (urllib.error.URLError, OSError) as e:
        raise ApiError(f"{method} {url.replace(base_url(), '')} failed: {e}") from e


def request_json(method, url, key, body=None):
    headers, raw = request(method, url, key, body)
    try:
        return json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as e:
        raise ApiError(f"{method} {url} answered with something that is not JSON") from e


def media_ext(media_type, fallback):
    media_type = (media_type or "").split(";")[0].strip().lower()
    return EXTENSIONS.get(media_type, fallback), media_type or None


def cost_of(usage):
    if isinstance(usage, dict) and isinstance(usage.get("cost"), (int, float)):
        return float(usage["cost"])
    return None


# --- the three producers: each returns (bytes, media_type, ext, cost) ---------

def make_image(model, prompt, aspect, key, endpoint, transparent=False):
    if transparent:
        # alpha only exists on /api/v1/images; --endpoint chat/auto do not apply.
        return make_image_via_images(model, prompt, aspect, key, transparent=True)
    if endpoint == "images":
        return make_image_via_images(model, prompt, aspect, key)
    try:
        return make_image_via_chat(model, prompt, aspect, key)
    except ApiError as e:
        # auto falls back once: some models only exist behind /api/v1/images
        # and chat/completions says so in a 404.
        if endpoint == "auto" and e.status == 404 and "/api/v1/images" in str(e):
            return make_image_via_images(model, prompt, aspect, key)
        raise


def make_image_via_chat(model, prompt, aspect, key):
    body = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        # "image" alone: models such as Recraft vector output only images and
        # refuse a request that also asks for text.
        "modalities": ["image"],
        "usage": {"include": True},
    }
    if aspect:
        body["image_config"] = {"aspect_ratio": aspect}
    answer = request_json("POST", "/api/v1/chat/completions", key, body)
    choices = answer.get("choices") or []
    images = (choices[0].get("message") or {}).get("images") if choices else None
    if not images:
        text = ((choices[0].get("message") or {}).get("content") if choices else "") or ""
        raise ApiError(f"{model} returned no image" + (f": {str(text)[:200]}" if text else ""))
    url = (images[0].get("image_url") or {}).get("url") or ""
    match = re.match(r"data:([^;,]+)(;base64)?,(.*)$", url, re.DOTALL)
    if match:
        media_type = match.group(1)
        payload = match.group(3)
        raw = base64.b64decode(payload) if match.group(2) else urllib.parse.unquote_to_bytes(payload)
    elif url.startswith("http"):
        headers, raw = request("GET", url, key, accept="*/*")
        media_type = headers.get("Content-Type")
    else:
        raise ApiError(f"{model} returned an image url I cannot read")
    ext, media_type = media_ext(media_type, "png")
    return raw, media_type, ext, cost_of(answer.get("usage"))


def make_image_via_images(model, prompt, aspect, key, transparent=False):
    body = {"model": model, "prompt": prompt}
    if aspect:
        body["image_config"] = {"aspect_ratio": aspect}
    if transparent:
        body["background"] = "transparent"
        body["output_format"] = "png"
    answer = request_json("POST", "/api/v1/images", key, body)
    data = ((answer.get("data") or [{}])[0])
    b64 = data.get("b64_json")
    if not b64:
        raise ApiError(f"{model} returned no image")
    raw = base64.b64decode(b64)
    ext, media_type = media_ext(data.get("media_type"), "png")
    return raw, media_type, ext, cost_of(answer.get("usage"))


def make_video(model, prompt, aspect, duration, key):
    body = {"model": model, "prompt": prompt}
    if aspect:
        body["aspect_ratio"] = aspect
    if duration:
        body["duration"] = duration
    job = request_json("POST", "/api/v1/videos", key, body)
    job_id = job.get("id")
    if not job_id:
        raise ApiError("POST /api/v1/videos answered without a job id")
    poll_url = job.get("polling_url") or f"/api/v1/videos/{job_id}"
    interval = float(os.environ.get("CLAUDE_1337_POLL_SECONDS", "5"))
    deadline = time.monotonic() + VIDEO_WAIT
    status = job.get("status")
    while status not in ("completed", "failed"):
        if time.monotonic() > deadline:
            raise ApiError(f"video job {job_id} still {status} after {int(VIDEO_WAIT)}s")
        time.sleep(interval)
        job = request_json("GET", poll_url, key)
        status = job.get("status")
    if status == "failed":
        raise JobFailed(f"video job {job_id} failed" + (f": {job['error']}" if job.get("error") else ""))
    urls = job.get("unsigned_urls") or []
    url = urls[0] if urls else f"/api/v1/videos/{job_id}/content?index=0"
    headers, raw = request("GET", url, key, accept="*/*")
    ext, media_type = media_ext(headers.get("Content-Type"), "mp4")
    return raw, media_type, ext, cost_of(job.get("usage"))


def default_voice(model, key):
    try:
        listing = request_json("GET", "/api/v1/models?output_modalities=speech", key)
    except ApiError:
        return None
    for entry in listing.get("data") or []:
        if entry.get("id") == model:
            voices = entry.get("supported_voices") or []
            return voices[0] if voices else None
    return None


def make_speech(model, prompt, voice, key):
    body = {"model": model, "input": prompt, "response_format": "mp3"}
    voice = voice or default_voice(model, key)
    if voice:
        body["voice"] = voice
    headers, raw = request("POST", "/api/v1/audio/speech", key, body, accept="*/*")
    if not raw:
        raise ApiError(f"{model} returned no audio")
    ext, media_type = media_ext(headers.get("Content-Type"), "mp3")
    cost = None
    generation_id = headers.get("X-Generation-Id")
    if generation_id:
        for attempt in range(2):
            try:
                stats = request_json("GET", f"/api/v1/generation?id={urllib.parse.quote(generation_id)}", key)
                data = stats.get("data") or {}
                if isinstance(data.get("total_cost"), (int, float)):
                    cost = float(data["total_cost"])
                break
            except ApiError as e:
                if e.status == 404 and attempt == 0:
                    time.sleep(1)
                    continue
                break
    return raw, media_type, ext, cost


# --- where the file goes ---------------------------------------------------------

def slug(text, limit=60):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return (s[:limit].rstrip("-")) or "output"


def target_path(out, prompt, ext):
    if out:
        path = out
        if not os.path.splitext(path)[1]:
            path = f"{path}.{ext}"
    else:
        path = os.path.join("assets", f"{slug(prompt)}.{ext}")
    root, extension = os.path.splitext(path)
    candidate, n = path, 2
    while os.path.exists(candidate):
        candidate = f"{root}-{n}{extension}"
        n += 1
    return candidate


def main(argv):
    parser = argparse.ArgumentParser(description="Make an image, SVG, video or speech file through OpenRouter.")
    parser.add_argument("--model", required=True)
    parser.add_argument("--modality", required=True, choices=MODALITIES)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--out", help="output path (default assets/<slug>.<ext>)")
    parser.add_argument("--aspect", help="aspect ratio such as 16:9 (image and video)")
    parser.add_argument("--duration", type=int, help="seconds (video)")
    parser.add_argument("--voice", help="voice id (speech)")
    parser.add_argument("--endpoint", choices=("auto", "chat", "images"), default="auto",
                        help="image endpoint to use (raster and vector only, default auto)")
    parser.add_argument("--transparent", action="store_true",
                        help="raster only: a real alpha channel through /api/v1/images")
    args = parser.parse_args(argv[1:])
    if not args.prompt.strip():
        parser.error("--prompt must not be empty")
    if args.transparent and args.modality != "raster_image":
        parser.error("--transparent only applies to --modality raster_image")
    if args.transparent and not catalogue.has_alpha(args.model):
        print(f"generate: {args.model} has no native alpha channel; --transparent on it would "
              "only spend credit on a fake checkerboard", file=sys.stderr)
        return 7

    try:
        key = keys.get("OPENROUTER_API_KEY")
    except (keys.MissingKey, keys.UnsafeFile) as e:
        print(f"generate: {e}", file=sys.stderr)
        return 3

    try:
        if args.modality in ("raster_image", "vector_svg"):
            raw, media_type, ext, cost = make_image(args.model, args.prompt, args.aspect, key,
                                                     args.endpoint, args.transparent)
        elif args.modality == "video":
            raw, media_type, ext, cost = make_video(args.model, args.prompt, args.aspect, args.duration, key)
        else:
            raw, media_type, ext, cost = make_speech(args.model, args.prompt, args.voice, key)
    except JobFailed as e:
        print(f"generate: {e}", file=sys.stderr)
        return 5
    except ModelUnusable as e:
        print(f"generate: {e.message}", file=sys.stderr)
        return 6
    except ApiError as e:
        print(f"generate: {e}", file=sys.stderr)
        return 4

    path = target_path(args.out, args.prompt, ext)
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(path, "wb") as f:
        f.write(raw)
    print(json.dumps({"path": path, "model": args.model, "modality": args.modality,
                      "media_type": media_type, "bytes": len(raw), "cost": cost}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
