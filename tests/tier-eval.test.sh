#!/usr/bin/env bash
# Tests for tools/tier-eval.py: dry-run payload shapes, accuracy scoring
# against a stand-in Jev, the escalation column, and the exit codes. Same
# stand-in-server pattern as tests/tier-route.test.sh. Needs python3 and jq;
# no key, no network.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$ROOT/tools/tier-eval.py"
fail=0
work="$(mktemp -d)"
trap 'rm -rf "$work"; [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null' EXIT

check_code() { # description got want
  if [ "$2" -eq "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (exit %s, want %s): %s\n' "$1" "$2" "$3" "$(cat "$work/stderr" 2>/dev/null)"; fail=1; fi
}

check_eq() { # description got want
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=1; fi
}

# A tiny inline fixture: known gold tiers, one row rigged for low confidence
# (escalation), one for a previous failed attempt (should score opus).
fixture="$work/fixture.jsonl"
cat > "$fixture" <<'EOF_FX'
{"id":1,"task":"t","title":"Rename helper","brief":"copy a sibling rename","gold":"haiku"}
{"id":2,"task":"t","title":"New endpoint","brief":"matches existing ones","gold":"sonnet"}
{"id":3,"task":"t","title":"Concurrency lock design","brief":"guard the writer","gold":"opus"}
{"id":4,"task":"t","title":"Unsure rename","brief":"low confidence case","gold":"haiku"}
{"id":5,"task":"t","title":"Already failed endpoint","brief":"retry","gold":"opus","previous_attempt":{"tier":"sonnet","outcome":"failed"}}
EOF_FX

# --- dry-run: no key, no network, payload shapes ---------------------------

unset TYPESAFE_API_KEY OPENROUTER_API_KEY
export CLAUDE_1337_CREDENTIALS="$work/no-such-credentials"

dry_out=$(python3 "$SCRIPT" --fixture "$fixture" --dry-run --variant current,legacy,score,atomic 2>"$work/stderr")
dry_code=$?
check_code "dry-run: exits 0 without a key" "$dry_code" 0

check_eq "dry-run: one payload line per variant per batch" \
  "$(printf '%s\n' "$dry_out" | wc -l)" "4"

check_eq "current: question count matches steps" \
  "$(printf '%s\n' "$dry_out" | jq -c 'select(.variant=="current") | .questions | length')" "5"

check_eq "current: object criteria with what/not_for/examples, three tiers" \
  "$(printf '%s\n' "$dry_out" | jq -c 'select(.variant=="current") | .questions.step_0.criteria | keys')" \
  '["haiku","opus","sonnet"]'
check_eq "current: each tier criterion has the three fields" \
  "$(printf '%s\n' "$dry_out" | jq -c 'select(.variant=="current") | .questions.step_0.criteria.haiku | keys | sort')" \
  '["examples","not_for","what"]'
check_eq "current: previous_attempt reaches state for the retried step" \
  "$(printf '%s\n' "$dry_out" | jq -r 'select(.variant=="current") | .state.steps.step_4.previous_attempt.outcome')" "failed"

check_eq "legacy: plain-string criteria, three tiers" \
  "$(printf '%s\n' "$dry_out" | jq -r 'select(.variant=="legacy") | .questions.step_0.criteria.haiku | type')" \
  "string"
check_eq "legacy: no previous_attempt in state" \
  "$(printf '%s\n' "$dry_out" | jq -r 'select(.variant=="legacy") | .state.steps.step_4 | has("previous_attempt")')" \
  "false"

check_eq "score: three ordered levels" \
  "$(printf '%s\n' "$dry_out" | jq -c 'select(.variant=="score") | .questions.step_0.criteria | length')" "3"
check_eq "score: type is score" \
  "$(printf '%s\n' "$dry_out" | jq -r 'select(.variant=="score") | .questions.step_0.type')" "score"

check_eq "atomic: five Nouls per step" \
  "$(printf '%s\n' "$dry_out" | jq -c 'select(.variant=="atomic") | [.questions | keys[] | select(startswith("step_0__"))] | length')" "5"
check_eq "atomic: questions are type noul" \
  "$(printf '%s\n' "$dry_out" | jq -r 'select(.variant=="atomic") | .questions.step_0__mechanical.type')" "noul"
check_eq "atomic: previous_attempt reaches state for the retried step" \
  "$(printf '%s\n' "$dry_out" | jq -r 'select(.variant=="atomic") | .state.steps.step_4.previous_attempt.outcome')" "failed"

# --- stand-in server: fixed answers, checked accuracy -----------------------

# Answers each question from the step's title (and previous_attempt), the
# same "the case is visible in the input" spirit as tests/tier-route.test.sh.
# "boom" -> HTTP 500 (used by the exit-4 case below).
python3 - "$work" <<'EOF' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

work = sys.argv[1]

def target_tier(title, has_previous):
    t = title.lower()
    if has_previous or "concurrency" in t:
        return "opus"
    if "endpoint" in t:
        return "sonnet"
    return "haiku"  # rename, crud, boilerplate, unsure-rename

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        open(f"{work}/last-request.json", "w").write(json.dumps(body))
        answers = {}
        for qid, q in body["questions"].items():
            step_key = qid.split("__")[0]
            step = body["state"]["steps"][step_key]
            title = step["title"]
            if "boom" in title.lower():
                self.send_response(500)
                self.end_headers()
                return
            has_previous = "previous_attempt" in step
            tier = target_tier(title, has_previous)
            confidence = 0.3 if "unsure" in title.lower() else 0.9
            if q["type"] == "choice":
                probs = {p: 0.0 for p in ("haiku", "sonnet", "opus")}
                probs[tier] = confidence
                answers[qid] = {"type": "choice", "choice": tier,
                                "confidence": confidence, "probabilities": probs}
            elif q["type"] == "score":
                idx = {"haiku": 0, "sonnet": 1, "opus": 2}[tier]
                probs = {p: 0.0 for p in ("haiku", "sonnet", "opus")}
                probs[tier] = confidence
                answers[qid] = {"type": "score", "score": float(idx),
                                "confidence": confidence, "probabilities": probs}
            elif q["type"] == "noul":
                name = qid.split("__", 1)[1]
                if tier == "opus" and has_previous:
                    p = {"mechanical": 0.1, "concurrency": 0.1, "public_api": 0.1,
                         "judgment": 0.2, "failed_before": 0.9}
                elif tier == "opus":
                    p = {"mechanical": 0.1, "concurrency": 0.9, "public_api": 0.1,
                         "judgment": 0.5, "failed_before": 0.1}
                elif tier == "sonnet":
                    p = {"mechanical": 0.4, "concurrency": 0.1, "public_api": 0.1,
                         "judgment": 0.4, "failed_before": 0.1}
                else:
                    p = {"mechanical": 0.9, "concurrency": 0.1, "public_api": 0.1,
                         "judgment": 0.1, "failed_before": 0.1}
                answers[qid] = {"type": "noul", "probability": p[name]}
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

json_out="$work/results.json"
run_out=$(python3 "$SCRIPT" --fixture "$fixture" --json "$json_out" 2>"$work/stderr")
run_code=$?
check_code "stand-in run: all variants exit 0" "$run_code" 0

# current/score carry previous_attempt in state, so both nail the
# retried-endpoint row too; legacy does not build state with it (matching
# the old route.py's own state shape), so it alone misses that one row.
for v in current score; do
  raw_acc=$(jq -r --arg v "$v" '.[$v] | map(select(.raw_tier == .gold)) | length' "$json_out")
  check_eq "$v: raw accuracy is 5/5" "$raw_acc" "5"
  esc_acc=$(jq -r --arg v "$v" '.[$v] | map(select(.escalated_tier == .gold)) | length' "$json_out")
  check_eq "$v: escalated accuracy is 4/5 (unsure row escalates past gold)" "$esc_acc" "4"
  unsure_escalated=$(jq -r --arg v "$v" '.[$v][] | select(.title | test("Unsure")) | .escalated' "$json_out")
  check_eq "$v: the unsure row is flagged escalated" "$unsure_escalated" "true"
  other_escalated=$(jq -r --arg v "$v" '[.[$v][] | select(.title | test("Unsure") | not) | .escalated] | any' "$json_out")
  check_eq "$v: escalation differs from raw only on the unsure row" "$other_escalated" "false"
done

check_eq "legacy: raw accuracy is 4/5 (no previous_attempt in its state, unlike current/score)" \
  "$(jq -r '.legacy | map(select(.raw_tier == .gold)) | length' "$json_out")" "4"
check_eq "legacy: escalated accuracy is 3/5" \
  "$(jq -r '.legacy | map(select(.escalated_tier == .gold)) | length' "$json_out")" "3"
check_eq "legacy: the unsure row is flagged escalated" \
  "$(jq -r '.legacy[] | select(.title | test("Unsure")) | .escalated' "$json_out")" "true"

atomic_acc=$(jq -r '.atomic | map(select(.raw_tier == .gold)) | length' "$json_out")
check_eq "atomic: accuracy is 5/5" "$atomic_acc" "5"
atomic_retry=$(jq -r '.atomic[] | select(.title | test("Already failed")) | .raw_tier' "$json_out")
check_eq "atomic: the retried step lands on opus via failed_before" "$atomic_retry" "opus"

# --- failures ---------------------------------------------------------------

boom_fixture="$work/boom.jsonl"
echo '{"id":1,"task":"t","title":"Boom step","brief":"b","gold":"haiku"}' > "$boom_fixture"
python3 "$SCRIPT" --fixture "$boom_fixture" --variant current >/dev/null 2>"$work/stderr"
check_code "server 500: exit 4" "$?" 4
check_eq "500 explained on stderr" "$(grep -c 'Jev call failed' "$work/stderr")" "1"

TYPESAFE_API_KEY= python3 "$SCRIPT" --fixture "$fixture" --variant current >/dev/null 2>"$work/stderr"
check_code "no key: exit 3" "$?" 3
check_eq "no-key explained on stderr" "$(grep -c 'no key' "$work/stderr")" "1"

python3 "$SCRIPT" --fixture "$work/does-not-exist.jsonl" >/dev/null 2>"$work/stderr"
check_code "missing fixture: exit 2" "$?" 2

bad_gold="$work/bad-gold.jsonl"
echo '{"id":1,"task":"t","title":"x","gold":"medium"}' > "$bad_gold"
python3 "$SCRIPT" --fixture "$bad_gold" --dry-run >/dev/null 2>"$work/stderr"
check_code "gold outside TIERS: exit 2" "$?" 2

python3 "$SCRIPT" --fixture "$fixture" --dry-run --variant nonsense >/dev/null 2>"$work/stderr"
check_code "unknown variant: exit 2" "$?" 2

# A forced-tier override left in the environment must not survive loading
# this eval: it measures Jev, never a forced tier.
override_cleared=$(CLAUDE_1337_TIER_MODEL=opus CLAUDE_PLUGIN_OPTION_TIER_MODEL=opus python3 -c "
import os, runpy
runpy.run_path('$SCRIPT')
print('cleared' if 'CLAUDE_1337_TIER_MODEL' not in os.environ
      and 'CLAUDE_PLUGIN_OPTION_TIER_MODEL' not in os.environ else 'leaked')
")
check_eq "loading tier-eval.py clears the forced-tier override vars" "$override_cleared" "cleared"

exit $fail
