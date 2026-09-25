#!/usr/bin/env bash
# Stop hook: when the session diff grows big, nudge once per session — the agent
# should offer a /1337:review pass before finishing. Never forces a review; the
# user decides. Opt out per environment with CLAUDE_1337_REVIEW_NUDGE=0.
#
# Counts added lines in `git diff HEAD` (staged + unstaged) plus the size of
# untracked files, in the session's cwd. Skips temp dirs and ~/.claude, non-git
# directories, and any Stop where stop_hook_active is true (no loops: the flag
# file is written before the nudge, so a repeated Stop also stays quiet).
#
# Exit 2 + stderr blocks the stop and feeds the nudge to the agent; exit 0 in
# every other path. Failure never blocks a session.
#
# Off switch precedence: an explicit CLAUDE_1337_REVIEW_NUDGE=0 wins, else the
# plugin option `review_nudge` (CLAUDE_PLUGIN_OPTION_REVIEW_NUDGE=false), else
# on by default (hooks/lib/mode.sh's opt_on).
set -u

NUDGE_LINES=30

. "${0%/*}/lib/mode.sh"
opt_on CLAUDE_1337_REVIEW_NUDGE CLAUDE_PLUGIN_OPTION_REVIEW_NUDGE true || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

payload="$(cat)"

active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[ "$active" = "true" ] && exit 0

cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null) || exit 0
[ -n "$cwd" ] || exit 0

case "$cwd" in
  "$HOME"/.claude/*|/tmp/*|/private/tmp/*|/var/folders/*) exit 0 ;;
esac

session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$session_id" ] || session_id="default"

flag="${TMPDIR:-/tmp}/claude-1337-review-nudge-$session_id"
[ -e "$flag" ] && exit 0

git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

added=$(git -C "$cwd" diff HEAD --numstat 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')
while IFS= read -r f; do
  if [ -f "$cwd/$f" ]; then
    n=$(wc -l < "$cwd/$f" 2>/dev/null || printf 0)
    added=$((added + n))
  fi
done < <(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null)

[ "$added" -ge "$NUDGE_LINES" ] || exit 0

: > "$flag" 2>/dev/null || exit 0

printf 'The session diff adds %d lines. Before finishing, offer the user one line: whether they want a /1337:review pass over the diff (it returns a delete-list of over-engineering). Do not run the review unless they ask; after offering, stop.\n' "$added" >&2
exit 2
