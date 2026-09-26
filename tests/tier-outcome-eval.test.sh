#!/usr/bin/env bash
# Tests for tools/tier-outcome-eval.py: dry-run payload shapes, the missing-
# fixture / bad-sha / no-claude exit codes, and one live run against a fake
# `claude` and a fake `ripwire` on a temp PATH.
#
# The harness's PLUGIN_ROOT is hard-coded to the real dirname of the script
# under test (tools/tier-outcome-eval.py -> this repo), not the caller's
# cwd: verify_shas() and every `git worktree`/`git checkout` call run
# against THIS repo regardless of where the test is invoked from. So the
# fixture row here uses a real commit/parent pair already in this repo's
# history (tests/fixtures/tier-outcome-steps.jsonl row o01: the WebFetch
# read-cap fix), and the fake builder "does the work" by lifting that
# commit's own source-path diff with `git show | git apply` in the
# throwaway worktree. No key, no network, no real `claude`.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$ROOT/tools/tier-outcome-eval.py"
fail=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A private TMPDIR for every harness invocation below: the "no leftover
# worktree/temp dir" checks at the end must not be fooled by (or fail
# because of) an unrelated live run elsewhere on the machine sharing the
# system temp dir. tempfile.mkdtemp in the harness honours $TMPDIR with no
# dir= override, so this alone redirects its 1337-outcome-* dirs here.
export TMPDIR="$work/tmp"
mkdir -p "$TMPDIR"

check_code() { # description got want
  if [ "$2" -eq "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (exit %s, want %s): %s\n' "$1" "$2" "$3" "$(cat "$work/stderr" 2>/dev/null)"; fail=1; fi
}

check_eq() { # description got want
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=1; fi
}

# --- fixtures ----------------------------------------------------------

# Real commit pair from this repo: c2bb15b8 fixes hooks/read-cap.sh (and
# hooks/hooks.json) so WebFetch no longer counts as a read; its parent is
# ab94f924. tests/read-cap.test.sh is the hidden test.
COMMIT="c2bb15b8c29aa9734bf2e7332921f53f871c2461"
PARENT="ab94f9241de9986ad349c6c4e4e674c2d37a3133"

fixture="$work/fixture.jsonl"
cat > "$fixture" <<EOF_FX
{"id":"o01","commit":"$COMMIT","parent":"$PARENT","difficulty":"trivial","brief":"stop counting WebFetch as a read in hooks/read-cap.sh","source_paths":["hooks/read-cap.sh","hooks/hooks.json"],"hidden_tests":["tests/read-cap.test.sh"],"test_cmd":"bash tests/read-cap.test.sh"}
EOF_FX

bad_fixture="$work/bad-sha.jsonl"
cat > "$bad_fixture" <<'EOF_FX'
{"id":"bad","commit":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","parent":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","difficulty":"trivial","brief":"x","source_paths":["x"],"hidden_tests":["tests/x.test.sh"],"test_cmd":"true"}
EOF_FX

# --- 1: --dry-run needs no key/network/claude, prints per-tier payloads ----

dry_out=$(python3 "$SCRIPT" --fixture "$fixture" --dry-run --tiers haiku,sonnet,opus 2>"$work/stderr")
check_code "dry-run: exits 0" "$?" 0

check_eq "dry-run: mentions --safe-mode" \
  "$([ "$(printf '%s' "$dry_out" | grep -c -- '--safe-mode')" -ge 1 ] && echo yes || echo no)" "yes"

for t in haiku sonnet opus; do
  check_eq "dry-run: mentions --model for $t" \
    "$([ "$(printf '%s' "$dry_out" | grep -c "\"$t\"")" -ge 1 ] && echo yes || echo no)" "yes"
done

check_eq "dry-run: reviewer_argv carries the review budget (default 0.25)" \
  "$([ "$(printf '%s' "$dry_out" | grep -c -- '"--max-budget-usd", "0.25"')" -ge 1 ] && echo yes || echo no)" "yes"

# --- 2: missing fixture / bad sha -------------------------------------------

python3 "$SCRIPT" --fixture "$work/does-not-exist.jsonl" --dry-run >/dev/null 2>"$work/stderr"
check_code "missing fixture: exit 2" "$?" 2

python3 "$SCRIPT" --fixture "$bad_fixture" --dry-run >/dev/null 2>"$work/stderr"
check_code "bad sha in fixture: exit 2" "$?" 2

# --- 3: no `claude` on PATH (live mode) -> exit 3 ---------------------------

PATH=/usr/bin:/bin python3 "$SCRIPT" --fixture "$fixture" --no-route --tiers haiku \
  >/dev/null 2>"$work/stderr"
check_code "no claude on PATH: exit 3" "$?" 3

# --- fake `claude` and `ripwire` on a temp PATH -----------------------------

bin="$work/bin"
mkdir -p "$bin"

cat > "$bin/claude" <<'EOF_CLAUDE'
#!/usr/bin/env bash
# Stand-in for `claude -p ...`. Builder calls carry --allowedTools; the
# reviewer call carries --tools "" instead -- that alone tells them apart.
is_builder=0
model=""
prev=""
for a in "$@"; do
  case "$prev" in --model) model="$a" ;; esac
  [ "$a" = "--allowedTools" ] && is_builder=1
  prev="$a"
done

if [ "$is_builder" = 1 ]; then
  case "$model" in
    haiku)
      # Outlasts --run-timeout so the harness kills it and records a timeout.
      sleep 20
      ;;
    *)
      # sonnet/opus "do the work": lift the real commit's own source diff.
      git show "$FAKE_CLAUDE_COMMIT" -- $FAKE_CLAUDE_SOURCE_PATHS | git apply
      ;;
  esac
  printf '{"result":"applied the fix","total_cost_usd":0.010,"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"num_turns":1,"is_error":false}\n'
else
  cat >/dev/null  # reviewer prompt arrives on stdin
  printf '{"result":"{\\"correctness\\":4,\\"design\\":4,\\"maintainability\\":4,\\"notes\\":\\"x\\"}","total_cost_usd":0.001,"usage":{"input_tokens":5,"output_tokens":5},"num_turns":1,"is_error":false}\n'
fi
EOF_CLAUDE
chmod +x "$bin/claude"

cat > "$bin/ripwire" <<'EOF_RIPWIRE'
#!/usr/bin/env bash
exit 0
EOF_RIPWIRE
chmod +x "$bin/ripwire"

export FAKE_CLAUDE_COMMIT="$COMMIT"
export FAKE_CLAUDE_SOURCE_PATHS="hooks/read-cap.sh hooks/hooks.json"

# --- 4: live fake run --------------------------------------------------

raw="$work/raw.jsonl"
run_out=$(PATH="$bin:/usr/bin:/bin" python3 "$SCRIPT" --fixture "$fixture" --no-route \
  --run-timeout 15 --run-budget 5 --out "$raw" 2>"$work/stderr")
run_code=$?
check_code "live run: exits 0" "$run_code" 0

check_eq "raw.jsonl has 3 rows (one per tier)" "$(wc -l < "$raw" | tr -d ' ')" "3"

hp_haiku=$(jq -r 'select(.tier=="haiku") | .hidden_pass' "$raw")
hp_sonnet=$(jq -r 'select(.tier=="sonnet") | .hidden_pass' "$raw")
hp_opus=$(jq -r 'select(.tier=="opus") | .hidden_pass' "$raw")
check_eq "sonnet: hidden_pass true (applied the fix)" "$hp_sonnet" "true"
check_eq "opus: hidden_pass true (applied the fix)" "$hp_opus" "true"
check_eq "haiku: hidden_pass not true (timed out, no fix applied)" \
  "$([ "$hp_haiku" != "true" ] && echo ok || echo bad)" "ok"

check_eq "haiku: builder_timeout true" \
  "$(jq -r 'select(.tier=="haiku") | .builder_timeout' "$raw")" "true"
check_eq "haiku: builder_cost_usd is null" \
  "$(jq -r 'select(.tier=="haiku") | .builder_cost_usd' "$raw")" "null"

check_eq "haiku: hidden_fail_lines is non-empty for the failing tier" \
  "$([ "$(jq -r 'select(.tier=="haiku") | .hidden_fail_lines | length' "$raw")" -gt 0 ] && echo yes || echo no)" "yes"
check_eq "haiku: every hidden_fail_lines entry starts with FAIL " \
  "$(jq -r 'select(.tier=="haiku") | .hidden_fail_lines[] | startswith("FAIL ")' "$raw" | grep -c false)" "0"

check_eq "sonnet: review_attempts has at least one entry" \
  "$([ "$(jq -r 'select(.tier=="sonnet") | .review_attempts | length' "$raw")" -ge 1 ] && echo yes || echo no)" "yes"
check_eq "sonnet: review_attempts[0] carries exit/cost_usd/num_turns/stdout" \
  "$(jq -r 'select(.tier=="sonnet") | .review_attempts[0] | (.exit != null and .cost_usd != null and .num_turns != null and (.stdout | length) > 0)' "$raw")" "true"

# --- 5: report text --------------------------------------------------------

check_eq "report: err/timeout count is 1 for haiku" \
  "$(printf '%s\n' "$run_out" | awk '$1=="haiku"{print $3; exit}')" "1"
check_eq "report: has a total \$ line" \
  "$(printf '%s\n' "$run_out" | grep -c '^total \$:')" "1"

# --- 6: --report re-prints the table from a saved log -----------------------

report_out=$(PATH="$bin:/usr/bin:/bin" python3 "$SCRIPT" --report "$raw" 2>"$work/stderr")
check_code "--report: exits 0" "$?" 0
check_eq "--report: re-prints the total \$ line" \
  "$(printf '%s\n' "$report_out" | grep -c '^total \$:')" "1"

# --- parse_scores: a `}` inside notes must not break the non-greedy match --

parse_out=$(python3 - "$SCRIPT" <<'EOF_PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("tier_outcome_eval", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

text = '{"correctness": 4, "design": 3, "maintainability": 5, "notes": "ok (see {x}) fine"}'
scores = mod.parse_scores(text)
assert scores == {"correctness": 4, "design": 3, "maintainability": 5, "notes": "ok (see {x}) fine"}, scores

fenced = "```json\n" + text + "\n```"
assert mod.parse_scores(fenced) == scores

prefixed = 'here you go: ' + text
assert mod.parse_scores(prefixed) == scores

assert mod.parse_scores("not json") is None
assert mod.parse_scores(None) is None
print("ok")
EOF_PY
)
check_eq "parse_scores: '}' inside notes, fenced and prefixed replies all parse" "$parse_out" "ok"

# --- 7: no worktree or temp-dir leftovers -----------------------------------
# Scoped to this run's own private TMPDIR (see above), not the whole
# machine: a live run elsewhere must not make these checks flaky.

leftover_wt=$(git -C "$ROOT" worktree list --porcelain | awk -v t="$TMPDIR" \
  '$1=="worktree" && index($2, t)==1 {n++} END{print n+0}')
check_eq "no leftover git worktrees under this run's TMPDIR" "$leftover_wt" "0"
leftover=$(find "$TMPDIR" -maxdepth 1 -name '1337-outcome-*' 2>/dev/null | wc -l | tr -d ' ')
check_eq "no leftover 1337-outcome-* temp dirs under this run's TMPDIR" "$leftover" "0"

# A forced-tier override left in the environment must not reach route.py's
# own subprocess call: this harness measures Jev, never a forced tier.
override_cleared=$(CLAUDE_1337_TIER_MODEL=opus CLAUDE_PLUGIN_OPTION_TIER_MODEL=opus python3 -c "
import os, runpy
runpy.run_path('$SCRIPT')
print('cleared' if 'CLAUDE_1337_TIER_MODEL' not in os.environ
      and 'CLAUDE_PLUGIN_OPTION_TIER_MODEL' not in os.environ else 'leaked')
")
check_eq "loading tier-outcome-eval.py clears the forced-tier override vars" "$override_cleared" "cleared"

exit $fail
