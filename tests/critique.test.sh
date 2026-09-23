#!/usr/bin/env bash
# Tests for skills/visual/critique.py against a stand-in OpenRouter that
# plays both the critic (chat/completions with a system message) and the
# generator (chat/completions with modalities:["image"]) sides, plus a
# fake google-chrome for the SVG-rasterisation path. No key, no network.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$ROOT/skills/visual/critique.py"
fail=0
work="$(mktemp -d)"
trap 'rm -rf "$work"; [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null' EXIT

python3 - "$work" <<'EOF_SERVER' &
import base64, json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
work = sys.argv[1]
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

calls = {}


def bump(model):
    calls[model] = calls.get(model, 0) + 1
    return calls[model]


def critic_answer(model):
    """(pass, defects) for one critic call, by model id and call count."""
    n = bump(model)
    if model == "acme/critic-pass":
        return True, []
    if model == "acme/critic-fail-simple":
        return False, [{"type": "artifact", "where": "a smudge", "box": None, "severity": 5, "fix": "remove the smudge"}]
    if model in ("acme/critic-then-pass", "acme/critic-noref-then-pass"):
        if n == 1:
            return False, [{"type": "artifact", "where": "top edge", "box": None, "severity": 5, "fix": "remove the artifact"}]
        return True, []
    if model == "acme/critic-worsening":
        if n == 1:
            return False, [{"type": "other", "where": "a", "box": None, "severity": 3, "fix": "fix a"}]
        if n == 2:
            return False, [{"type": "other", "where": "b", "box": None, "severity": 5, "fix": "fix b"},
                            {"type": "other", "where": "c", "box": None, "severity": 5, "fix": "fix c"}]
        return False, [{"type": "other", "where": "d", "box": None, "severity": 4, "fix": "fix d"},
                        {"type": "other", "where": "e", "box": None, "severity": 2, "fix": "fix e"}]
    raise ValueError(f"stand-in: no script for critic model {model}")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass

    def send_json(self, status, obj):
        raw = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def record(self, body=None):
        with open(f"{work}/requests.jsonl", "a") as f:
            f.write(json.dumps({"method": self.command, "path": self.path,
                                "auth": self.headers.get("Authorization"), "body": body}) + "\n")

    def do_GET(self):
        self.record()
        if self.path == "/api/v1/models?output_modalities=image":
            self.send_json(200, {"data": [
                {"id": "acme/gen", "architecture": {"input_modalities": ["text", "image"]}},
                {"id": "acme/gen-noref", "architecture": {"input_modalities": ["text"]}},
            ]}); return
        self.send_json(404, {"error": {"message": "no such path"}})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.record(body)
        model = body.get("model", "")
        messages = body.get("messages") or []
        is_critic = bool(messages) and messages[0].get("role") == "system"

        if self.path != "/api/v1/chat/completions":
            self.send_json(404, {"error": {"message": "no such path"}}); return

        if is_critic:
            if model.startswith("acme/critic-badjson"):
                n = bump(model)
                if model == "acme/critic-badjson-always" or n == 1:
                    self.send_json(200, {"choices": [{"message": {"role": "assistant", "content": "sorry, I cannot help with that"}}],
                                         "usage": {"cost": 0.001}}); return
                content = json.dumps({"pass": True, "defects": []})
                self.send_json(200, {"choices": [{"message": {"role": "assistant", "content": content}}],
                                     "usage": {"cost": 0.001}}); return
            passed, defects = critic_answer(model)
            content = json.dumps({"pass": passed, "defects": defects})
            self.send_json(200, {"choices": [{"message": {"role": "assistant", "content": content}}],
                                 "usage": {"cost": 0.002}}); return

        # generator side: fix-round image call
        url = "data:image/png;base64," + base64.b64encode(PNG).decode()
        self.send_json(200, {"choices": [{"message": {"role": "assistant", "content": "",
                             "images": [{"type": "image_url", "image_url": {"url": url}}]}}],
                             "usage": {"cost": 0.01}}); return


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
mkdir -p "$work/cwd" && cd "$work/cwd"

check_code() { if [ "$2" -eq "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (exit %s, want %s): %s\n' "$1" "$2" "$3" "$(cat "$work/stderr")"; fail=1; fi; }
check_eq() { if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=1; fi; }
run() { rm -f "$work/requests.jsonl"; out=$("$SCRIPT" "$@" 2>"$work/stderr"); code=$?; }
field() { printf '%s' "$out" | jq -r "$1"; }

TINY_PNG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
printf '%s' "$TINY_PNG_B64" | base64 -d > original.png

# --- pass on the first judge ---------------------------------------------------
run original.png --prompt "A red fox" --model acme/gen --critic acme/critic-pass
check_code "pass first try: exit 0" "$code" 0
check_eq "pass first try: no rounds used" "$(field .rounds)" "0"
check_eq "pass first try: final is the original" "$(field .final)" "original.png"
check_eq "pass first try: pass true" "$(field .pass)" "true"
check_eq "pass first try: files has only the original" "$(field '.files | length')" "1"
check_eq "pass first try: critic id echoed" "$(field .critic)" "acme/critic-pass"
check_eq "pass first try: no generator request" "$(jq -c 'select(.body.model=="acme/gen")' "$work/requests.jsonl" | wc -l | tr -d ' ')" "0"

# --- fail, then fix, then pass; reference sent on the fix round ----------------
run original.png --prompt "A red fox" --model acme/gen --critic acme/critic-then-pass
check_code "fail then fix then pass: exit 0" "$code" 0
check_eq "fail then fix then pass: pass true" "$(field .pass)" "true"
check_eq "fail then fix then pass: one round used" "$(field .rounds)" "1"
check_eq "fail then fix then pass: final is the .r1 file" "$(field .final)" "original.r1.png"
check_eq "fail then fix then pass: files lists original then .r1" "$(field '.files | join(",")')" "original.png,original.r1.png"
[ -s original.r1.png ] && printf 'ok   fail then fix then pass: .r1 file written\n' || { printf 'FAIL .r1 file missing\n'; fail=1; }
fix_body="$(jq -c 'select(.body.model=="acme/gen")' "$work/requests.jsonl")"
check_eq "fix round: prompt carries the fix instruction" "$(printf '%s' "$fix_body" | jq -r '.body.messages[0].content[0].text' | grep -c 'remove the artifact')" "1"
ref_url="$(printf '%s' "$fix_body" | jq -r '.body.messages[0].content[1].image_url.url')"
check_eq "fix round: reference sent as a second image_url part" "$(printf '%s' "$ref_url" | cut -c1-22)" "data:image/png;base64,"
check_eq "fix round: reference decodes to the original's bytes" \
  "$(printf '%s' "$ref_url" | sed 's/^data:image\/png;base64,//' | base64 -d | cmp -s - original.png && echo same || echo different)" "same"

# --- still failing after N rounds: lowest score wins, not the last ------------
run original.png --prompt "A blue jay" --model acme/gen --critic acme/critic-worsening --rounds 2
check_code "still failing after N rounds: exit 0 (not passing isn't an error)" "$code" 0
check_eq "still failing: pass false" "$(field .pass)" "false"
check_eq "still failing: both rounds used" "$(field .rounds)" "2"
check_eq "still failing: final is the original (lowest score 3), not the last (score 6)" "$(field .final)" "original.png"
check_eq "still failing: three files judged" "$(field '.files | length')" "3"

# --- --rounds 0: judge only -----------------------------------------------------
run original.png --prompt "A red fox" --model acme/gen --critic acme/critic-fail-simple --rounds 0
check_code "--rounds 0: exit 0" "$code" 0
check_eq "--rounds 0: rounds used is 0" "$(field .rounds)" "0"
check_eq "--rounds 0: final is the original" "$(field .final)" "original.png"
check_eq "--rounds 0: pass false" "$(field .pass)" "false"
check_eq "--rounds 0: no generator request" "$(jq -c 'select(.body.model=="acme/gen")' "$work/requests.jsonl" | wc -l | tr -d ' ')" "0"

# --- unparseable critic reply -----------------------------------------------------
run original.png --prompt "A red fox" --model acme/gen --critic acme/critic-badjson-always
check_code "unparseable twice: exit 9" "$code" 9
check_eq "unparseable twice: message on stderr" "$(grep -c 'did not answer with parseable JSON' "$work/stderr")" "1"

run original.png --prompt "A red fox" --model acme/gen --critic acme/critic-badjson-once
check_code "unparseable once then valid: exit 0" "$code" 0
check_eq "unparseable once then valid: pass true" "$(field .pass)" "true"
check_eq "unparseable once then valid: no fix round needed" "$(field .rounds)" "0"

# --- model without image input: no reference sent -------------------------------
run original.png --prompt "An owl" --model acme/gen-noref --critic acme/critic-noref-then-pass
check_code "gen model without image input: exit 0" "$code" 0
check_eq "gen model without image input: still fixed and passed" "$(field .pass)" "true"
noref_body="$(jq -c 'select(.body.model=="acme/gen-noref")' "$work/requests.jsonl")"
check_eq "gen model without image input: plain string content, no reference" "$(printf '%s' "$noref_body" | jq -r '.body.messages[0].content | type')" "string"

# --- no key -----------------------------------------------------------------------
OPENROUTER_API_KEY= run original.png --prompt "A red fox" --model acme/gen --critic acme/critic-pass
check_code "no key: exit 3" "$code" 3
check_eq "no key: no request made" "$([ -f "$work/requests.jsonl" ] && wc -l < "$work/requests.jsonl" || echo 0)" "0"

# --- cost log ------------------------------------------------------------------
log="$work/costs/visual.jsonl"
export CLAUDE_1337_VISUAL_LOG="$log"
run original.png --prompt "A red fox" --model acme/gen --critic acme/critic-then-pass
check_code "cost log: run still succeeds" "$code" 0
check_eq "cost log: total cost summed and non-null" "$([ "$(field .cost)" != "null" ] && echo yes || echo no)" "yes"
check_eq "cost log: at least one critique line logged" "$([ "$(grep -c '\"modality\": \"critique\"' "$log")" -ge 1 ] && echo yes || echo no)" "yes"
unset CLAUDE_1337_VISUAL_LOG

# --- SVG input: rasterised when a browser is available, sent as text otherwise --
cat > shape.svg <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 32"><rect width="64" height="32"/></svg>
EOF

mkdir -p "$work/bin-ok"
cat > "$work/bin-ok/google-chrome" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\$arg" in
    --screenshot=*) printf '%s' "$TINY_PNG_B64" | base64 -d > "\${arg#--screenshot=}" ;;
  esac
done
exit 0
EOF
chmod +x "$work/bin-ok/google-chrome"
mkdir -p "$work/bin-empty"
py_dir="$(dirname "$(command -v python3)")"

run_with_path() { rm -f "$work/requests.jsonl"; out=$(PATH="$1" "$SCRIPT" "${@:2}" 2>"$work/stderr"); code=$?; }

run_with_path "$work/bin-ok:$PATH" shape.svg --prompt "A rectangle" --model acme/gen --critic acme/critic-pass
check_code "svg with chrome: exit 0" "$code" 0
svg_body="$(jq -c 'select(.body.model=="acme/critic-pass")' "$work/requests.jsonl")"
svg_content="$(printf '%s' "$svg_body" | jq -r '.body.messages[1].content')"
check_eq "svg with chrome: content is text+image_url (2 parts)" "$(printf '%s' "$svg_content" | jq 'length')" "2"
check_eq "svg with chrome: image part is a PNG data url" "$(printf '%s' "$svg_content" | jq -r '.[1].image_url.url' | cut -c1-22)" "data:image/png;base64,"

run_with_path "$work/bin-empty:$py_dir" shape.svg --prompt "A rectangle" --model acme/gen --critic acme/critic-pass
check_code "svg without chrome: exit 0" "$code" 0
svg_body2="$(jq -c 'select(.body.model=="acme/critic-pass")' "$work/requests.jsonl")"
svg_content2="$(printf '%s' "$svg_body2" | jq -r '.body.messages[1].content')"
check_eq "svg without chrome: content is text only (1 part)" "$(printf '%s' "$svg_content2" | jq 'length')" "1"
check_eq "svg without chrome: svg markup sent as text" "$(printf '%s' "$svg_content2" | jq -r '.[0].text' | grep -c '<svg')" "1"

# --- SVG rasterisation window: sized from the SVG's own aspect ratio, not a fixed square ---
cat > wide.svg <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 100"><rect width="400" height="100"/></svg>
EOF

mkdir -p "$work/bin-record"
cat > "$work/bin-record/google-chrome" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$work/chrome-args"
for arg in "\$@"; do
  case "\$arg" in
    --screenshot=*) printf '%s' "$TINY_PNG_B64" | base64 -d > "\${arg#--screenshot=}" ;;
  esac
done
exit 0
EOF
chmod +x "$work/bin-record/google-chrome"

run_with_path "$work/bin-record:$PATH" wide.svg --prompt "A wide banner" --model acme/gen --critic acme/critic-pass
check_code "wide svg: exit 0" "$code" 0
window_size="$(grep '^--window-size=' "$work/chrome-args")"
check_eq "wide svg: window-size argument present" "$([ -n "$window_size" ] && echo yes || echo no)" "yes"
win_w="$(printf '%s' "$window_size" | sed 's/^--window-size=//' | cut -d, -f1)"
win_h="$(printf '%s' "$window_size" | sed 's/^--window-size=//' | cut -d, -f2)"
check_eq "wide svg: window keeps the SVG's 4:1 aspect ratio" "$((win_w * 100 / win_h))" "400"

exit $fail
