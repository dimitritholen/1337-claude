#!/usr/bin/env bash
# Tests for hooks/review-gate.sh: feeds crafted PreToolUse payloads with
# fixture JSONL transcripts and asserts the exit code (and stderr, where the
# message content matters). Exit 2 = refused, exit 0 = allowed. Runs inside
# a scratch git repo (the hook fails open outside one).
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/review-gate.sh"
fail=0

REPO="$(mktemp -d)"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init

TMPDIR="$(mktemp -d)"
export TMPDIR
trap 'rm -rf "$TMPDIR" "$REPO"' EXIT

MODE_ORCH="CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=false CLAUDE_1337_ORCHESTRATOR=1 EVAL_CLAUDE_1337_ORCHESTRATOR=0"
MODE_OFF="CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=false CLAUDE_1337_ORCHESTRATOR=0 EVAL_CLAUDE_1337_ORCHESTRATOR=0"

run_hook() { # extra-env payload
  (cd "$REPO" && printf '%s' "$2" | env $1 "$HOOK" 2>&1 >/dev/null)
}

check() { # expected-exit description extra-env payload
  local got out
  out="$(run_hook "$3" "$4")"
  got=$?
  if [ "$got" -eq "$1" ]; then
    printf 'ok   %s\n' "$2"
  else
    printf 'FAIL %s (exit %s, want %s; stderr: %s)\n' "$2" "$got" "$1" "$out"; fail=1
  fi
}

check_grep() { # expected-exit want-in-stderr description extra-env payload
  local got out
  out="$(run_hook "$4" "$5")"
  got=$?
  if [ "$got" -eq "$1" ] && printf '%s' "$out" | grep -q "$2"; then
    printf 'ok   %s\n' "$3"
  else
    printf 'FAIL %s (exit %s, want %s; stderr: %s)\n' "$3" "$got" "$1" "$out"; fail=1
  fi
}

# --- transcript builders: everything appends, in order ---
t_tool() { printf '%s\n' "$1" >> "$2"; }

builder_line() { # subagent_type-value (always 1337:builder), tool-use id
  jq -c -n --arg id "$1" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",input:{subagent_type:"1337:builder",model:"sonnet"}}]}}'
}
builder_result_line() { # tool-use id
  jq -c -n --arg id "$1" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:"builder report: done"}]}}'
}
git_diff_line() {
  jq -c -n '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:"git diff HEAD -- foo.py"}}]}}'
}
skill_review_line() {
  jq -c -n '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Skill",input:{skill:"1337:review"}}]}}'
}
slash_review_line() {
  jq -c -n '{type:"user",message:{role:"user",content:"<command-message>1337:review</command-message>\n<command-name>/1337:review</command-name>\n<command-args></command-args>"}}'
}
checker_line() { # tool-use id
  jq -c -n --arg id "$1" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",input:{subagent_type:"1337:checker"}}]}}'
}
checker_result_line() { # tool-use id, PASS-or-FAIL text
  jq -c -n --arg id "$1" --arg body "$2" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$body}]}}'
}
scout_line() {
  jq -c -n '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Agent",input:{subagent_type:"1337:scout",model:"haiku"}}]}}'
}

commit_payload() { # transcript_path
  jq -c -n --arg tr "$1" '{tool_name:"Bash",tool_input:{command:"git commit -m x"},transcript_path:$tr,session_id:"s"}'
}
dispatch_payload() { # subagent_type transcript_path
  jq -c -n --arg s "$1" --arg tr "$2" '{tool_name:"Agent",tool_input:{subagent_type:$s,model:"sonnet"},transcript_path:$tr,session_id:"s"}'
}

# A diff over CLAUDE_1337_REVIEW_MIN_LINES (default 20), staged so it shows
# up in `git diff --numstat HEAD`, so the size carve-out doesn't swallow
# every case below.
i=0; while [ "$i" -lt 30 ]; do printf 'x = 1\n' >> "$REPO/big.py"; i=$((i + 1)); done
git -C "$REPO" add big.py

# --- case 1: builder result, nothing after it, then git commit -> refused ---
tr1="$TMPDIR/tr1.jsonl"
t_tool "$(builder_line b1)" "$tr1"
t_tool "$(builder_result_line b1)" "$tr1"
check_grep 2 'run since' "commit gate: nothing after builder result: refused" \
  "$MODE_ORCH" "$(commit_payload "$tr1")"

# --- case 2: same, but only a git diff after -> still refused (needs both) ---
tr2="$TMPDIR/tr2.jsonl"
t_tool "$(builder_line b1)" "$tr2"
t_tool "$(builder_result_line b1)" "$tr2"
t_tool "$(git_diff_line)" "$tr2"
check_grep 2 'run since' "commit gate: git diff alone: still refused" \
  "$MODE_ORCH" "$(commit_payload "$tr2")"
check_grep 2 '`/1337:review` has not run since' \
  "commit gate: only the diff ran: message names the missing review" \
  "$MODE_ORCH" "$(commit_payload "$tr2")"

# --- case 3: same, but only a review invocation after -> still refused ---
tr3="$TMPDIR/tr3.jsonl"
t_tool "$(builder_line b1)" "$tr3"
t_tool "$(builder_result_line b1)" "$tr3"
t_tool "$(skill_review_line)" "$tr3"
check_grep 2 'run since' "commit gate: review invocation alone: still refused" \
  "$MODE_ORCH" "$(commit_payload "$tr3")"
check_grep 2 '`git diff` has not run since' \
  "commit gate: only the review ran: message names the missing diff" \
  "$MODE_ORCH" "$(commit_payload "$tr3")"

# --- case 4: both present -> allowed ---
tr4="$TMPDIR/tr4.jsonl"
t_tool "$(builder_line b1)" "$tr4"
t_tool "$(builder_result_line b1)" "$tr4"
t_tool "$(git_diff_line)" "$tr4"
t_tool "$(skill_review_line)" "$tr4"
check 0 "commit gate: git diff and review invocation both present: allowed" \
  "$MODE_ORCH" "$(commit_payload "$tr4")"

# --- case 4b: the slash-command form of the review invocation counts too ---
tr4b="$TMPDIR/tr4b.jsonl"
t_tool "$(builder_line b1)" "$tr4b"
t_tool "$(builder_result_line b1)" "$tr4b"
t_tool "$(git_diff_line)" "$tr4b"
t_tool "$(slash_review_line)" "$tr4b"
check 0 "commit gate: git diff + typed /1337:review: allowed" \
  "$MODE_ORCH" "$(commit_payload "$tr4b")"

# --- case 5: a second builder dispatch with an unreviewed first -> refused ---
tr5="$TMPDIR/tr5.jsonl"
t_tool "$(builder_line b1)" "$tr5"
t_tool "$(builder_result_line b1)" "$tr5"
check_grep 2 'unreviewed' "dispatch gate: unreviewed first builder: refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr5")"

# --- case 6: with both signals present -> allowed ---
tr6="$TMPDIR/tr6.jsonl"
t_tool "$(builder_line b1)" "$tr6"
t_tool "$(builder_result_line b1)" "$tr6"
t_tool "$(git_diff_line)" "$tr6"
t_tool "$(skill_review_line)" "$tr6"
check 0 "dispatch gate: both signals present: allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr6")"

# --- case 7: a checker failure between them -> the retry dispatch allowed ---
tr7="$TMPDIR/tr7.jsonl"
t_tool "$(builder_line b1)" "$tr7"
t_tool "$(builder_result_line b1)" "$tr7"
t_tool "$(checker_line c1)" "$tr7"
t_tool "$(checker_result_line c1 "FAIL

tests broke: 3 assertions failed")" "$tr7"
check 0 "dispatch gate: checker FAIL after builder: retry dispatch allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7")"

# --- case 7b: a checker PASS does not exempt anything ---
tr7b="$TMPDIR/tr7b.jsonl"
t_tool "$(builder_line b1)" "$tr7b"
t_tool "$(builder_result_line b1)" "$tr7b"
t_tool "$(checker_line c1)" "$tr7b"
t_tool "$(checker_result_line c1 "PASS")" "$tr7b"
check_grep 2 'unreviewed' "dispatch gate: checker PASS: no exemption, still refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7b")"

# --- case 7c: NEW verdict format (token alone on the first line, body
# after) still fires the retry exemption ---
tr7c="$TMPDIR/tr7c.jsonl"
t_tool "$(builder_line b1)" "$tr7c"
t_tool "$(builder_result_line b1)" "$tr7c"
t_tool "$(checker_line c1)" "$tr7c"
t_tool "$(checker_result_line c1 "FAIL

PASS/FAIL split by criterion — overall verdict: **FAIL**")" "$tr7c"
check 0 "dispatch gate: checker result in NEW verdict-token format reporting FAIL: retry allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7c")"

# --- case 7d: a passing verdict token with "0 FAIL lines" in the body must
# NOT be mistaken for a failure by a loose substring match ---
tr7d="$TMPDIR/tr7d.jsonl"
t_tool "$(builder_line b1)" "$tr7d"
t_tool "$(builder_result_line b1)" "$tr7d"
t_tool "$(checker_line c1)" "$tr7d"
t_tool "$(checker_result_line c1 "PASS

0 FAIL lines, 42 passed")" "$tr7d"
check_grep 2 'unreviewed' "dispatch gate: PASS verdict with '0 FAIL lines' in body: no false exemption, still refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7d")"

# --- case 8: a 1337:scout dispatch -> never refused, whatever the state ---
check 0 "dispatch gate: 1337:scout dispatch: never refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:scout "$tr5")"

# --- case 9: diff of 12 lines -> allowed with no review at all. Own scratch
# repo so it isn't drowned out by "big.py" staged above. ---
REPO_SMALL="$(mktemp -d)"
git -C "$REPO_SMALL" init -q
git -C "$REPO_SMALL" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
i=0; while [ "$i" -lt 12 ]; do printf 'a\n' >> "$REPO_SMALL/small.py"; i=$((i + 1)); done
git -C "$REPO_SMALL" add small.py
tr9="$TMPDIR/tr9.jsonl"
t_tool "$(builder_line b1)" "$tr9"
t_tool "$(builder_result_line b1)" "$tr9"
out9=$(cd "$REPO_SMALL" && printf '%s' "$(commit_payload "$tr9")" | env $MODE_ORCH "$HOOK" 2>&1 >/dev/null)
got9=$?
if [ "$got9" -eq 0 ]; then
  printf 'ok   %s\n' "size carve-out: small staged diff: commit allowed with no review"
else
  printf 'FAIL %s (exit %s, want 0; stderr: %s)\n' "size carve-out: small staged diff: commit allowed with no review" "$got9" "$out9"; fail=1
fi
rm -rf "$REPO_SMALL"

# --- case 10: mode off -> allowed ---
check 0 "orchestrator mode off: allowed" \
  "$MODE_OFF" "$(commit_payload "$tr1")"

# --- case 11: gate off -> allowed ---
check 0 "CLAUDE_1337_REVIEW_GATE=off: allowed" \
  "$MODE_ORCH CLAUDE_1337_REVIEW_GATE=off" "$(commit_payload "$tr1")"

# --- case 12: missing transcript -> allowed, silent ---
check 0 "missing transcript: allowed, silent" \
  "$MODE_ORCH" "$(commit_payload "$TMPDIR/does-not-exist.jsonl")"

# --- case 13: a Bash command that is not git commit -> never gated ---
no_commit_payload=$(jq -c -n --arg tr "$tr1" '{tool_name:"Bash",tool_input:{command:"git status"},transcript_path:$tr,session_id:"s"}')
check 0 "Bash command other than git commit: never gated" \
  "$MODE_ORCH" "$no_commit_payload"

# --- case 14: no 1337:builder dispatch at all this session -> commit allowed ---
tr14="$TMPDIR/tr14.jsonl"
t_tool "$(scout_line)" "$tr14"
check 0 "no builder dispatch yet: commit allowed, nothing to review" \
  "$MODE_ORCH" "$(commit_payload "$tr14")"

# --- case 15: no prior 1337:builder dispatch -> first dispatch allowed ---
check 0 "dispatch gate: first-ever builder dispatch: allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr14")"

# --- case 16: a subagent-issued call (payload carries agent_id) always passes ---
sub_payload=$(jq -c -n --arg tr "$tr5" '{agent_id:"abc",tool_name:"Agent",tool_input:{subagent_type:"1337:builder",model:"sonnet"},transcript_path:$tr,session_id:"s"}')
check 0 "subagent-issued dispatch (agent_id set): always allowed" \
  "$MODE_ORCH" "$sub_payload"

exit $fail
