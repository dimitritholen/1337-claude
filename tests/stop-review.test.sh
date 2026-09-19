#!/usr/bin/env bash
# Tests for hooks/stop-review.sh: feeds crafted Stop payloads against fixture
# git repos and asserts the exit code. Exit 2 = nudge fired, exit 0 = quiet.
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/stop-review.sh"
fail=0
work="$(mktemp -d)"
# The hook ignores temp paths by design, so the fixture repo must live elsewhere.
repo="$HOME/1337-stop-review-test-$$"
sid="test-$$"
trap 'rm -rf "$work" "$repo"; rm -f "${TMPDIR:-/tmp}"/claude-1337-review-nudge-"$sid"*' EXIT

check() { # expected-exit description payload
  local got
  printf '%s' "$3" | "$HOOK" 2>/dev/null
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'ok   %s\n' "$2"; else printf 'FAIL %s (exit %s, want %s)\n' "$2" "$got" "$1"; fail=1; fi
}

# Fixture repo: one commit with a.txt, then a quiet session (1-line diff).
git init -q "$repo"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf 'hello\n' > "$repo/a.txt"
git -C "$repo" add a.txt
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m a

payload() { # sid cwd extra
  printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false%s}' "$1" "$2" "${3:-}"
}

unset CLAUDE_1337_REVIEW_NUDGE

check 0 "small diff: quiet" "$(payload "$sid-quiet" "$repo")"

# Big tracked diff fires the nudge, exactly once per session.
sid_big="$sid-big"
seq 1 40 > "$repo/a.txt"
out="$(mktemp)"; payload="$(payload "$sid_big" "$repo")"
printf '%s' "$payload" | "$HOOK" 2>"$out"
got=$?
if [ "$got" -eq 2 ] && grep -q '1337:review' "$out"; then
  printf 'ok   big diff: nudge fires with pointer to /1337:review\n'
else
  printf 'FAIL big diff: nudge (exit %s)\n' "$got"; fail=1
fi
check 0 "second stop, same session: quiet" "$payload"
rm -f "$out"

# A 40-line untracked file counts too.
sid_new="$sid-new"
git -C "$repo" checkout -q -- a.txt
seq 1 40 > "$repo/new.py"
check 2 "untracked file of 40 lines: nudge fires" "$(payload "$sid_new" "$repo")"
rm -f "$repo/new.py"

# stop_hook_active never re-blocks (loop guard), even with a fresh flag.
sid_loop="$sid-loop"
seq 1 40 > "$repo/a.txt"
check 0 "stop_hook_active=true: quiet" \
  "{\"session_id\":\"$sid_loop\",\"cwd\":\"$repo\",\"stop_hook_active\":true}"

# Opt-out env var.
sid_env="$sid-env"
CLAUDE_1337_REVIEW_NUDGE=0 check 0 "CLAUDE_1337_REVIEW_NUDGE=0: quiet" "$(payload "$sid_env" "$repo")"

# Outside any git repo (and under a temp path) it stays quiet.
check 0 "non-git temp dir: quiet" "$(payload "$sid-tmp" "$work")"

exit $fail
