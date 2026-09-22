#!/usr/bin/env bash
# Tests for skills/visual/generate.py against a stand-in OpenRouter that
# returns a PNG data URL, an SVG data URL for vector models, a two-step
# video job, audio bytes with a generation id, and fails on demand. Needs
# python3 and jq; no key, no network.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$ROOT/skills/visual/generate.py"
fail=0
work="$(mktemp -d)"
trap 'rm -rf "$work"; [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null' EXIT

python3 - "$work" <<'EOF_SERVER' &
import base64, json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
work = sys.argv[1]
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
SVG = b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>'
MP4 = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 24
MP3 = b"ID3" + b"\x00" * 13
polls = {}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def send(self, status, raw, ctype, extra=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)
    def send_json(self, status, obj, extra=None):
        self.send(status, json.dumps(obj).encode(), "application/json", extra)
    def record(self, body=None):
        with open(f"{work}/requests.jsonl", "a") as f:
            f.write(json.dumps({"method": self.command, "path": self.path,
                                "auth": self.headers.get("Authorization"), "body": body}) + "\n")
    def base(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def do_GET(self):
        self.record()
        if self.path.startswith("/api/v1/videos/") and self.path.endswith("/content?index=0"):
            self.send(200, MP4, "video/mp4"); return
        if self.path.startswith("/api/v1/videos/"):
            job = self.path.rsplit("/", 1)[1]
            polls[job] = polls.get(job, 0) + 1
            if job == "job-fails":
                self.send_json(200, {"id": job, "status": "failed", "error": "provider said no"}); return
            if polls[job] < 2:
                self.send_json(200, {"id": job, "status": "in_progress"}); return
            self.send_json(200, {"id": job, "status": "completed",
                                 "unsigned_urls": [f"{self.base()}/api/v1/videos/{job}/content?index=0"],
                                 "usage": {"cost": 0.25, "is_byok": False}}); return
        if self.path == "/api/v1/models?output_modalities=speech":
            self.send_json(200, {"data": [{"id": "acme/tts", "supported_voices": ["nova", "alloy"]},
                                          {"id": "acme/tts-mute", "supported_voices": []}]}); return
        if self.path.startswith("/api/v1/generation?id="):
            gen = self.path.split("=", 1)[1]
            if gen == "gen-late" and polls.get("gen-late", 0) == 0:
                polls["gen-late"] = 1
                self.send_json(404, {"error": {"message": "not yet"}}); return
            self.send_json(200, {"data": {"id": gen, "total_cost": 0.0003}}); return
        self.send_json(404, {"error": {"message": "no such path"}})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.record(body)
        model = body.get("model", "")
        if "boom" in model:
            self.send_json(500, {"error": {"message": "stand-in exploded"}}); return
        if self.path == "/api/v1/chat/completions":
            if "vector" in model:
                url = "data:image/svg+xml;base64," + base64.b64encode(SVG).decode()
            elif "noimage" in model:
                self.send_json(200, {"choices": [{"message": {"content": "I cannot draw that."}}],
                                     "usage": {"cost": 0.0}}); return
            else:
                url = "data:image/png;base64," + base64.b64encode(PNG).decode()
            self.send_json(200, {"id": "gen-img", "choices": [{"message": {"role": "assistant", "content": "",
                                 "images": [{"type": "image_url", "image_url": {"url": url}}]}}],
                                 "usage": {"prompt_tokens": 10, "completion_tokens": 1000, "cost": 0.0192}}); return
        if self.path == "/api/v1/videos":
            job = "job-fails" if "fail" in model else "job-1"
            self.send_json(200, {"id": job, "status": "pending", "polling_url": f"{self.base()}/api/v1/videos/{job}"}); return
        if self.path == "/api/v1/audio/speech":
            gen = "gen-late" if "late" in model else "gen-audio"
            self.send(200, MP3, "audio/mpeg", {"X-Generation-Id": gen}); return
        self.send_json(404, {"error": {"message": "no such path"}})

server = HTTPServer(("127.0.0.1", 0), Handler)
open(f"{work}/port", "w").write(str(server.server_port))
server.serve_forever()
EOF_SERVER
server_pid=$!
for _ in $(seq 50); do [ -s "$work/port" ] && break; sleep 0.1; done
[ -s "$work/port" ] || { printf 'FAIL stand-in server did not start\n'; exit 1; }
export OPENROUTER_BASE_URL="http://127.0.0.1:$(cat "$work/port")"
export CLAUDE_1337_CREDENTIALS="$work/no-such-file"
export OPENROUTER_API_KEY="test-key"
export CLAUDE_1337_POLL_SECONDS=0
mkdir -p "$work/cwd" && cd "$work/cwd"

check_code() { if [ "$2" -eq "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (exit %s, want %s): %s\n' "$1" "$2" "$3" "$(cat "$work/stderr")"; fail=1; fi; }
check_eq() { if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=1; fi; }
run() { rm -f "$work/requests.jsonl"; out=$("$SCRIPT" "$@" 2>"$work/stderr"); code=$?; }
field() { printf '%s' "$out" | jq -r "$1"; }

# --- raster ------------------------------------------------------------------
run --model acme/paint --modality raster_image --prompt "A red fox, watercolour"
check_code "raster: written" "$code" 0
check_eq "raster: default path is assets/<slug>.png" "$(field .path)" "assets/a-red-fox-watercolour.png"
check_eq "raster: file is the decoded PNG" "$(head -c 8 assets/a-red-fox-watercolour.png | od -An -c | tr -d ' \n')" '211PNG\r\n032\n'
check_eq "raster: media type and cost on stdout" "$(field '[.media_type, .cost, .model, .modality] | @csv')" '"image/png",0.0192,"acme/paint","raster_image"'
check_eq "raster: chat completions with image modality and usage" "$(jq -c 'select(.method=="POST") | [.path, .body.modalities, .body.usage.include, .body.messages[0].content]' "$work/requests.jsonl")" '["/api/v1/chat/completions",["image"],true,"A red fox, watercolour"]'
check_eq "raster: bearer sent" "$(jq -r '.auth' "$work/requests.jsonl")" "Bearer test-key"
check_eq "raster: no image_config without --aspect" "$(jq -c '.body | has("image_config")' "$work/requests.jsonl")" "false"

run --model acme/paint --modality raster_image --prompt "A red fox, watercolour"
check_eq "no overwrite: second run gets -2" "$(field .path)" "assets/a-red-fox-watercolour-2.png"
run --model acme/paint --modality raster_image --prompt "A red fox, watercolour"
check_eq "no overwrite: third run gets -3" "$(field .path)" "assets/a-red-fox-watercolour-3.png"

run --model acme/paint --modality raster_image --prompt "banner" --aspect 16:9 --out out/wide.png
check_eq "--out is honoured, directories made" "$(field .path)" "out/wide.png"
[ -s out/wide.png ] && printf 'ok   --out file exists\n' || { printf 'FAIL --out file missing\n'; fail=1; }
check_eq "--aspect goes into image_config" "$(jq -r '.body.image_config.aspect_ratio' "$work/requests.jsonl")" "16:9"
run --model acme/paint --modality raster_image --prompt "banner" --out out/wide.png
check_eq "--out never overwrites either" "$(field .path)" "out/wide-2.png"
run --model acme/paint --modality raster_image --prompt "x" --out out/noext
check_eq "--out without extension gets the media type's" "$(field .path)" "out/noext.png"

# --- vector ------------------------------------------------------------------
run --model recraft/recraft-v4.1-vector --modality vector_svg --prompt "Fox logo, flat"
check_code "vector: written" "$code" 0
check_eq "vector: svg extension from image/svg+xml" "$(field '[.path, .media_type] | @csv')" '"assets/fox-logo-flat.svg","image/svg+xml"'
check_eq "vector: file holds the SVG" "$(head -c 4 assets/fox-logo-flat.svg)" "<svg"

run --model acme/noimage --modality raster_image --prompt "nothing"
check_code "no image in the answer: exit 4" "$code" 4
check_eq "no image: model's text quoted" "$(grep -c 'returned no image: I cannot draw that' "$work/stderr")" "1"

# --- video -------------------------------------------------------------------
run --model acme/video --modality video --prompt "Sunrise over a lake" --duration 4 --aspect 9:16
check_code "video: written" "$code" 0
check_eq "video: mp4 from the content type, cost from the job" "$(field '[.path, .media_type, .cost] | @csv')" '"assets/sunrise-over-a-lake.mp4","video/mp4",0.25'
check_eq "video: file holds the mp4 bytes" "$(dd if=assets/sunrise-over-a-lake.mp4 bs=1 skip=4 count=4 2>/dev/null)" "ftyp"
check_eq "video: submit, two polls, one download" "$(jq -r '.method + " " + .path' "$work/requests.jsonl" | tr '\n' ';')" "POST /api/v1/videos;GET /api/v1/videos/job-1;GET /api/v1/videos/job-1;GET /api/v1/videos/job-1/content?index=0;"
check_eq "video: duration and aspect in the submit body" "$(jq -c 'select(.method=="POST") | [.body.model, .body.prompt, .body.duration, .body.aspect_ratio]' "$work/requests.jsonl")" '["acme/video","Sunrise over a lake",4,"9:16"]'

run --model acme/video-fail --modality video --prompt "doomed clip"
check_code "failed video job: exit 5" "$code" 5
check_eq "failed job: reason on stderr" "$(grep -c 'video job job-fails failed: provider said no' "$work/stderr")" "1"
[ ! -e assets/doomed-clip.mp4 ] && printf 'ok   failed job: nothing written\n' || { printf 'FAIL failed job wrote a file\n'; fail=1; }

# --- speech ------------------------------------------------------------------
run --model acme/tts --modality speech --prompt "Hello there, listener"
check_code "speech: written" "$code" 0
check_eq "speech: mp3, cost from the generation lookup" "$(field '[.path, .media_type, .cost] | @csv')" '"assets/hello-there-listener.mp3","audio/mpeg",0.0003'
check_eq "speech: file holds the audio bytes" "$(head -c 3 assets/hello-there-listener.mp3)" "ID3"
check_eq "speech: default voice is the model's first supported voice" "$(jq -c 'select(.path=="/api/v1/audio/speech") | [.body.model, .body.input, .body.voice, .body.response_format]' "$work/requests.jsonl")" '["acme/tts","Hello there, listener","nova","mp3"]'
check_eq "speech: generation looked up by the header id" "$(grep -c '"/api/v1/generation?id=gen-audio"' "$work/requests.jsonl")" "1"

run --model acme/tts --modality speech --prompt "Hello again" --voice alloy
check_eq "--voice wins over the default and skips the lookup" "$(jq -c 'select(.path=="/api/v1/audio/speech") | .body.voice' "$work/requests.jsonl")" '"alloy"'
check_eq "--voice: no model list fetched" "$(grep -c 'output_modalities=speech' "$work/requests.jsonl")" "0"

run --model acme/tts-mute --modality speech --prompt "No voices listed"
check_code "model without voices: still sent, no voice field" "$code" 0
check_eq "no voice field when none is known" "$(jq -c 'select(.path=="/api/v1/audio/speech") | .body | has("voice")' "$work/requests.jsonl")" "false"

run --model acme/tts-late --modality speech --prompt "Late stats"
check_eq "generation stats 404 once: retried and found" "$(field .cost)" "0.0003"

# --- failures and usage ---------------------------------------------------------
run --model acme/boom --modality raster_image --prompt "x"
check_code "API 500: exit 4" "$code" 4
check_eq "API 500: message on stderr" "$(grep -c 'answered 500: stand-in exploded' "$work/stderr")" "1"
OPENROUTER_API_KEY= run --model acme/paint --modality raster_image --prompt "x"
check_code "no key: exit 3" "$code" 3
check_eq "no key: no request" "$([ -f "$work/requests.jsonl" ] && wc -l < "$work/requests.jsonl" || echo 0)" "0"
run --model acme/paint --modality hologram --prompt "x"
check_code "bad modality: usage exit 2" "$code" 2
run --model acme/paint --modality raster_image --prompt "   "
check_code "empty prompt: usage exit 2" "$code" 2
OPENROUTER_BASE_URL="http://127.0.0.1:1" run --model acme/paint --modality raster_image --prompt "x"
check_code "unreachable: exit 4" "$code" 4

exit $fail
