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
# records the last request body for assertions, and fails or misbehaves on
# demand. "delayed" sleeps ~6s, "slow" sleeps 20s (past any reasonable timeout),
# "bad-tier" answers with a tier outside TIERS, "no-confidence" omits confidence,
# "not-dict" answers a step with something other than an object, "cased tier"
# answers with padding and mixed case that must still parse, "bad-confidence"
# answers with a non-numeric confidence, "no-model" omits "model" from the
# response entirely.
python3 - "$work" <<'EOF' &
import json, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

work = sys.argv[1]

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        open(f"{work}/last-request.json", "w").write(json.dumps(body))
        open(f"{work}/last-path.txt", "w").write(self.path)
        answers = {}
        no_model = False
        for key in body["questions"]:
            t = body["state"]["steps"][key]["title"].lower()
            if "boom" in t:
                self.send_response(500)
                self.end_headers()
                return
            if "delayed" in t:
                time.sleep(6)
            if "slow" in t:
                time.sleep(20)
                self.send_response(500)
                self.end_headers()
                return
            if "bad-tier" in t:
                answers[key] = {"type": "choice", "choice": "nonsense",
                                "confidence": 0.9, "probabilities": {}}
                continue
            if "no-confidence" in t:
                answers[key] = {"type": "choice", "choice": "sonnet",
                                "probabilities": {"sonnet": 0.9}}
                continue
            if "not-dict" in t:
                answers[key] = "oops-not-a-dict"
                continue
            if "cased tier" in t:
                answers[key] = {"type": "choice", "choice": " Sonnet ",
                                "confidence": 0.9, "probabilities": {"sonnet": 0.9}}
                continue
            if "bad-confidence" in t:
                answers[key] = {"type": "choice", "choice": "sonnet",
                                "confidence": "high", "probabilities": {"sonnet": 0.9}}
                continue
            if "no-model" in t:
                no_model = True
                answers[key] = {"type": "choice", "choice": "sonnet",
                                "confidence": 0.9, "probabilities": {"sonnet": 0.9}}
                continue
            if "unsure" in t:
                tier, confidence = "haiku", 0.3
            elif "concurrency" in t:
                tier, confidence = "opus", 0.95
            elif "endpoint" in t:
                tier, confidence = "sonnet", 0.8
            elif "doubtful opus" in t:
                tier, confidence = "opus", 0.2
            else:
                tier, confidence = "haiku", 0.9
            probs = {p: 0.0 for p in ("haiku", "sonnet", "opus")}
            probs[tier] = confidence
            answers[key] = {"type": "choice", "choice": tier,
                            "confidence": confidence, "probabilities": probs}
        payload = {"answers": answers, "usage": {"input_tokens": 1, "output_tokens": 1}}
        if not no_model:
            payload["model"] = "jev-stand-in"
        out = json.dumps(payload).encode()
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
check_eq "contrastive criteria: what/not_for/examples per tier" \
  "$(jq -c '.questions.step_0.criteria.haiku | keys | sort' "$work/last-request.json")" '["examples","not_for","what"]'
check_eq "default floor is 0.6" "$(printf '%s' "$out" | jq -r '.floor')" "0.6"
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

# previous_attempt is forwarded into state exactly as given, per-step.
withprev='{"task":"t","steps":[{"id":1,"title":"Endpoint retry","previous_attempt":{"tier":"sonnet","outcome":"checker FAIL: missed an edge case"}}]}'
run "$withprev"
check_code "previous_attempt: routed" "$code" 0
check_eq "previous_attempt reaches state" \
  "$(jq -r '.state.steps.step_0.previous_attempt.outcome' "$work/last-request.json")" "checker FAIL: missed an edge case"
check_eq "previous_attempt tier reaches state" \
  "$(jq -r '.state.steps.step_0.previous_attempt.tier' "$work/last-request.json")" "sonnet"

noprev='{"task":"t","steps":[{"id":1,"title":"Rename helper"}]}'
run "$noprev"
check_eq "no previous_attempt: absent from state" \
  "$(jq -r 'has("previous_attempt")' <<< "$(jq -c '.state.steps.step_0' "$work/last-request.json")")" "false"

badprev='{"task":"t","steps":[{"id":1,"title":"Endpoint retry","previous_attempt":{"tier":"medium","outcome":"x"}}]}'
run "$badprev"
check_code "previous_attempt.tier outside TIERS: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (bad previous_attempt tier)" 2

badprevshape='{"task":"t","steps":[{"id":1,"title":"Endpoint retry","previous_attempt":"oops"}]}'
run "$badprevshape"
check_code "previous_attempt not an object: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (previous_attempt not an object)" 2

badconf='{"task":"t","steps":[{"id":1,"title":"Bad-confidence step"}]}'
run "$badconf"
check_code "non-numeric confidence: exit 4" "$code" 4
check_failure_marker "failure marker printed on exit 4 (non-numeric confidence)" 4

nomodel='{"task":"t","steps":[{"id":1,"title":"No-model step"}]}'
run "$nomodel"
check_code "missing model in response: exit 4" "$code" 4
check_failure_marker "failure marker printed on exit 4 (missing model)" 4

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

# --- gaps 36-44 -------------------------------------------------------

six='{"task":"t","steps":[{"title":"a"},{"title":"b"},{"title":"c"},{"title":"d"},{"title":"e"},{"title":"f"}]}'
run "$six"
check_code "more than five steps: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (six steps)" 2

dup='{"task":"t","steps":[{"id":1,"title":"Endpoint one"},{"id":1,"title":"Endpoint two"}]}'
run "$dup"
check_code "duplicate ids: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (duplicate ids)" 2

missing_id='{"task":"t","steps":[{"id":5,"title":"Endpoint A"},{"title":"Endpoint B"}]}'
run "$missing_id"
check_code "missing id alongside an explicit one: routed" "$code" 0
check_eq "explicit id kept, missing id falls back to its index" "$(printf '%s' "$out" | jq -c '[.steps[].id]')" '[5,2]'

cased='{"task":"t","steps":[{"id":1,"title":"Cased tier step"}]}'
run "$cased"
check_code "tier parsed case- and whitespace-insensitively: routed" "$code" 0
check_eq "padded, mixed-case tier still parses" "$(printf '%s' "$out" | jq -r '.steps[0].tier')" "sonnet"

noconf='{"task":"t","steps":[{"id":1,"title":"No-confidence step"}]}'
run "$noconf"
check_code "missing confidence: routed" "$code" 0
check_eq "missing confidence comes back null" "$(printf '%s' "$out" | jq -r '.steps[0].confidence')" "null"
check_eq "missing confidence never escalates" "$(printf '%s' "$out" | jq -r '.steps[0].escalated')" "false"
check_eq "one warning about the missing confidence" "$(grep -c 'no confidence' "$work/stderr")" "1"
check_no_failure_marker "missing confidence is not a routing failure"

notdict='{"task":"t","steps":[{"id":1,"title":"Not-dict step"}]}'
run "$notdict"
check_code "non-dict answer: exit 4" "$code" 4
check_failure_marker "failure marker printed on exit 4 (non-dict answer)" 4

badtier='{"task":"t","steps":[{"id":1,"title":"Bad-tier step"}]}'
run "$badtier"
check_code "tier outside TIERS: exit 4" "$code" 4
check_failure_marker "failure marker printed on exit 4 (bad tier)" 4

CLAUDE_1337_TIER_FLOOR=2 run "$three"
check_code "floor above 1: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (floor above 1)" 2

CLAUDE_1337_TIER_FLOOR=-0.1 run "$three"
check_code "floor below 0: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (floor below 0)" 2

CLAUDE_1337_TIER_FLOOR=nope run "$three"
check_code "floor not a number: exit 2" "$code" 2
check_failure_marker "failure marker printed on exit 2 (floor not a number)" 2

# Transport: with no TYPESAFE_API_KEY, an OpenRouter key routes over the
# decisions endpoint instead, and the request names the OpenRouter model.
TYPESAFE_API_KEY= OPENROUTER_API_KEY=test-or-key \
  OPENROUTER_BASE_URL="http://127.0.0.1:$(cat "$work/port")" run "$three"
check_code "openrouter transport: routed" "$code" 0
check_eq "openrouter path" "$(cat "$work/last-path.txt")" "/api/alpha/decisions"
check_eq "openrouter model in the request" "$(jq -r .model "$work/last-request.json")" "typesafe/jev-1.13"

# Timeout behaviour: delayed ~6s succeeds with the default 20s timeout.
delayed='{"task":"t","steps":[{"id":1,"title":"Delayed step"}]}'
run "$delayed"
check_code "delayed ~6s with default timeout: routed" "$code" 0
check_eq "delayed step resolved successfully" "$(printf '%s' "$out" | jq -r '.steps[0].tier')" "haiku"

# Timeout behaviour: delayed ~6s times out with 1s timeout.
CLAUDE_1337_TIER_TIMEOUT=1 run "$delayed"
check_code "delayed ~6s with 1s timeout: exit 4" "$code" 4
check_failure_marker "failure marker printed on exit 4 (timeout)" 4

# Wall clock: a server that delays ~6s must not cost more than the 1s
# timeout plus the one JevError-triggering attempt.
start=$(date +%s)
CLAUDE_1337_TIER_TIMEOUT=1 run "$delayed"
elapsed=$(( $(date +%s) - start ))
check_code "1s timeout against delayed server: exit 4" "$code" 4
if [ "$elapsed" -lt 5 ]; then
  printf 'ok   %s\n' "wall clock stays within 5s on 1s timeout (${elapsed}s)"
else
  printf 'FAIL %s (%ss)\n' "wall clock stays within 5s on 1s timeout" "$elapsed"; fail=1
fi

# Wall clock: a server that sleeps 20s should fail quickly with a lower timeout.
slow='{"task":"t","steps":[{"id":1,"title":"Slow step"}]}'
start=$(date +%s)
CLAUDE_1337_TIER_TIMEOUT=1 run "$slow"
elapsed=$(( $(date +%s) - start ))
check_code "slow server with 1s timeout: exit 4" "$code" 4
if [ "$elapsed" -lt 5 ]; then
  printf 'ok   %s\n' "wall clock stays within 5s on 1s timeout against slow server (${elapsed}s)"
else
  printf 'FAIL %s (%ss)\n' "wall clock stays within 5s on 1s timeout against slow server" "$elapsed"; fail=1
fi

# The exit-3 text names one setup path, the same in all three places.
setup_path='/1337:visual setup'
for f in "$ROOT/skills/tier/route.py" "$ROOT/hooks/tiered.md" "$ROOT/skills/tier/SKILL.md"; do
  if grep -qF -- "$setup_path" "$f"; then
    printf 'ok   %s\n' "exit-3 setup path named in $(basename "$f")"
  else
    printf 'FAIL %s\n' "exit-3 setup path named in $(basename "$f")"; fail=1
  fi
done

exit $fail
