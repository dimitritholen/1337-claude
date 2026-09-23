#!/usr/bin/env bash
# Stop hook: the verbosity governor. Measures the last assistant reply in the
# transcript; if it exceeds the mode's word budget and the user did not ask for
# an explanation, blocks the stop so the agent resends the answer only. Code
# fences do not count. Enforces, where an output style only instructs.
#
# Mode (highest first): CLAUDE_1337_TERSE env (0/off/on/hard), then the mode
# file (default $HOME/.claude/.1337-terse, set by /1337:terse), then "on".
# Budgets: on = 40 words, hard = 12, off = no check.
#
# stop_hook_active=true never blocks again, so the resend happens once.
# Exit 2 + stderr blocks; every failure path exits 0 and never blocks a session.
set -u

command -v jq >/dev/null 2>&1 || exit 0

env_mode="${CLAUDE_1337_TERSE:-}"
if [ -n "$env_mode" ]; then
  mode="$env_mode"
else
  mode_file="${CLAUDE_1337_TERSE_FILE:-$HOME/.claude/.1337-terse}"
  mode=$(cat "$mode_file" 2>/dev/null || printf 'on')
fi
mode=$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')
[ "$mode" = "0" ] && mode="off"
# A truncated or empty mode file means the default, never a silent off.
[ -n "$mode" ] || mode="on"

case "$mode" in
  on) budget=40 ;;
  hard) budget=12 ;;
  off) exit 0 ;;
  *) exit 0 ;;
esac

payload="$(cat)"

active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[ "$active" = "true" ] && exit 0

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

text_of() { # jq type filter over a JSONL transcript -> last non-empty text
  jq -rs --arg t "$1" '
    map(select(.type == $t) | .message.content
      | if type == "string" then .
        else ([.[]? | select(.type == "text") | .text] | join("\n"))
        end)
    | map(select(length > 0))
    | last // empty' "$2" 2>/dev/null
}

last_user=$(text_of user "$transcript")
[ -n "$last_user" ] || exit 0

# The user asked for an explanation: no budget this turn.
if printf '%s' "$last_user" | grep -iqE '(^|[^a-z])(why|how|explain|tell me|because|reason|difference|trade.?offs?|what (is|are|does)|review|recommend(ation)?s?|list|summari[sz]e|summary|compar(e|ison)|options|what should)([^a-z]|$)'; then
  exit 0
fi

last_reply=$(text_of assistant "$transcript")
[ -n "$last_reply" ] || exit 0

# Words outside code fences.
words=$(printf '%s\n' "$last_reply" | awk '
  /^```/ { fenced = !fenced; next }
  !fenced { print }
' | wc -w)

[ "$words" -le "$budget" ] && exit 0

if [ "$mode" = "hard" ]; then
  printf 'Reply was %d words (budget %d). Resend it as one line: the answer, nothing else.\n' "$words" "$budget" >&2
else
  printf 'Reply was %d words (budget %d). Resend the answer only: the result, `path:line` where it matters, nothing else. Do not narrate tool calls.\n' "$words" "$budget" >&2
fi
exit 2
