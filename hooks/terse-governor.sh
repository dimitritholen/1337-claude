#!/usr/bin/env bash
# Stop hook (default) / UserPromptSubmit nudge (--nudge): the verbosity
# governor. Enforces, where an output style only instructs.
#
# Stop mode measures the last assistant reply in the transcript. An
# over-budget reply is never blocked any more -- the tokens are already
# spent, so a forced resend only adds output tokens. Instead it writes a
# per-session marker (the counted words and budget) and exits 0 silently.
# Code fences do not count; why/how/explain-style prompts lift the budget
# for that turn.
#
# --nudge mode (UserPromptSubmit) reads that marker for the session, if
# any: prints one line of context reminding the model of the budget, then
# deletes the marker. No marker, or terse mode off, means silence (and off
# also clears a stale marker).
#
# Marker: ${TMPDIR:-/tmp}/claude-1337-terse-overrun-<session_id>, holding
# "<words> <budget>". Every failure path exits 0 and never blocks a session.
set -u

command -v jq >/dev/null 2>&1 || exit 0

. "${0%/*}/lib/terse-mode.sh"

payload="$(cat)"

session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
session_id=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_-')
[ -n "$session_id" ] || session_id="default"
marker="${TMPDIR:-/tmp}/claude-1337-terse-overrun-$session_id"

if [ "${1:-}" = "--nudge" ]; then
  mode=$(terse_mode)
  if [ "$mode" = "off" ] || [ ! -e "$marker" ]; then
    rm -f "$marker" 2>/dev/null
    exit 0
  fi
  read -r words budget < "$marker" 2>/dev/null
  rm -f "$marker" 2>/dev/null
  [ -n "${words:-}" ] && [ -n "${budget:-}" ] || exit 0
  printf 'Terse: your last reply was %s words (budget %s). Keep this one within budget.\n' "$words" "$budget"
  exit 0
fi

mode=$(terse_mode)

case "$mode" in
  on) budget=40 ;;
  hard) budget=12 ;;
  off) exit 0 ;;
  *) exit 0 ;;
esac

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

# Exempt an ordered list of steps (order matters) and security/irreversible
# wording, per hooks/terse.md's exemptions block: write normally there.
list_steps=$(printf '%s\n' "$last_reply" | grep -cE '^[[:space:]]*[0-9]+\.[[:space:]]')
[ "$list_steps" -ge 2 ] && exit 0

if printf '%s' "$last_reply" | grep -iqE '(security|vulnerab|irreversible|cannot be undone|destructive|data loss)'; then
  exit 0
fi

# Words outside code fences.
words=$(printf '%s\n' "$last_reply" | awk '
  /^```/ { fenced = !fenced; next }
  !fenced { print }
' | wc -w)

[ "$words" -le "$budget" ] && exit 0

printf '%s %s\n' "$words" "$budget" > "$marker" 2>/dev/null
exit 0
