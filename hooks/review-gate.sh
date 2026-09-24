#!/usr/bin/env bash
# PreToolUse hook for Bash|Agent|Task, active only in orchestrator mode
# (plugin option `orchestrator`, or CLAUDE_1337_ORCHESTRATOR=1 /
# EVAL_CLAUDE_1337_ORCHESTRATOR=1 for eval cases — same three switches
# hooks/route-guard.sh and hooks/read-cap.sh check). Enforces, instead of
# leaving to prose, that the orchestrator actually reads a builder's diff and
# runs `/1337:review` on it before committing or dispatching the next
# builder.
#
# THE RULE, decided from the session transcript (JSONL, at .transcript_path):
# after the last `1337:builder` dispatch, BOTH signals below are required
# before the orchestrator may run `git commit` (COMMIT GATE) or dispatch
# another `1337:builder` (DISPATCH GATE; every other subagent_type always
# passes untouched). Either signal alone is not enough.
#
# THE TWO SIGNALS:
#   - a Bash call actually running `git diff`;
#   - a `/1337:review` invocation, either a Skill tool_use with
#     input.skill == "1337:review", or a user message carrying the literal
#     "<command-name>/1337:review</command-name>" tag the CLI emits for the
#     typed slash command.
#
# THE RETRY EXEMPTION (dispatch gate only): if a 1337:checker dispatch
# appears after the previous builder's dispatch and that checker's result
# opens with the verdict token `FAIL` alone on its first line (the contract
# agents/checker.md documents), the next 1337:builder dispatch is the
# sanctioned retry one tier up and passes even with neither diff nor review
# seen — without this the gate deadlocks the exact path where work is
# already going wrong. An Agent/Task dispatch now runs in the background:
# the checker's synchronous tool_result is only the async launch stub, and
# the real verdict lands later as a separate transcript entry carrying a
# `<task-notification>...<tool-use-id>...</tool-use-id>...<result>...
# </result>...</task-notification>` block. The FAIL check below looks at
# both — the synchronous result and any notification whose tool-use-id
# matches a 1337:checker dispatch — either counts.
#
# SIZE CARVE-OUT: the hook measures the change itself instead of trusting
# what got dispatched — `git diff --numstat HEAD` (covers staged and
# unstaged together) summed added+removed. At or under
# CLAUDE_1337_REVIEW_MIN_LINES (default 20) both refusals are skipped: a
# one-line fix must not need a review pass.
#
# ESCAPES: CLAUDE_1337_REVIEW_GATE=off disables the whole hook. A nested
# call made by a subagent (payload carries agent_id) always passes — the
# main session is the orchestrator here, a subagent is not. A
# missing/unreadable transcript, or not being inside a git repository, fails
# open silently — this step cannot tell "nothing to review" from "cannot
# see the evidence". No 1337:builder dispatch yet this session means
# nothing to review yet, so both gates allow.
#
# Exit 2 + stderr refuses; exit 0 allows.
set -u

. "${0%/*}/lib/mode.sh"
mode_on orchestrator || exit 0

# `off` (any case) disables this hook entirely.
gate_lc=$(printf '%s' "${CLAUDE_1337_REVIEW_GATE:-}" | tr '[:upper:]' '[:lower:]')
[ "$gate_lc" != "off" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"

# A nested call made by a subagent, not the main session, always passes:
# the main session is the orchestrator here, a subagent is not.
agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
[ -n "$agent_id" ] && exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

case "$tool" in
  Bash)
    # Cheap fast path: only a command actually running `git commit`
    # triggers this gate at all; every other Bash call is free of this hook.
    bash_cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    is_commit=$(printf '%s' "$bash_cmd" | jq -Rr 'test("(^|[;&|\\s])git\\s+commit(\\s|$)")' 2>/dev/null) || exit 0
    [ "$is_commit" = "true" ] || exit 0
    gate="commit"
    ;;
  Agent|Task)
    # Cheap fast path: only a 1337:builder dispatch triggers this gate;
    # every other subagent_type is free of it.
    subagent_type=$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0
    [ "$subagent_type" = "1337:builder" ] || exit 0
    gate="dispatch"
    ;;
  *) exit 0 ;;
esac

# Not being in a git repository fails open silently: nothing to gate.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
[ -n "$transcript" ] && [ -f "$transcript" ] && [ -r "$transcript" ] || exit 0

# SIZE CARVE-OUT: measure the change itself. `git diff --numstat HEAD`
# already reflects the full working tree (staged and unstaged) against
# HEAD; non-numeric columns (binary files show `-`) are skipped rather than
# counted.
min_lines="${CLAUDE_1337_REVIEW_MIN_LINES:-20}"
case "$min_lines" in ''|*[!0-9]*) min_lines=20 ;; esac
diff_lines=$(git diff --numstat HEAD -- 2>/dev/null | awk '
  { if ($1 ~ /^[0-9]+$/) sum += $1; if ($2 ~ /^[0-9]+$/) sum += $2 }
  END { print sum + 0 }
')
case "$diff_lines" in ''|*[!0-9]*) diff_lines=0 ;; esac
[ "$diff_lines" -le "$min_lines" ] && exit 0

# The anchor is the last builder dispatch that actually spent the slot:
# hooks/lib/builder-dispatches.jq drops a dispatch a PreToolUse hook
# refused (it never ran, so grepping the raw tool_use text — the old
# approach — kept re-anchoring on refusals and never opened the gate
# again), and keeps pending and self-failed ones.
dispatches_jq="$(dirname "$0")/lib/builder-dispatches.jq"
builder_ln=$(jq -R -s --argjson offset 0 -f "$dispatches_jq" "$transcript" 2>/dev/null \
  | jq -r '(last // empty) | .line // empty' 2>/dev/null) || exit 0

# No 1337:builder dispatch yet this session: nothing to review.
[ -n "$builder_ln" ] || exit 0

# Scan everything after the anchor line once: the diff signal, the review
# invocation (either form), and whether a 1337:checker dispatch after the
# anchor reported FAIL (the retry exemption). Bounded tail, never the whole
# transcript — mirrors hooks/route-guard.sh's streaming idiom.
scan=$(tail -n "+$((builder_ln + 1))" "$transcript" 2>/dev/null | jq -R 'fromjson? // empty' 2>/dev/null | jq -cs '
  def texts_of(c):
    if (c|type) == "array" then ([c[]? | select(.type == "text") | .text] | join("\n"))
    elif (c|type) == "string" then c
    else "" end;
  # A diff read: `git diff` at a command boundary, with zero or more git
  # global options in between (`-C <path>`, `-c <k=v>`, `--no-pager`,
  # `-p`/`--paginate`, `--git-dir`/`--work-tree` with `=` or a space,
  # `--no-optional-locks`). An option value is bare or quoted; \x27 is a
  # single quote, which this single-quoted program cannot hold literally.
  def optarg: "(?:\\x27[^\\x27]*\\x27|\"[^\"]*\"|[^\\s;&|\\x27\"]+)";
  def diff_re:
    "(^|[;&|\\s])git(?:\\s+(?:-[Cc]\\s+" + optarg
    + "|--no-pager|-p|--paginate|--(?:git-dir|work-tree)(?:=|\\s+)" + optarg
    + "|--no-optional-locks))*\\s+diff(\\s|$)";
  # The checker verdict token: the first non-empty line, trimmed, with any
  # leading markdown emphasis stripped (`**FAIL**`, `# FAIL`, `` `FAIL` ``),
  # must start with FAIL for the retry exemption to fire (agents/checker.md).
  # The harness sometimes prepends a `[harness: ...]` note of its own ahead
  # of the subagent text it wraps; any leading non-empty line starting with
  # `[harness:` is skipped before the verdict line is taken.
  def verdict_line(t):
    (t | split("\n") | map(gsub("^[ \t]+|[ \t]+$"; "")) | map(select(length > 0))
       | until((. == []) or ((.[0] // "") | startswith("[harness:") | not); .[1:])
       | (.[0] // ""))
    | gsub("^[*#`_ ]+"; "");
  # A task-notification block (an Agent/Task dispatch that ran in the
  # background): the tool-use-id it reports on and its <result> body, the
  # real verdict when the checkers own tool_result was only the async
  # launch stub.
  def notify_of(t):
    select(t | contains("<task-notification>"))
    | {kind:"notify",
       tool_use_id:((t | capture("<tool-use-id>(?<v>[^<]*)</tool-use-id>") | .v) // ""),
       text:((t | capture("<result>(?<v>[\\s\\S]*?)</result>") | .v) // "")};
  [ .[] |
    if .type == "assistant" then
      ((.message.content? // [])[]? | select(.type == "tool_use")
        | {kind:"use", id:(.id // ""), name:(.name // ""),
           subagent_type:(.input.subagent_type // ""),
           command:(.input.command // ""),
           skill:(.input.skill // "")})
    elif .type == "user" then
      (.message.content?) as $c
      | (texts_of($c)) as $t
      | (
          (if ($c|type) == "array" then
             ($c[]? | select(.type == "tool_result")
               | {kind:"result", tool_use_id:(.tool_use_id // ""), text:texts_of(.content)})
           else empty end),
          {kind:"usertext", text: $t},
          notify_of($t)
        )
    elif .type == "queue-operation" then
      notify_of(.content // "")
    else empty end
  ] as $events
  | ($events | any(.kind == "use" and .name == "Bash"
      and (.command | test(diff_re)))) as $diffed
  | ($events | any(.kind == "use" and .name == "Skill" and .skill == "1337:review")) as $skillreview
  | ($events | any(.kind == "usertext"
      and (.text | contains("<command-name>/1337:review</command-name>")))) as $slashreview
  | ([$events[] | select(.kind == "use" and (.name == "Agent" or .name == "Task")
      and .subagent_type == "1337:checker") | .id]) as $checker_ids
  | ($events | any((.kind == "result" or .kind == "notify")
      and (.tool_use_id as $t | ($checker_ids | index($t)) != null)
      and (verdict_line(.text) | test("^FAIL")))) as $checker_fail
  | {diffed:$diffed, review:($skillreview or $slashreview), checker_fail:$checker_fail}
' 2>/dev/null) || exit 0
[ -n "$scan" ] || exit 0

diffed=$(printf '%s' "$scan" | jq -r '.diffed' 2>/dev/null)
reviewed=$(printf '%s' "$scan" | jq -r '.review' 2>/dev/null)
checker_fail=$(printf '%s' "$scan" | jq -r '.checker_fail' 2>/dev/null)

if [ "$diffed" = "true" ] && [ "$reviewed" = "true" ]; then
  exit 0
fi

if [ "$gate" = "dispatch" ] && [ "$checker_fail" = "true" ]; then
  exit 0
fi

# Name what is actually missing rather than claiming neither signal ran
# when one of the two did.
if [ "$diffed" != "true" ] && [ "$reviewed" != "true" ]; then
  missing='neither `git diff` nor `/1337:review` have run since'
elif [ "$diffed" != "true" ]; then
  missing='`git diff` has not run since'
else
  missing='`/1337:review` has not run since'
fi

# The remedy leads (#717): a caller skimming only the first line still gets
# the fix, not just the diagnosis.
if [ "$gate" = "commit" ]; then
  remedy='blocked (1337 review gate): run `git diff`, then `/1337:review`, before committing.'
  lead="a 1337:builder dispatch finished and $missing."
else
  remedy='blocked (1337 review gate): run `git diff`, then `/1337:review`, before the next builder dispatch.'
  lead="the previous 1337:builder dispatch is unreviewed — $missing, and no 1337:checker failure sanctions this as a retry."
fi
printf '%s\n%s Approve or send the deltas back first. CLAUDE_1337_REVIEW_GATE=off disables.\n' "$remedy" "$lead" >&2
exit 2
