#!/usr/bin/env bash
# Tests for hooks/read-cap.sh: feeds crafted PreToolUse payloads and asserts
# the exit code. Exit 2 = refused, exit 0 = allowed.
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/read-cap.sh"
fail=0
ok_count=0
fail_count=0
todo_count=0

STATEDIR="$(mktemp -d)"
export TMPDIR="$STATEDIR"
trap 'rm -rf "$STATEDIR"' EXIT

sid="test-$$"

check() { # expected-exit description payload
  local got out
  out=$(printf '%s' "$3" | "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'ok   %s\n' "$2"; ok_count=$((ok_count + 1)); else printf 'FAIL %s (exit %s, want %s)\n' "$2" "$got" "$1"; fail=1; fail_count=$((fail_count + 1)); fi
  # Trailing newline so any stderr this call produced (e.g. a check() used
  # on a refusal, which does carry a message) never glues onto the next
  # helper's "ok "/"FAIL " line — that would hide it from tests/run-all.sh's
  # line-prefix counting.
  [ -n "$out" ] && printf '%s\n' "$out"
}

check_grep() { # expected-exit want-in-stderr description payload
  local out
  out=$(printf '%s' "$4" | "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$1" ] && printf '%s' "$out" | grep -q "$2"; then
    printf 'ok   %s\n' "$3"; ok_count=$((ok_count + 1))
  else
    printf 'FAIL %s (exit %s, want %s; stderr: %s)\n' "$3" "$got" "$1" "$out"; fail=1; fail_count=$((fail_count + 1))
  fi
}

check_notgrep() { # expected-exit not-in-stderr description payload
  local out
  out=$(printf '%s' "$4" | "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$1" ] && ! printf '%s' "$out" | grep -q "$2"; then
    printf 'ok   %s\n' "$3"; ok_count=$((ok_count + 1))
  else
    printf 'FAIL %s (exit %s, want %s; stderr: %s)\n' "$3" "$got" "$1" "$out"; fail=1; fail_count=$((fail_count + 1))
  fi
}

readcall() { # session prompt_id extra
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"Read","tool_input":{"file_path":"/repo/a.py"}%s}' "$1" "$2" "${3:-}"
}
readcall_path() { # session prompt_id file_path extra
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"Read","tool_input":{"file_path":"%s"}%s}' "$1" "$2" "$3" "${4:-}"
}
grepcall() { # session prompt_id tool extra
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"%s","tool_input":{"pattern":"x"}%s}' "$1" "$2" "$3" "${4:-}"
}
bashcall() { # session prompt_id command extra
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"}%s}' "$1" "$2" "$3" "${4:-}"
}
mcpcall() { # session prompt_id
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"mcp__codebase-memory-mcp__get_code_snippet","tool_input":{}}' "$1" "$2"
}
editcall() { # session prompt_id
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/repo/a.py"}}' "$1" "$2"
}
readcall_transcript() { # session transcript_path
  printf '{"session_id":"%s","tool_name":"Read","tool_input":{"file_path":"/repo/a.py"},"transcript_path":"%s"}' "$1" "$2"
}

# a. mode off: Read passes.
unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR CLAUDE_1337_ORCHESTRATOR CLAUDE_1337_READ_CAP CLAUDE_1337_GREP_CAP
check 0 "mode off: read allowed" "$(readcall "$sid" p1)"

export CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=true

# b. default cap (unset -> 0): the main session reads nothing by default,
# so the very first Read of a turn is already refused.
unset CLAUDE_1337_READ_CAP CLAUDE_1337_GREP_CAP
check_grep 2 'Read #1' "default cap 0: first read in p0 refused" "$(readcall "$sid" p0)"

# c/d. CLAUDE_1337_READ_CAP=1: first read in p1 passes, second refused.
CLAUDE_1337_READ_CAP=1 check 0 "READ_CAP=1: first read in p1" "$(readcall "$sid" p1)"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "READ_CAP=1: second read in p1 refused" "$(readcall "$sid" p1)"

# e. Grep, Glob in p2 pass under GREP_CAP=2; third (Grep) refused.
CLAUDE_1337_GREP_CAP=2 check 0 "GREP_CAP=2: p2: first grep allowed" "$(grepcall "$sid" p2 Grep)"
CLAUDE_1337_GREP_CAP=2 check 0 "GREP_CAP=2: p2: first glob allowed (second grep-kind call)" "$(grepcall "$sid" p2 Glob)"
CLAUDE_1337_GREP_CAP=2 check_grep 2 'Grep/Glob #3' "GREP_CAP=2: p2: third grep-kind call refused" "$(grepcall "$sid" p2 Grep)"

# f. Read in p2 with agent_id after cap reached: always allowed.
check 0 "p2: subagent read bypasses cap" "$(readcall "$sid" p2 ',"agent_id":"abc"')"

# g. CLAUDE_1337_READ_CAP=0 (the default) refuses every read, it does not disable.
CLAUDE_1337_READ_CAP=0 check_grep 2 'Read #1' "READ_CAP=0: first read in p7 refused" "$(readcall "$sid" p7)"

# g2. CLAUDE_1337_READ_CAP=off disables the cap entirely: three reads in p1 all pass.
CLAUDE_1337_READ_CAP=off check 0 "READ_CAP=off: read in p1 allowed" "$(readcall "$sid" p1)"
CLAUDE_1337_READ_CAP=OFF check 0 "READ_CAP=OFF (case-insensitive): read in p1 allowed" "$(readcall "$sid" p1)"

# g-grep. CLAUDE_1337_GREP_CAP=off disables Grep/Glob cap: three grep-kind calls in fresh prompt p4 all pass.
CLAUDE_1337_GREP_CAP=off check 0 "GREP_CAP=off: first grep in p4 allowed" "$(grepcall "$sid" p4 Grep)"
CLAUDE_1337_GREP_CAP=off check 0 "GREP_CAP=off: second grep in p4 allowed" "$(grepcall "$sid" p4 Grep)"
CLAUDE_1337_GREP_CAP=off check 0 "GREP_CAP=off: third grep in p4 allowed" "$(grepcall "$sid" p4 Grep)"

# h. CLAUDE_1337_READ_CAP=3: reads 2 and 3 in fresh prompt p3 pass, fourth refused.
CLAUDE_1337_READ_CAP=3 check 0 "READ_CAP=3: read 1 in p3" "$(readcall "$sid" p3)"
CLAUDE_1337_READ_CAP=3 check 0 "READ_CAP=3: read 2 in p3" "$(readcall "$sid" p3)"
CLAUDE_1337_READ_CAP=3 check 0 "READ_CAP=3: read 3 in p3" "$(readcall "$sid" p3)"
CLAUDE_1337_READ_CAP=3 check_grep 2 'Read #4' "READ_CAP=3: read 4 in p3 refused" "$(readcall "$sid" p3)"

# i. no prompt_id, fallback to transcript's last user message.
transcript="$STATEDIR/transcript-$sid.jsonl"
printf '{"type":"user","message":{"content":"hello there"}}\n' > "$transcript"
sid_t="$sid-transcript"
read_noprompt=$(printf '{"session_id":"%s","tool_name":"Read","tool_input":{"file_path":"/repo/a.py"},"transcript_path":"%s"}' "$sid_t" "$transcript")
CLAUDE_1337_READ_CAP=1 check 0 "no prompt_id: first read via transcript fallback" "$read_noprompt"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "no prompt_id: second read via transcript fallback refused" "$read_noprompt"

# j. six parallel Reads in a fresh prompt with cap 1: exactly one allowed.
exits="$STATEDIR/exits-p5"
: > "$exits"
for _ in 1 2 3 4 5 6; do
  (
    printf '%s' "$(readcall "$sid" p5)" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1
    printf 'exit=%s\n' "$?" >> "$exits"
  ) &
done
wait
allowed=$(grep -c -F -x 'exit=0' "$exits")
refused=$(grep -c -F -x 'exit=2' "$exits")
if [ "$allowed" -eq 1 ] && [ "$refused" -eq 5 ]; then
  printf 'ok   parallel: one read allowed, five refused\n'; ok_count=$((ok_count + 1))
else
  printf 'FAIL parallel: %s allowed, %s refused (want 1 and 5; exits: %s)\n' "$allowed" "$refused" "$(tr '\n' ' ' < "$exits")"; fail=1; fail_count=$((fail_count + 1))
fi

# k. a stale lock left behind does not block the next Read.
sid_lock="$sid-stalelock"
stale_lock="$STATEDIR/claude-1337-read-cap-$sid_lock.lock"
mkdir "$stale_lock"
touch -d '-10 seconds' "$stale_lock"
CLAUDE_1337_READ_CAP=1 check 0 "stale lock: first read in fresh prompt allowed" "$(readcall "$sid_lock" p1)"

# l. Edit tool_name passes through untouched.
edit_payload=$(printf '{"session_id":"%s","prompt_id":"p1","tool_name":"Edit","tool_input":{"file_path":"/repo/a.py"}}' "$sid")
check 0 "Edit tool_name not counted" "$edit_payload"

# m. eval switch turns mode on: EVAL_CLAUDE_1337_ORCHESTRATOR=1 alone, no other knob set.
unset CLAUDE_1337_READ_CAP CLAUDE_1337_GREP_CAP
unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR
export EVAL_CLAUDE_1337_ORCHESTRATOR=1
CLAUDE_1337_READ_CAP=1 check 0 "eval switch: first read in p6" "$(readcall "$sid" p6)"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "eval switch: second read in p6 refused" "$(readcall "$sid" p6)"
unset EVAL_CLAUDE_1337_ORCHESTRATOR

export CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=true

# n. a path under the scratchpad/temp dir is exempt even at cap 0: three
# reads of it in the same turn all pass, uncounted.
CLAUDE_1337_READ_CAP=0 check 0 "scratch path: read 1 in p8 allowed" "$(readcall_path "$sid" p8 "$STATEDIR/scratch.txt")"
CLAUDE_1337_READ_CAP=0 check 0 "scratch path: read 2 in p8 allowed" "$(readcall_path "$sid" p8 "$STATEDIR/scratch.txt")"
CLAUDE_1337_READ_CAP=0 check 0 "scratch path: read 3 in p8 allowed" "$(readcall_path "$sid" p8 "$STATEDIR/scratch.txt")"

# o. a path under $HOME/.claude is exempt at cap 0.
CLAUDE_1337_READ_CAP=0 check 0 "\$HOME/.claude path exempt" "$(readcall_path "$sid" p9 "$HOME/.claude/notes.md")"

# p. same turn, a repo path at cap 0 is refused (not exempt).
CLAUDE_1337_READ_CAP=0 check_grep 2 'Read #1' "repo path at cap 0 refused" "$(readcall_path "$sid" p10 /repo/a.py)"

# q. the refusal names 1337:scout, and ripwire when it is on PATH.
CLAUDE_1337_GREP_CAP=0 check_grep 2 '1337:scout' "cap 0: message names 1337:scout" "$(grepcall "$sid" p11 Grep)"
if command -v ripwire >/dev/null 2>&1; then
  CLAUDE_1337_GREP_CAP=0 check_grep 2 'ripwire' "cap 0: message names ripwire when it is on PATH" "$(grepcall "$sid" p12 Grep)"
fi

# r. with ripwire missing from PATH, the message drops the ripwire half and
# names only the 1337:scout dispatch.
NOPWIRE_DIR="$STATEDIR/nopath"
mkdir -p "$NOPWIRE_DIR"
for bin in $(command -v jq env cat grep awk printf mkdir rm touch date sleep tr cksum bash sh true false); do
  ln -sf "$(command -v "$(basename "$bin")")" "$NOPWIRE_DIR/$(basename "$bin")" 2>/dev/null
done
out=$(printf '%s' "$(grepcall "$sid" p13 Grep)" | CLAUDE_1337_GREP_CAP=0 PATH="$NOPWIRE_DIR" "$HOOK" 2>&1 >/dev/null)
got=$?
if [ "$got" -eq 2 ] && printf '%s' "$out" | grep -q '1337:scout' && ! printf '%s' "$out" | grep -q 'ripwire'; then
  printf 'ok   ripwire missing from PATH: message names only 1337:scout\n'; ok_count=$((ok_count + 1))
else
  printf 'FAIL ripwire missing from PATH: message names only 1337:scout (exit %s; stderr: %s)\n' "$got" "$out"; fail=1; fail_count=$((fail_count + 1))
fi

# s-v. subagent nudge: a subagent's first Grep/Glob is refused once, naming
# ripwire, then later calls from that agent pass; a different agent_id is
# nudged independently; Read from a subagent is never nudged; and with
# ripwire missing from PATH there is no nudge at all.
if command -v ripwire >/dev/null 2>&1; then
  CLAUDE_1337_GREP_CAP=off check_grep 2 'ripwire' "subagent nudge: first grep from agent ag1 refused" "$(grepcall "$sid" p14 Grep ',"agent_id":"ag1"')"
  CLAUDE_1337_GREP_CAP=off check 0 "subagent nudge: second grep from agent ag1 allowed" "$(grepcall "$sid" p14 Grep ',"agent_id":"ag1"')"
  CLAUDE_1337_GREP_CAP=off check_grep 2 'ripwire' "subagent nudge: different agent (ag2) nudged independently" "$(grepcall "$sid" p14 Glob ',"agent_id":"ag2"')"
else
  printf 'ok   subagent nudge tests skipped: ripwire not on PATH\n'; ok_count=$((ok_count + 1))
fi

CLAUDE_1337_READ_CAP=off check 0 "subagent nudge: Read from a subagent never nudged" "$(readcall "$sid" p14 ',"agent_id":"ag3"')"

out=$(printf '%s' "$(grepcall "$sid" p14 Grep ',"agent_id":"ag4"')" | CLAUDE_1337_GREP_CAP=off PATH="$NOPWIRE_DIR" "$HOOK" 2>&1 >/dev/null)
got=$?
if [ "$got" -eq 0 ]; then
  printf 'ok   subagent nudge: no nudge when ripwire absent from PATH\n'; ok_count=$((ok_count + 1))
else
  printf 'FAIL subagent nudge: no nudge when ripwire absent from PATH (exit %s; stderr: %s)\n' "$got" "$out"; fail=1; fail_count=$((fail_count + 1))
fi

# --- gap cases (tasqx #657/#660), now live checks.

# 25. READ_CAP=0 must not disable the Grep cap: with GREP_CAP=2 a third
# Grep/Glob in one turn is still refused.
printf '%s' "$(grepcall "$sid" p25 Grep)" | CLAUDE_1337_READ_CAP=0 CLAUDE_1337_GREP_CAP=2 "$HOOK" >/dev/null 2>&1
printf '%s' "$(grepcall "$sid" p25 Glob)" | CLAUDE_1337_READ_CAP=0 CLAUDE_1337_GREP_CAP=2 "$HOOK" >/dev/null 2>&1
CLAUDE_1337_READ_CAP=0 CLAUDE_1337_GREP_CAP=2 check_grep 2 'Grep/Glob #3' "gap 25: READ_CAP=0 does not disable the Grep cap, third grep-kind call refused" "$(grepcall "$sid" p25 Grep)"

# 26. a Bash call whose command reads a file (cat/rg/git show) counts as a
# read against READ_CAP: with READ_CAP=1 the second such call is refused.
printf '%s' "$(bashcall "$sid" p26 'cat src/lib.rs')" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1
CLAUDE_1337_READ_CAP=1 check 2 "gap 26: second Bash read (rg TODO src) refused under READ_CAP=1" "$(bashcall "$sid" p26 'rg TODO src')"
printf '%s' "$(bashcall "$sid" p26 'git show HEAD:src/lib.rs')" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1

# 27. an mcp__codebase-memory-mcp__get_code_snippet call counts as a read
# against READ_CAP.
printf '%s' "$(mcpcall "$sid" p27)" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1
CLAUDE_1337_READ_CAP=1 check 2 "gap 27: second mcp__codebase-memory-mcp__get_code_snippet call refused under READ_CAP=1" "$(mcpcall "$sid" p27)"

# 28. two consecutive user turns with identical transcript text get distinct
# turn keys: a read in the second turn is not charged to the first. Every
# user entry carries a distinct uuid, so the key comes from uuid.
sid28="$sid-gap28"
transcript28="$STATEDIR/transcript-gap28.jsonl"
printf '{"uuid":"gap28-u1","isSidechain":false,"type":"user","message":{"role":"user","content":"hello there"}}\n' > "$transcript28"
printf '%s' "$(readcall_transcript "$sid28" "$transcript28")" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1
printf '{"uuid":"gap28-a1","type":"assistant","message":{"role":"assistant","content":"ok"}}\n' >> "$transcript28"
printf '{"uuid":"gap28-u2","isSidechain":false,"type":"user","message":{"role":"user","content":"hello there"}}\n' >> "$transcript28"
CLAUDE_1337_READ_CAP=1 check 0 "gap 28: identical text in a second turn gets its own turn key, first read of it not charged to the first turn" "$(readcall_transcript "$sid28" "$transcript28")"

# 28-fallback. Same identical-text scenario but with NO uuid fields anywhere
# in the transcript: this documents the cksum fallback's known limitation
# (it collides on identical text), not the wanted behaviour — the second
# turn's read is still charged to the first.
sid28f="$sid-gap28-fallback"
transcript28f="$STATEDIR/transcript-gap28-fallback.jsonl"
printf '{"type":"user","message":{"content":"hello there"}}\n' > "$transcript28f"
printf '%s' "$(readcall_transcript "$sid28f" "$transcript28f")" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1
printf '{"type":"assistant","message":{"content":"ok"}}\n' >> "$transcript28f"
printf '{"type":"user","message":{"content":"hello there"}}\n' >> "$transcript28f"
CLAUDE_1337_READ_CAP=1 check 2 "gap 28 (cksum fallback, documents current limitation): identical text with no uuid collides across turns" "$(readcall_transcript "$sid28f" "$transcript28f")"

# 29. a sidechain user entry (isSidechain:true) as the transcript's last
# entry is ignored when deriving the turn key: a read within the same real
# turn, made after a sidechain entry lands at the end of the transcript,
# is still charged to that turn. Every user entry carries a uuid.
sid29="$sid-gap29"
transcript29="$STATEDIR/transcript-gap29.jsonl"
printf '{"uuid":"gap29-u1","isSidechain":false,"type":"user","message":{"role":"user","content":"real turn text"}}\n' > "$transcript29"
printf '%s' "$(readcall_transcript "$sid29" "$transcript29")" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1
printf '{"uuid":"gap29-u2","isSidechain":true,"type":"user","message":{"role":"user","content":"side note text"}}\n' >> "$transcript29"
CLAUDE_1337_READ_CAP=1 check 2 "gap 29: a trailing sidechain entry does not change the turn key, second read of the same turn refused" "$(readcall_transcript "$sid29" "$transcript29")"

# 30. stale state from a previous session_id does not count against a new
# session_id.
sidA30="$sid-gap30A"
sidB30="$sid-gap30B"
printf '%s' "$(readcall "$sidA30" p30)" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1
CLAUDE_1337_READ_CAP=1 check 0 "gap 30: stale state from a previous session_id does not count against a new session_id" "$(readcall "$sidB30" p30)"

# 31. a lock dir with an empty ts file counts as live: the hook waits it out
# (treats it as stale only after its own spin threshold) rather than
# stealing it immediately; the call that follows still succeeds.
sidL31="$sid-gap31"
lockdir31="$STATEDIR/claude-1337-read-cap-$sidL31.lock"
mkdir -p "$lockdir31"
: > "$lockdir31/ts"
CLAUDE_1337_READ_CAP=1 check 0 "gap 31: a lock dir with an empty ts file counts as live, the call waits it out and still succeeds" "$(readcall "$sidL31" p31)"

# 32/33. Read, then a small Edit, then Read: with READ_CAP=1 the Edit itself
# is allowed (33) and does not reset the count, so the second Read is still
# refused (32).
sid3233="$sid-gap3233"
printf '%s' "$(readcall "$sid3233" p32)" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1
CLAUDE_1337_READ_CAP=1 check 0 "gap 33: an Edit between two Reads is itself allowed" "$(editcall "$sid3233" p32)"
CLAUDE_1337_READ_CAP=1 check 2 "gap 32: the second Read after an intervening Edit is still refused under READ_CAP=1" "$(readcall "$sid3233" p32)"

# --- new cases (#662): mcp search_graph, Bash pipe-filter
# exclusion, subagent Bash bypass, state-file truncation on turn change,
# and Bash reads following the read kind under GREP_CAP=off. WebFetch is
# never counted or refused.

webfetchcall() { # session prompt_id extra
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"WebFetch","tool_input":{"url":"https://example.com"}%s}' "$1" "$2" "${3:-}"
}
mcpcall_named() { # session prompt_id tool
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"%s","tool_input":{}}' "$1" "$2" "$3"
}

# WebFetch does not count against READ_CAP: all WebFetch calls pass, and do not
# consume the budget. A Read after two WebFetch calls is still the first read.
CLAUDE_1337_READ_CAP=1 check 0 "WebFetch: first fetch in p34 allowed" "$(webfetchcall "$sid" p34)"
CLAUDE_1337_READ_CAP=1 check 0 "WebFetch: second fetch in p34 allowed (does not count)" "$(webfetchcall "$sid" p34)"
CLAUDE_1337_READ_CAP=1 check 0 "WebFetch: a Read after two WebFetch calls is the 1st read" "$(readcall "$sid" p34)"

# A pure stdin-filter Bash pipeline never counts, no matter how many run.
CLAUDE_1337_READ_CAP=1 check 0 "Bash pipe-filter: ps aux | grep x (1st) allowed" "$(bashcall "$sid" p35 'ps aux | grep x')"
CLAUDE_1337_READ_CAP=1 check 0 "Bash pipe-filter: git log | grep fix (2nd) allowed" "$(bashcall "$sid" p35 'git log | grep fix')"
CLAUDE_1337_READ_CAP=1 check 0 "Bash pipe-filter: ps aux | grep x (3rd) allowed" "$(bashcall "$sid" p35 'ps aux | grep x')"

# A subagent Bash call (agent_id set) passes untouched, cat included.
CLAUDE_1337_READ_CAP=0 check 0 "subagent Bash: cat src/lib.rs from agent_id bypasses the cap" "$(bashcall "$sid" p36 'cat src/lib.rs' ',"agent_id":"sub1"')"

# `git show <rev>` (and `--stat` etc, no colon operand) is metadata, same as
# `git diff`, and never counts: three in one turn all pass.
CLAUDE_1337_READ_CAP=1 check 0 "git show HEAD --stat (1st) allowed" "$(bashcall "$sid" p36b 'git show HEAD --stat')"
CLAUDE_1337_READ_CAP=1 check 0 "git show HEAD --stat (2nd) allowed" "$(bashcall "$sid" p36b 'git show HEAD --stat')"
CLAUDE_1337_READ_CAP=1 check 0 "git show HEAD --stat (3rd) allowed" "$(bashcall "$sid" p36b 'git show HEAD --stat')"

# `git show <rev>:<path>` dumps a file's contents and counts: it fills the
# cap, so the next read this turn is refused.
CLAUDE_1337_READ_CAP=1 check 0 "git show HEAD:src/lib.rs allowed (1st read this turn)" "$(bashcall "$sid" p36c 'git show HEAD:src/lib.rs')"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "git show HEAD:src/lib.rs fills the cap, next read refused" "$(readcall "$sid" p36c)"

# A git global option in front does not hide the subcommand
# (hooks/lib/git-subcommand.sh): each reader still counts and fills the cap.
CLAUDE_1337_READ_CAP=1 check 0 "git -C /repo show HEAD:secret.py allowed (1st read this turn)" "$(bashcall "$sid" p36d 'git -C /repo show HEAD:secret.py')"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "git -C /repo show HEAD:secret.py fills the cap, next read refused" "$(readcall "$sid" p36d)"
CLAUDE_1337_READ_CAP=1 check 0 "git --no-pager grep foo allowed (1st read this turn)" "$(bashcall "$sid" p36e 'git --no-pager grep foo')"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "git --no-pager grep foo fills the cap, next read refused" "$(readcall "$sid" p36e)"
CLAUDE_1337_READ_CAP=1 check 0 "git -C . cat-file -p X allowed (1st read this turn)" "$(bashcall "$sid" p36f 'git -C . cat-file -p X')"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "git -C . cat-file -p X fills the cap, next read refused" "$(readcall "$sid" p36f)"
CLAUDE_1337_READ_CAP=1 check 0 "git -C '/my repo' show HEAD:a.py allowed (1st read this turn)" "$(bashcall "$sid" p36g "git -C '/my repo' show HEAD:a.py")"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "git -C with a quoted path fills the cap, next read refused" "$(readcall "$sid" p36g)"
# An unknown option where a global option goes counts as a possible read.
CLAUDE_1337_READ_CAP=1 check 0 "git --frobnicate show HEAD allowed (1st read this turn)" "$(bashcall "$sid" p36h 'git --frobnicate show HEAD')"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "git with an unknown global option counts, next read refused" "$(readcall "$sid" p36h)"
# Non-reading git behind a global option never counts: three in one turn pass.
CLAUDE_1337_READ_CAP=1 check 0 "git -C . diff (1st) allowed" "$(bashcall "$sid" p36i 'git -C . diff')"
CLAUDE_1337_READ_CAP=1 check 0 "git --no-pager diff HEAD (2nd) allowed" "$(bashcall "$sid" p36i 'git --no-pager diff HEAD')"
CLAUDE_1337_READ_CAP=1 check 0 "git -C /repo log --oneline (3rd) allowed" "$(bashcall "$sid" p36i 'git -C /repo log --oneline')"
CLAUDE_1337_READ_CAP=1 check 0 "git -C /repo status (4th) allowed" "$(bashcall "$sid" p36i 'git -C /repo status')"
CLAUDE_1337_READ_CAP=1 check 0 "git -c url.a:b.insteadOf=c show HEAD (5th) allowed" "$(bashcall "$sid" p36i 'git -c url.a:b.insteadOf=c show HEAD')"
CLAUDE_1337_READ_CAP=1 check 0 "a Read after five non-reading git calls is the 1st read" "$(readcall "$sid" p36i)"
# The command/env prefixes are transparent, and a -c alias.* config can rename
# any subcommand into a read, so each of these counts and fills the cap.
CLAUDE_1337_READ_CAP=1 check 0 "command git cat-file -p X allowed (1st read this turn)" "$(bashcall "$sid" p36j 'command git cat-file -p X')"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "command git cat-file -p X fills the cap, next read refused" "$(readcall "$sid" p36j)"
CLAUDE_1337_READ_CAP=1 check 0 "env GIT_PAGER=cat git grep foo allowed (1st read this turn)" "$(bashcall "$sid" p36k 'env GIT_PAGER=cat git grep foo')"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "env GIT_PAGER=cat git grep foo fills the cap, next read refused" "$(readcall "$sid" p36k)"
CLAUDE_1337_READ_CAP=1 check 0 "git -c alias.s=cat-file s -p X allowed (1st read this turn)" "$(bashcall "$sid" p36l 'git -c alias.s=cat-file s -p X')"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "git -c alias.* fills the cap, next read refused" "$(readcall "$sid" p36l)"
# An alias cannot shadow a builtin: git diff behind one never counts.
CLAUDE_1337_READ_CAP=1 check 0 "git -c alias.d=log diff HEAD (1st) allowed" "$(bashcall "$sid" p36m 'git -c alias.d=log diff HEAD')"
CLAUDE_1337_READ_CAP=1 check 0 "git -c alias.d=log diff HEAD (2nd) allowed" "$(bashcall "$sid" p36m 'git -c alias.d=log diff HEAD')"

# mcp__codebase-memory-mcp__search_graph counts as a read.
CLAUDE_1337_READ_CAP=1 check 0 "mcp search_graph: first call in p37 allowed" "$(mcpcall_named "$sid" p37 mcp__codebase-memory-mcp__search_graph)"
CLAUDE_1337_READ_CAP=1 check_grep 2 'Read #2' "mcp search_graph: second call in p37 refused" "$(mcpcall_named "$sid" p37 mcp__codebase-memory-mcp__search_graph)"

# After a turn change, the state file holds only the new turn: exactly the
# new key line plus the new turn's entries.
sid_trunc="$sid-trunc"
state_trunc="$STATEDIR/claude-1337-read-cap-$sid_trunc"
CLAUDE_1337_READ_CAP=2 check 0 "state truncation: read 1 in p38 (old turn)" "$(readcall "$sid_trunc" p38)"
CLAUDE_1337_READ_CAP=2 check 0 "state truncation: read 2 in p38 (old turn)" "$(readcall "$sid_trunc" p38)"
CLAUDE_1337_READ_CAP=2 check 0 "state truncation: read 1 in p39 (new turn)" "$(readcall "$sid_trunc" p39)"
# File now holds the header line "p39" plus the one entry line "p39 read":
# 2 lines total, no trace of the old turn's "p38" entries.
trunc_lines=$(wc -l < "$state_trunc" | tr -d ' ')
trunc_p38=$(grep -c -F 'p38 ' "$state_trunc")
trunc_p39=$(grep -c -F 'p39 ' "$state_trunc")
if [ "$trunc_lines" -eq 2 ] && [ "$trunc_p38" -eq 0 ] && [ "$trunc_p39" -eq 1 ]; then
  printf 'ok   state truncation: file holds only the new turn key\n'; ok_count=$((ok_count + 1))
else
  printf 'FAIL state truncation: file holds only the new turn key (lines=%s p38=%s p39=%s; content: %s)\n' "$trunc_lines" "$trunc_p38" "$trunc_p39" "$(tr '\n' '|' < "$state_trunc")"; fail=1; fail_count=$((fail_count + 1))
fi

# READ_CAP=0 with GREP_CAP=off: a Bash cat is refused (Bash reads follow the
# read kind, not the grep kind).
CLAUDE_1337_READ_CAP=0 CLAUDE_1337_GREP_CAP=off check_grep 2 'Read #1' "READ_CAP=0, GREP_CAP=off: Bash cat refused" "$(bashcall "$sid" p40 'cat src/lib.rs')"

# --- tasqx #682: quoted text inside a Bash command must not be split on as
# if it were a real |, ;, &&, || separator, and an unprotected glob in the
# unquoted word-split must not be expanded against the hook's own cwd.

bash_json() { jq -Rs . <<<"$1"; }
bashcall_json() { # session prompt_id command-json
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"Bash","tool_input":{"command":%s}}' "$1" "$2" "$3"
}

# A `;`/`|` quoted inside a string is data, not a real separator: neither
# example below is a read (the file-reader name only appears inside quotes).
CLAUDE_1337_READ_CAP=0 check 0 'gap 682: echo "run; cat file" is not a read' "$(bashcall_json "$sid" p41 "$(bash_json 'echo "run; cat file"')")"
CLAUDE_1337_READ_CAP=0 check 0 'gap 682: git commit -m "x; head first" is not a read' "$(bashcall_json "$sid" p42 "$(bash_json 'git commit -m "x; head first"')")"

# `$( )` runs even inside a double-quoted string, so a `;` there still
# separates real commands and `cat f` inside it still counts.
CLAUDE_1337_READ_CAP=0 check 2 'gap 682: echo "$(true; cat f)" IS a read' "$(bashcall_json "$sid" p43 "$(bash_json 'echo "$(true; cat f)"')")"

# `cat *.rs` counts as a read, and the glob must not be expanded against the
# hook's cwd: a directory whose only match is a dash-led filename proves it
# — expanded, that filename would parse as a flag and be dropped, undercounting
# to zero non-flag operands and wrongly passing as not-a-read.
GLOBDIR="$STATEDIR/globdir"
mkdir -p "$GLOBDIR"
touch -- "$GLOBDIR/-x.rs"
out=$(cd "$GLOBDIR" && printf '%s' "$(bashcall "$sid" p44 'cat *.rs')" | CLAUDE_1337_READ_CAP=0 "$HOOK" 2>&1 >/dev/null)
got=$?
if [ "$got" -eq 2 ]; then
  printf 'ok   gap 682: cat *.rs counts as a read, not glob-expanded against the hook cwd\n'; ok_count=$((ok_count + 1))
else
  printf 'FAIL gap 682: cat *.rs counts as a read, not glob-expanded against the hook cwd (exit %s; stderr: %s)\n' "$got" "$out"; fail=1; fail_count=$((fail_count + 1))
fi

# --- tasqx #693: plain file readers (cat, head, tail, etc.) count only when
# they have file operands; piped stages with no file operand of their own
# (e.g. `git log | tail -2`) do not count as reads.

# A plain file reader with no file operand is not a read.
CLAUDE_1337_READ_CAP=0 check 0 "git log | tail -2 (no file operand) allowed" "$(bashcall "$sid" p45 'git log | tail -2')"
CLAUDE_1337_READ_CAP=0 check 0 "echo x | head -n 5 (no file operand) allowed" "$(bashcall "$sid" p46 'echo x | head -n 5')"

# A plain file reader with a file operand is a read.
CLAUDE_1337_READ_CAP=0 check 2 "tail -2 src/x.py (has file operand) refused" "$(bashcall "$sid" p47 'tail -2 src/x.py')"
CLAUDE_1337_READ_CAP=0 check 2 "head -n 5 src/x.py (has file operand) refused" "$(bashcall "$sid" p48 'head -n 5 src/x.py')"
CLAUDE_1337_READ_CAP=0 check 2 "cat src/x.py (has file operand) refused" "$(bashcall "$sid" p49 'cat src/x.py')"

# A bare plain reader reading stdin only is not a read.
CLAUDE_1337_READ_CAP=0 check 0 "bare cat (stdin only) allowed" "$(bashcall "$sid" p50 'cat')"

# --- tasqx #693 (review): boolean flags like -s, -q don't take arguments,
# so they shouldn't skip the next token which may be the file operand.

# Boolean flags like -s (squeeze), -q (quiet) don't take arguments; the next token is still the file.
CLAUDE_1337_READ_CAP=0 check 2 "cat -s src/x.py (file operand after boolean flag) refused" "$(bashcall "$sid" p51 'cat -s src/x.py')"
CLAUDE_1337_READ_CAP=0 check 2 "tail -q src/x.py (file operand after boolean flag) refused" "$(bashcall "$sid" p52 'tail -q src/x.py')"

# Long-form flags like --lines N take arguments; the next token is skipped.
CLAUDE_1337_READ_CAP=0 check 2 "head --lines 3 src/x.py (file operand after flag with arg) refused" "$(bashcall "$sid" p53 'head --lines 3 src/x.py')"

# Piped long-form flags with no file operand are not reads.
CLAUDE_1337_READ_CAP=0 check 0 "git log | head --lines 3 (no file operand, piped) allowed" "$(bashcall "$sid" p54 'git log | head --lines 3')"

# --- tasqx #693 (review, second pass): -n and -c mean different things for different readers.
# For cat, -n means "number lines" (flag, no argument); for od, -c means "character format" (flag, no argument).
# Only head/tail have -n/-c as "count" flags that take arguments.

# For other readers, -n and -c are boolean flags that don't take arguments.
CLAUDE_1337_READ_CAP=0 check 2 "cat -n src/x.py (-n as number-lines flag, file follows) refused" "$(bashcall "$sid" p55 'cat -n src/x.py')"
CLAUDE_1337_READ_CAP=0 check 2 "od -c src/x.py (-c as character-format flag, file follows) refused" "$(bashcall "$sid" p56 'od -c src/x.py')"

# --- tasqx #696: bash_is_read runs on hooks/lib/tokenize.sh, the lexer
# orchestrator-guard.sh judges with. Each case below is a command the old
# mask-quotes + sed split judged wrong; the shared tokenizer judges it the
# way the shell runs it.

# A heredoc body is data, not commands, and the heredoc marker, an output
# redirect, a here-string and an fd duplication are not file operands.
CLAUDE_1337_READ_CAP=0 check 0 '696: cat > /tmp/x.json <<EOF (heredoc write) is not a read' "$(bashcall_json "$sid" p60 "$(bash_json $'cat > /tmp/x.json <<\'EOF\'\n{}\nEOF')")"
CLAUDE_1337_READ_CAP=0 check 0 '696: a heredoc body line `cat src/x.py` is not a read' "$(bashcall_json "$sid" p61 "$(bash_json $'python3 - <<\'EOF\'\ncat src/x.py\nhead -1 src/y.py\nEOF')")"
CLAUDE_1337_READ_CAP=0 check 0 '696: grep x 2>/dev/null (stderr redirect) is not a path operand' "$(bashcall_json "$sid" p62 "$(bash_json 'ps aux | grep x 2>/dev/null')")"
CLAUDE_1337_READ_CAP=0 check 0 '696: jq . 2>&1 (fd duplication) is not a path operand' "$(bashcall_json "$sid" p63 "$(bash_json 'echo {} | jq . 2>&1')")"
CLAUDE_1337_READ_CAP=0 check 0 '696: grep x > out.txt (output redirect) is not a path operand' "$(bashcall_json "$sid" p64 "$(bash_json 'ps aux | grep x > /tmp/out.txt')")"
CLAUDE_1337_READ_CAP=0 check 0 '696: od -c <<< "$v" (here-string) is not a read' "$(bashcall_json "$sid" p65 "$(bash_json 'od -c <<< "$v"')")"
# An input redirect still feeds a file to the reader: one operand, as before.
CLAUDE_1337_READ_CAP=0 check 2 '696: cat < src/x.py (input redirect) is still a read' "$(bashcall_json "$sid" p66 "$(bash_json 'cat < src/x.py')")"
CLAUDE_1337_READ_CAP=0 check 2 '696: jq . < data.json (input redirect as the path operand) is still a read' "$(bashcall_json "$sid" p67 "$(bash_json 'jq . < data.json')")"

# The inside of $( ), backticks and <( ) runs, as a segment of its own.
CLAUDE_1337_READ_CAP=0 check 2 '696: x=$(cat src/x.py) is a read' "$(bashcall_json "$sid" p68 "$(bash_json 'x=$(cat src/x.py)')")"
CLAUDE_1337_READ_CAP=0 check 2 '696: echo "$(head -1 src/x.py)" is a read' "$(bashcall_json "$sid" p69 "$(bash_json 'echo "$(head -1 src/x.py)"')")"
CLAUDE_1337_READ_CAP=0 check 2 '696: a backtick `cat src/x.py` is a read' "$(bashcall_json "$sid" p70 "$(bash_json 'echo `cat src/x.py`')")"
CLAUDE_1337_READ_CAP=0 check 2 '696: diff <(cat a.py) b.py is a read' "$(bashcall_json "$sid" p71 "$(bash_json 'diff <(cat a.py) b.py')")"
# ...and a pipe that closes inside <( ) does not hand the next word to it.
CLAUDE_1337_READ_CAP=0 check 0 '696: diff <(git log | grep -v x) <(git log) is not a read' "$(bashcall_json "$sid" p72 "$(bash_json 'diff <(git log | grep -v x) <(git log)')")"

# Shell keywords and group openers introduce a command; they are not it.
CLAUDE_1337_READ_CAP=0 check 2 '696: for f in a b; do cat $f; done is a read' "$(bashcall_json "$sid" p73 "$(bash_json 'for f in a b; do cat $f; done')")"
CLAUDE_1337_READ_CAP=0 check 2 '696: if grep -q x src/x.py; then echo y; fi is a read' "$(bashcall_json "$sid" p74 "$(bash_json 'if grep -q x src/x.py; then echo y; fi')")"
CLAUDE_1337_READ_CAP=0 check 2 '696: { cat src/x.py; } is a read' "$(bashcall_json "$sid" p75 "$(bash_json '{ cat src/x.py; }')")"
CLAUDE_1337_READ_CAP=0 check 2 '696: (cat src/x.py) in a subshell is a read' "$(bashcall_json "$sid" p76 "$(bash_json '(cat src/x.py)')")"
CLAUDE_1337_READ_CAP=0 check 2 '696: ! grep -q x src/x.py is a read' "$(bashcall_json "$sid" p77 "$(bash_json '! grep -q x src/x.py')")"

# A lone & separates commands; a comment runs nothing.
CLAUDE_1337_READ_CAP=0 check 2 '696: sleep 1 & cat src/x.py is a read' "$(bashcall_json "$sid" p78 "$(bash_json 'sleep 1 & cat src/x.py')")"
CLAUDE_1337_READ_CAP=0 check 0 '696: ls # ; cat src/x.py (a comment) is not a read' "$(bashcall_json "$sid" p79 "$(bash_json 'ls # ; cat src/x.py')")"

# A quoted span runs across lines: a multi-line jq program is one word, and
# a multi-line commit message naming a reader stays data.
CLAUDE_1337_READ_CAP=0 check 2 '696: jq with a multi-line program and a file is a read' "$(bashcall_json "$sid" p80 "$(bash_json $'jq -r \'\n  .a\n  | .b\' data.json')")"
CLAUDE_1337_READ_CAP=0 check 0 '696: a multi-line commit message naming `; cat f` is not a read' "$(bashcall_json "$sid" p81 "$(bash_json $'git commit -m "first\nsecond; cat src/x.py"')")"

# command -v / -V looks a name up and runs nothing.
CLAUDE_1337_READ_CAP=0 check 0 '696: command -v cat src/x.py (a lookup) is not a read' "$(bashcall_json "$sid" p82 "$(bash_json 'command -v cat src/x.py')")"

# --- tasqx #699: jq's own options are not all flag-then-operand, so
# bash_is_read counts jq operands with jq's own option grammar instead of
# the generic sed/grep/awk rule.
CLAUDE_1337_READ_CAP=0 check 0 '699: jq -n --arg c x (--arg NAME VALUE is not a file) is not a read' "$(bashcall_json "$sid" p83 "$(bash_json "jq -n --arg c x '{c:\$c}'")")"
CLAUDE_1337_READ_CAP=0 check 0 '699: jq -n --argjson n 1 (--argjson NAME VALUE is not a file) is not a read' "$(bashcall_json "$sid" p84 "$(bash_json "jq -n --argjson n 1 '\$n'")")"
CLAUDE_1337_READ_CAP=0 check 2 '699: jq --indent 2 . f.json (a real file operand) is a read' "$(bashcall_json "$sid" p85 "$(bash_json 'jq --indent 2 . f.json')")"
CLAUDE_1337_READ_CAP=0 check 2 '699: jq --rawfile t notes.md -n (--rawfile FILE is a read) is a read' "$(bashcall_json "$sid" p86 "$(bash_json "jq --rawfile t notes.md -n '\$t'")")"
CLAUDE_1337_READ_CAP=0 check 2 '699: jq -f prog.jq data.json (-f FILE plus a data file) is a read' "$(bashcall_json "$sid" p87 "$(bash_json 'jq -f prog.jq data.json')")"
CLAUDE_1337_READ_CAP=0 check 2 '699: jq -n -f prog.jq (-f FILE alone still reads prog.jq) is a read' "$(bashcall_json "$sid" p88 "$(bash_json 'jq -n -f prog.jq')")"
CLAUDE_1337_READ_CAP=0 check 0 '699: echo {} | jq --arg a b (piped, no file operand) is not a read' "$(bashcall_json "$sid" p89 "$(bash_json "echo '{}' | jq --arg a b '.x=\$a'")")"
CLAUDE_1337_READ_CAP=0 check 0 '699: jq -n --args (positional args after --args are not files) is not a read' "$(bashcall_json "$sid" p90 "$(bash_json "jq -n --args '\$ARGS' a b")")"

printf 'summary: %d ok, %d FAIL, %d todo\n' "$ok_count" "$fail_count" "$todo_count"
exit $fail
