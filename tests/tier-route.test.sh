#!/usr/bin/env bash
# Tests for skills/tier/route.py: runs it against a local stand-in for the
# TypeSafe API and asserts the routed tiers, the escalation rule and the exit
# codes. The stand-in picks its answer from the step title, so every case is
# visible in the input. Needs python3 and jq; no key, no network.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$ROOT/skills/tier/route.py"
fail=0
work="$(mktemp -d)"
trap 'rm -rf "$work"; [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null' EXIT

# The stand-in API: answers each step_N choice from the words in its title,
# records the last request body for assertions, and fails on demand.
python3 - "$work" <<'EOF' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

work = sys.argv[1]

def answer(title):
    t = title.lower()
    if "boom" in t:
        return None
    if "unsure" in t:
        return "haiku", 0.3
    if "concurrency" in t:
        return "opus", 0.95
    if "endpoint" in t:
        return "sonnet", 0.8
    if "doubtful opus" in t:
        return "opus", 0.2
    return "haiku", 0.9

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        open(f"{work}/last-request.json", "w").write(json.dumps(body))
        answers = {}
        for key in body["questions"]:
            picked = answer(body["state"]["steps"][key]["title"])
            if picked is None:
                self.send_response(500)
                self.end_headers()
                return
            tier, confidence = picked
            probs = {t: 0.0 for t in ("haiku", "sonnet", "opus")}
            probs[tier] = confidence
            answers[key] = {"type": "choice", "choice": tier,
                            "confidence": confidence, "probabilities": probs}
        out = json.dumps({"model": "jev-stand-in", "answers": answers,
                          "usage": {"input_tokens": 1, "output_tokens": 1}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

server = HTTPServer(("127.0.0.1", 0), Handler)
open(f"{work}/port", "w").write(str(server.server_port))
server.serve_forever()
EOF
server_pid=$!
for _ in $(seq 50); do [ -s "$work/port" ] && break; sleep 0.1; done
[ -s "$work/port" ] || { printf 'FAIL stand-in server did not start\n'; exit 1; }
export TYPESAFE_BASE_URL="http://127.0.0.1:$(cat "$work/port")"
export TYPESAFE_API_KEY="test-key"
# No credentials file and no OpenRouter key, so the "no key" case is real.
export CLAUDE_1337_CREDENTIALS="$work/no-such-credentials"
unset CLAUDE_1337_TIER_FLOOR OPENROUTER_API_KEY OPENROUTER_BASE_URL TYPESAFE_DEFAULT_MODEL

run() { # input-json -> stdout in $out (main JSON only), exit code in $code, marker in $marker
  raw_output=$(printf '%s' "$1" | "$SCRIPT" 2>"$work/stderr"); code=$?
  # Split output into main JSON and marker line (only if there's output)
  if [ -z "$raw_output" ]; then
    out=""
    marker=""
  else
    # Last line is the marker, rest is the main JSON
    marker=$(printf '%s' "$raw_output" | tail -n 1)
    out=$(printf '%s' "$raw_output" | head -n -1)
  fi
}

check_code() { # description got want
  if [ "$2" -eq "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (exit %s, want %s): %s\n' "$1" "$2" "$3" "$(cat "$work/stderr")"; fail=1; fi
}

check_eq() { # description got want
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=1; fi
}

check_marker_prefix() { # description
  prefix=$(printf '%s' "$marker" | cut -c1-17)
  if [ "$prefix" = "1337-tier-route: " ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got prefix: %s)\n' "$1" "$prefix"; fail=1; fi
}

check_marker_json() { # description
  marker_json=$(printf '%s' "$marker" | sed 's/^1337-tier-route: //')
  if printf '%s' "$marker_json" | jq . > /dev/null 2>&1; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (marker JSON does not parse)\n' "$1"; fail=1; fi
}

check_failure_marker() { # description want-exit-code
  want="1337-tier-failed: {\"exit\":$2}"
  if grep -qF -- "$want" "$work/stderr"; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s (want %s in stderr: %s)\n' "$1" "$want" "$(cat "$work/stderr")"; fail=1
  fi
}

check_no_failure_marker() { # description
  if grep -qF -- '1337-tier-failed: ' "$work/stderr"; then
    printf 'FAIL %s (failure marker present on success: %s)\n' "$1" "$(cat "$work/stderr")"; fail=1
  else
    printf 'ok   %s\n' "$1"
  fi
}

three='{"task":"Add a --json flag to the todo CLI","steps":[
  {"id":1,"title":"Rename the list helper","brief":"todo.py: cmd_list -> print_list"},
  {"id":2,"title":"Add the endpoint for JSON output","brief":"todo.py: new branch in cmd_list"},
  {"id":3,"title":"Handle concurrency on the DB file","brief":"todo.py: lock around save()"}]}'

run "$three"
check_code "three steps: routed" "$code" 0
check_eq "tiers follow the answers" "$(printf '%s' "$out" | jq -c '[.steps[].tier]')" '["haiku","sonnet","opus"]'
check_eq "ids come back in order" "$(printf '%s' "$out" | jq -c '[.steps[].id]')" '[1,2,3]'
check_eq "nothing escalated" "$(printf '%s' "$out" | jq -c '[.steps[].escalated]')" '[false,false,false]'
check_eq "model reported" "$(printf '%s' "$out" | jq -r .model)" "jev-stand-in"
check_eq "one question per step" "$(jq '.questions | length' "$work/last-request.json")" "3"
check_eq "task in state" "$(jq -r '.state.task' "$work/last-request.json")" "Add a --json flag to the todo CLI"
check_eq "brief in state" "$(jq -r '.state.steps.step_2.brief' "$work/last-request.json")" "todo.py: lock around save()"
check_eq "question names its step" "$(jq -r '.questions.step_1.instructions' "$work/last-request.json" | grep -c 'steps.step_1')" "1"
check_eq "three tiers offered" "$(jq -c '.questions.step_0.criteria | keys' "$work/last-request.json")" '["haiku","opus","sonnet"]'
check_marker_prefix "marker starts at column 0 with exact prefix"
check_marker_json "marker JSON parses"
check_eq "marker tiers match main output" "$(printf '%s' "$marker" | sed 's/^1337-tier-route: //' | jq -c '[.steps[].tier]')" '["haiku","sonnet","opus"]'
check_eq "marker has same step ids" "$(printf '%s' "$marker" | sed 's/^1337-tier-route: //' | jq -c '[.steps[].id]')" '[1,2,3]'
check_eq "marker has confidence values" "$(printf '%s' "$marker" | sed 's/^1337-tier-route: //' | jq -c '[.steps[].confidence]')" '[0.9,0.8,0.95]'
check_eq "marker has escalated flags" "$(printf '%s' "$marker" | sed 's/^1337-tier-route: //' | jq -c '[.steps[].escalated]')" '[false,false,false]'
check_no_failure_marker "success: no failure marker on stderr"

unsure='{"task":"t","steps":[{"id":"a","title":"Unsure rename"},{"id":"b","title":"Doubtful opus step"}]}'
run "$unsure"
check_code "low confidence: routed" "$code" 0
check_eq "haiku under the floor escalates to sonnet" "$(printf '%s' "$out" | jq -r '.steps[0].tier')" "sonnet"
check_eq "escalation is flagged" "$(printf '%s' "$out" | jq -r '.steps[0].escalated')" "true"
check_eq "opus under the floor stays opus" "$(printf '%s' "$out" | jq -r '.steps[1].tier')" "opus"
check_eq "opus is not flagged" "$(printf '%s' "$out" | jq -r '.steps[1].escalated')" "false"
check_eq "confidence passed through" "$(printf '%s' "$out" | jq -r '.steps[0].confidence')" "0.3"
check_marker_prefix "escalation case: marker has prefix"
check_eq "marker reflects escalation" "$(printf '%s' "$marker" | sed 's/^1337-tier-route: //' | jq -c '[.steps[].escalated]')" '[true,false]'

CLAUDE_1337_TIER_FLOOR=0.2 run "$unsure"
check_eq "lower floor: no escalation" "$(printf '%s' "$out" | jq -c '[.steps[].tier, .floor]')" '["haiku","opus",0.2]'

run '{"task":"t","steps":[{"title":"Boom"}]}'
check_code "API 500: exit 4" "$code" 4
check_eq "failure explained on stderr" "$(grep -c 'Jev call failed' "$work/stderr")" "1"
check_eq "success marker absent on exit 4" "$marker" ""
check_failure_marker "failure marker printed on exit 4" 4

run 'not json'
check_code "bad input: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (not json)" 2
run '{"task":"t","steps":[]}'
check_code "no steps: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (no steps)" 2
run '{"task":"","steps":[{"title":"x"}]}'
check_code "empty task: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (empty task)" 2
run '{"task":"t","steps":[{"brief":"no title"}]}'
check_code "step without title: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (no title)" 2

TYPESAFE_API_KEY= run "$three"
check_code "no key: exit 3" "$code" 3
check_eq "no key explained on stderr" "$(grep -c 'TYPESAFE_API_KEY' "$work/stderr")" "1"
check_eq "success marker absent on exit 3" "$marker" ""
check_failure_marker "failure marker printed on exit 3" 3

# The file-argument form reads the same input.
printf '%s' "$three" > "$work/in.json"
out=$("$SCRIPT" "$work/in.json" 2>/dev/null); code=$?
check_code "file argument: routed" "$code" 0

exit $fail
