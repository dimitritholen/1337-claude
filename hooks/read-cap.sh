#!/usr/bin/env bash
# PreToolUse hook for Read|Grep|Glob, active only in orchestrator mode (plugin
# option `orchestrator`, or CLAUDE_1337_ORCHESTRATOR=1). Caps how many of each
# the main session may run per user turn: CLAUDE_1337_READ_CAP Reads (default
# 1), CLAUDE_1337_GREP_CAP Grep/Glob calls (default 2). Subagent calls
# (payload carries agent_id) always pass.
#
# Turn key is prompt_id; when the payload omits it (older clients), falls
# back to a cksum of the last user message pulled from transcript_path, the
# way hooks/terse-governor.sh does. Counts are kept in a per-session state
# file, one "<turnkey> <kind>" line per call, appended (never rewritten) so
# concurrent tool calls in the same turn don't race each other away. Appending
# and counting is one critical section, held with an atomic `mkdir` lock: run
# unlocked, parallel calls all append before any of them counts, so each sees
# the full total and every one is refused. The lock holder stamps the lock with
# its start time; a lock older than 5 seconds (or one that never got a stamp)
# is stale and is cleared. After ~1s of waiting the cap is applied unlocked
# rather than stall the session.
#
# Exit 2 + stderr refuses over cap; exit 0 allows. Every failure path exits 0.
#
# EVAL_CLAUDE_1337_ORCHESTRATOR=1 is the switch eval cases use, since `claude plugin
# eval` cases may only set EVAL_* variables.
set -u

[ "${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-false}" = "true" ] || [ "${CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || [ "${EVAL_CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || exit 0
[ "${CLAUDE_1337_READ_CAP:-1}" != "0" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"

agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
[ -n "$agent_id" ] && exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

case "$tool" in
  Read) kind=read; cap="${CLAUDE_1337_READ_CAP:-1}" ;;
  Grep|Glob) kind=grep; cap="${CLAUDE_1337_GREP_CAP:-2}" ;;
  *) exit 0 ;;
esac
# A cap of 0 means "no cap for this kind", matching the message below.
[ "$cap" != "0" ] || exit 0

session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$session_id" ] || exit 0

turn_key=$(printf '%s' "$payload" | jq -r '.prompt_id // empty' 2>/dev/null) || exit 0
if [ -z "$turn_key" ]; then
  transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    last_user=$(jq -rs '
      map(select(.type == "user") | .message.content
        | if type == "string" then .
          else ([.[]? | select(.type == "text") | .text] | join("\n"))
          end)
      | map(select(length > 0))
      | last // empty' "$transcript" 2>/dev/null)
    [ -n "$last_user" ] && turn_key=$(printf '%s' "$last_user" | cksum | awk '{print $1}')
  fi
fi
[ -n "$turn_key" ] || exit 0

state="${TMPDIR:-/tmp}/claude-1337-read-cap-$session_id"
lock="$state.lock"

held=0
spin=0
while [ "$spin" -lt 50 ]; do
  if mkdir "$lock" 2>/dev/null; then
    held=1
    trap 'rm -rf "$lock" 2>/dev/null' EXIT
    printf '%s\n' "${EPOCHSECONDS:-$(date +%s)}" > "$lock/ts" 2>/dev/null
    break
  fi
  spin=$((spin + 1))
  stamp=$(cat "$lock/ts" 2>/dev/null)
  case "$stamp" in
    # No stamp after half a second: a leftover directory, not a live holder.
    ''|*[!0-9]*) [ "$spin" -ge 25 ] && rm -rf "$lock" 2>/dev/null ;;
    # A holder that died mid-section leaves its stamp behind; 5 seconds is far
    # more than the section costs.
    *) [ "$(( ${EPOCHSECONDS:-$(date +%s)} - stamp ))" -ge 5 ] && rm -rf "$lock" 2>/dev/null ;;
  esac
  sleep 0.02
done

printf '%s %s\n' "$turn_key" "$kind" >> "$state" 2>/dev/null || exit 0

count=$(grep -c -F -x "$turn_key $kind" "$state" 2>/dev/null) || exit 0

if [ "$held" = 1 ]; then
  rm -rf "$lock" 2>/dev/null
  trap - EXIT
fi

[ "$count" -le "$cap" ] && exit 0

if [ "$kind" = "read" ]; then
  printf 'blocked (1337 orchestrator mode): Read #%d this turn (cap %d). Dispatch 1337:scout with the question; it reads in its own context. CLAUDE_1337_READ_CAP=0 disables.\n' "$count" "$cap" >&2
else
  printf 'blocked (1337 orchestrator mode): Grep/Glob #%d this turn (cap %d). Dispatch 1337:scout with the question; it reads in its own context. CLAUDE_1337_GREP_CAP=0 disables.\n' "$count" "$cap" >&2
fi
exit 2
