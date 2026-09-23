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
bash_line() { # command
  jq -c -n --arg cmd "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:$cmd}}]}}'
}
git_diff_line() {
  jq -c -n '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:"git diff HEAD -- foo.py"}}]}}'
}
git_diff_stat_line() {
  jq -c -n '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:"git diff --stat"}}]}}'
}
# A dispatch that ran and reported success (as hooks/lib/builder-dispatches.jq
# expects it, an array of {type:text} blocks rather than a plain string).
builder_success_result_line() { # tool-use id
  jq -c -n --arg id "$1" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:"Async agent launched successfully."}]}]}}'
}
# A builder dispatch a PreToolUse hook (route-guard) refused before it ever
# ran: hooks/lib/builder-dispatches.jq drops this shape from the anchor.
builder_refused_result_line() { # tool-use id
  jq -c -n --arg id "$1" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,is_error:true,content:"PreToolUse:Agent hook error: [\"/x/hooks/route-guard.sh\"]: blocked (1337 tiered mode): ..."}]}}'
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
# The async launch stub a checker dispatch actually returns synchronously
# now (the real verdict comes later as a task-notification, see below).
checker_launch_stub_line() { # tool-use id
  jq -c -n --arg id "$1" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:"Async agent launched successfully. Task ID: af0. Output file: /tmp/x.output"}]}}'
}
# A synchronous checker tool_result whose content is an array of text
# blocks rather than a plain string.
checker_result_array_line() { # tool-use id, PASS-or-FAIL text
  jq -c -n --arg id "$1" --arg body "$2" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:$body}]}]}}'
}
# The real transcript shape for an async agent's delivered verdict: a
# "user" entry whose message.content is a plain string carrying a
# <task-notification> block naming the tool-use-id it reports on and the
# <result> body.
task_notification_line() { # tool-use id, result body
  jq -c -n --arg id "$1" --arg body "$2" \
    '{type:"user",message:{role:"user",content:("<task-notification>\n<task-id>t1</task-id>\n<tool-use-id>" + $id + "</tool-use-id>\n<status>completed</status>\n<result>" + $body + "</result>\n</task-notification>")}}'
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

# --- case 7e: async launch stub + a later task-notification carrying the
# real FAIL verdict, matching the checker's tool-use-id -> retry allowed ---
tr7e="$TMPDIR/tr7e.jsonl"
t_tool "$(builder_line b1)" "$tr7e"
t_tool "$(builder_result_line b1)" "$tr7e"
t_tool "$(checker_line c1)" "$tr7e"
t_tool "$(checker_launch_stub_line c1)" "$tr7e"
t_tool "$(task_notification_line c1 "FAIL

verdict text")" "$tr7e"
check 0 "dispatch gate: async launch stub + task-notification FAIL: retry allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7e")"

# --- case 7f: same, but the notification reports PASS -> no exemption ---
tr7f="$TMPDIR/tr7f.jsonl"
t_tool "$(builder_line b1)" "$tr7f"
t_tool "$(builder_result_line b1)" "$tr7f"
t_tool "$(checker_line c1)" "$tr7f"
t_tool "$(checker_launch_stub_line c1)" "$tr7f"
t_tool "$(task_notification_line c1 "PASS

nothing wrong")" "$tr7f"
check_grep 2 'unreviewed' "dispatch gate: async launch stub + task-notification PASS: no exemption, still refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7f")"

# --- case 7g: a task-notification for a DIFFERENT tool-use-id reporting
# FAIL must not exempt this checker's stub -> still refused ---
tr7g="$TMPDIR/tr7g.jsonl"
t_tool "$(builder_line b1)" "$tr7g"
t_tool "$(builder_result_line b1)" "$tr7g"
t_tool "$(checker_line c1)" "$tr7g"
t_tool "$(checker_launch_stub_line c1)" "$tr7g"
t_tool "$(task_notification_line other-id "FAIL

unrelated task")" "$tr7g"
check_grep 2 'unreviewed' "dispatch gate: task-notification for a different tool-use-id: no exemption, still refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7g")"

# --- case 7h: a synchronous checker tool_result whose content is an array
# of text blocks (not a plain string) reporting FAIL -> retry allowed ---
tr7h="$TMPDIR/tr7h.jsonl"
t_tool "$(builder_line b1)" "$tr7h"
t_tool "$(builder_result_line b1)" "$tr7h"
t_tool "$(checker_line c1)" "$tr7h"
t_tool "$(checker_result_array_line c1 "FAIL

boom")" "$tr7h"
check 0 "dispatch gate: synchronous checker result as array-of-text-blocks reporting FAIL: retry allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7h")"

# --- case 7i: the verdict token wrapped in markdown emphasis (**FAIL**)
# still fires the exemption ---
tr7i="$TMPDIR/tr7i.jsonl"
t_tool "$(builder_line b1)" "$tr7i"
t_tool "$(builder_result_line b1)" "$tr7i"
t_tool "$(checker_line c1)" "$tr7i"
t_tool "$(checker_result_line c1 "**FAIL**

details")" "$tr7i"
check 0 "dispatch gate: checker result with **FAIL** first line: retry allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7i")"

# --- case 7j: a task-notification whose text has a `[harness: ...]` note
# ahead of the actual verdict -> the FAIL line under it still fires the
# exemption (#720) ---
tr7j="$TMPDIR/tr7j.jsonl"
t_tool "$(builder_line b1)" "$tr7j"
t_tool "$(builder_result_line b1)" "$tr7j"
t_tool "$(checker_line c1)" "$tr7j"
t_tool "$(checker_launch_stub_line c1)" "$tr7j"
t_tool "$(task_notification_line c1 "[harness: subagent output matched instruction-shaped pattern(s): foo]
FAIL

verdict text")" "$tr7j"
check 0 "dispatch gate: task-notification with a [harness: ...] line ahead of FAIL: retry allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr7j")"

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

# --- case 17 (regression): a builder dispatch runs, gets reviewed, then a
# SECOND builder dispatch is refused by route-guard before it ever ran. The
# refusal must not re-anchor past the diff/review evidence already given —
# a NEW builder dispatch after the refusal must still be allowed.
tr17="$TMPDIR/tr17.jsonl"
t_tool "$(builder_line b1)" "$tr17"
t_tool "$(builder_success_result_line b1)" "$tr17"
t_tool "$(git_diff_stat_line)" "$tr17"
t_tool "$(skill_review_line)" "$tr17"
t_tool "$(builder_line b2)" "$tr17"
t_tool "$(builder_refused_result_line b2)" "$tr17"
check 0 "dispatch gate: refused dispatch does not re-anchor past prior evidence: new dispatch allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr17")"

# --- case 18 (control): same shape, but no diff and no review before the
# refused dispatch -> the new dispatch is still refused.
tr18="$TMPDIR/tr18.jsonl"
t_tool "$(builder_line b1)" "$tr18"
t_tool "$(builder_success_result_line b1)" "$tr18"
t_tool "$(builder_line b2)" "$tr18"
t_tool "$(builder_refused_result_line b2)" "$tr18"
check_grep 2 'unreviewed' "dispatch gate: refused dispatch, no prior evidence: still refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr18")"

# --- case 19: git diff with global options: git -C /repo diff --stat ---
tr19="$TMPDIR/tr19.jsonl"
t_tool "$(builder_line b1)" "$tr19"
t_tool "$(builder_result_line b1)" "$tr19"
t_tool "$(bash_line 'git -C /repo diff --stat')" "$tr19"
t_tool "$(skill_review_line)" "$tr19"
check 0 "diff_re: git -C /repo diff --stat: allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr19")"

# --- case 20: git diff with path containing spaces ---
tr20="$TMPDIR/tr20.jsonl"
t_tool "$(builder_line b1)" "$tr20"
t_tool "$(builder_result_line b1)" "$tr20"
t_tool "$(bash_line 'git -C "/a b" diff')" "$tr20"
t_tool "$(skill_review_line)" "$tr20"
check 0 'diff_re: git -C "/a b" diff: allowed' \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr20")"

# --- case 21: git diff with --no-pager ---
tr21="$TMPDIR/tr21.jsonl"
t_tool "$(builder_line b1)" "$tr21"
t_tool "$(builder_result_line b1)" "$tr21"
t_tool "$(bash_line 'git --no-pager diff HEAD')" "$tr21"
t_tool "$(skill_review_line)" "$tr21"
check 0 "diff_re: git --no-pager diff HEAD: allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr21")"

# --- case 22: git diff with -c option ---
tr22="$TMPDIR/tr22.jsonl"
t_tool "$(builder_line b1)" "$tr22"
t_tool "$(builder_result_line b1)" "$tr22"
t_tool "$(bash_line 'git -c core.pager=cat diff')" "$tr22"
t_tool "$(skill_review_line)" "$tr22"
check 0 "diff_re: git -c core.pager=cat diff: allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr22")"

# --- case 23: cd followed by git -C . diff ---
tr23="$TMPDIR/tr23.jsonl"
t_tool "$(builder_line b1)" "$tr23"
t_tool "$(builder_result_line b1)" "$tr23"
t_tool "$(bash_line 'cd /repo && git -C . diff')" "$tr23"
t_tool "$(skill_review_line)" "$tr23"
check 0 "diff_re: cd /repo && git -C . diff: allowed" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr23")"

# --- case 24: git log is not git diff -> refused ---
tr24="$TMPDIR/tr24.jsonl"
t_tool "$(builder_line b1)" "$tr24"
t_tool "$(builder_result_line b1)" "$tr24"
t_tool "$(bash_line 'git log -p')" "$tr24"
t_tool "$(skill_review_line)" "$tr24"
check_grep 2 '`git diff` has not run since' "diff_re: git log -p: not a diff, refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr24")"

# --- case 25: git -C /repo log is not git diff -> refused ---
tr25="$TMPDIR/tr25.jsonl"
t_tool "$(builder_line b1)" "$tr25"
t_tool "$(builder_result_line b1)" "$tr25"
t_tool "$(bash_line 'git -C /repo log')" "$tr25"
t_tool "$(skill_review_line)" "$tr25"
check_grep 2 '`git diff` has not run since' "diff_re: git -C /repo log: not a diff, refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr25")"

# --- case 26: git difftool is not git diff -> refused ---
tr26="$TMPDIR/tr26.jsonl"
t_tool "$(builder_line b1)" "$tr26"
t_tool "$(builder_result_line b1)" "$tr26"
t_tool "$(bash_line 'git difftool')" "$tr26"
t_tool "$(skill_review_line)" "$tr26"
check_grep 2 '`git diff` has not run since' "diff_re: git difftool: not a diff, refused" \
  "$MODE_ORCH" "$(dispatch_payload 1337:builder "$tr26")"

exit $fail
