#!/usr/bin/env bash
# Tests for tools/replay.sh (#658): runs it over the redacted fixture and
# asserts the exact summary numbers the current hooks/orchestrator-guard.sh
# and hooks/read-cap.sh give for it. No network; stand-alone.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
REPLAY="$ROOT/tools/replay.sh"
FIXTURE="$ROOT/tests/fixtures/replay-sample.jsonl"
fail=0

out=$(bash "$REPLAY" "$FIXTURE" 2>&1)
rc=$?

check() { # description condition (already evaluated, 0/1)
  if [ "$2" -eq 0 ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

[ "$rc" -eq 0 ]; check "exits 0" $?

printf '%s\n' "$out" | grep -q '^line	tool	first	verdict	recorded	next$'
check "TSV header present" $?

printf '%s\n' "$out" | grep -qF 'allowed 10'
check "summary: allowed 10" $?

printf '%s\n' "$out" | grep -qF 'refused 4'
check "summary: refused 4" $?

printf '%s\n' "$out" | grep -qF 'then-refused-now-allowed 2'
check "summary: then-refused-now-allowed 2" $?

printf '%s\n' "$out" | grep -qF 'then-allowed-now-refused 2'
check "summary: then-allowed-now-refused 2" $?

# The sed-i row (a real, still-refused write) stays refused both ways.
printf '%s\n' "$out" | grep -qP '^2\tBash\tsed\trefused\trefused\tEdit$'
check "sed-i row: still refused, matches the recorded refusal" $?

# The two git-commit-heredoc rows: orchestrator-guard.sh's write check passes
# (heredoc is data, not a code file write), and read-cap.sh's fixed bash_is_read
# now correctly recognizes that `| tail -2` and `| head -1` have no file
# operands (no nonflag operands after skipping flags with arguments), so they
# do not count as reads. These rows flip from recorded-refused to now-allowed.
printf '%s\n' "$out" | grep -qP '^10\tBash\tgit\tallowed\trefused\tBash$'
check "first git-commit row: now allowed (pipe filter has no file operand)" $?
printf '%s\n' "$out" | grep -qP '^12\tBash\tgit\tallowed\trefused\tEdit$'
check "second git-commit row: now allowed (pipe filter has no file operand)" $?

# The edit-cap refusal (edit #4 past the default cap of 3) stays refused.
printf '%s\n' "$out" | grep -qP '^14\tEdit\tplugin\.json\trefused\trefused\tBash$'
check "edit-cap row: still refused" $?

# The two rows that DID flip: a first-turn Read and Grep, refused today by
# read-cap.sh's default-0 cap though the fixture recorded them as having
# gone through.
printf '%s\n' "$out" | grep -qP '^19\tRead\torchestrator-guard\.sh\trefused\tallowed\tGrep$'
check "read row flips to refused (default read cap is 0)" $?
printf '%s\n' "$out" | grep -qP '^21\tGrep\t-\trefused\tallowed\tmcp__tasqx__tasqx_annotate_task$'
check "grep row flips to refused (default grep cap is 0)" $?

echo
if [ "$fail" -eq 0 ]; then
  echo "all replay.test.sh checks passed"
else
  echo "$out"
fi
exit $fail
