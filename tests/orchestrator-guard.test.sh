#!/usr/bin/env bash
# Tests for hooks/orchestrator-guard.sh: feeds crafted PreToolUse payloads and
# asserts the exit code. Exit 2 = refused, exit 0 = allowed.
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/orchestrator-guard.sh"
fail=0

check() { # expected-exit description payload
  local got
  printf '%s' "$3" | "$HOOK" 2>/dev/null
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'ok   %s\n' "$2"; else printf 'FAIL %s (exit %s, want %s)\n' "$2" "$got" "$1"; fail=1; fi
}

big=$(printf 'line\n%.0s' $(seq 1 30))
bigjson=$(jq -Rs . <<<"$big")
write='{"tool_name":"Write","tool_input":{"file_path":"/repo/new.py","content":"x"}}'

unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR CLAUDE_1337_ORCHESTRATOR
check 0 "mode off: write allowed" "$write"
[ -z "$("$HOOK" --rules)" ] && echo "ok   mode off: no rules printed" || { echo "FAIL mode off: rules printed"; fail=1; }

export CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=true
check 0 "small edit in main session" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/repo/a.py","old_string":"a","new_string":"b"}}'
check 2 "big edit in main session" \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/repo/a.py\",\"old_string\":\"a\",\"new_string\":$bigjson}}"
check 2 "write in main session" "$write"
check 2 "big multiedit in main session" \
  "{\"tool_name\":\"MultiEdit\",\"tool_input\":{\"file_path\":\"/repo/a.py\",\"edits\":[{\"new_string\":$bigjson}]}}"
check 0 "write from subagent" \
  '{"agent_id":"abc","tool_name":"Write","tool_input":{"file_path":"/repo/new.py","content":"x"}}'
check 0 "write under ~/.claude" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/projects/p/memory/m.md\",\"content\":\"x\"}}"
check 0 "write in temp scratchpad" \
  '{"tool_name":"Write","tool_input":{"file_path":"/private/tmp/claude-501/x/scratchpad/f.txt","content":"x"}}'

# Bash writes are refused in the main session, reads are not.
check 2 "bash redirect to a file in main session" \
  '{"tool_name":"Bash","tool_input":{"command":"printf \"a\\nb\\n\" > /repo/big.txt"}}'
check 2 "bash heredoc in main session" \
  '{"tool_name":"Bash","tool_input":{"command":"cat <<EOF > /repo/f.txt\nhello\nEOF"}}'
check 2 "bash append-redirect in main session" \
  '{"tool_name":"Bash","tool_input":{"command":"echo x >> /repo/f.txt"}}'
check 2 "bash tee in main session" \
  '{"tool_name":"Bash","tool_input":{"command":"echo x | tee /repo/f.txt"}}'
check 2 "bash sed -i in main session" \
  '{"tool_name":"Bash","tool_input":{"command":"sed -i \"s/a/b/\" /repo/f.txt"}}'
check 0 "bash redirect to /dev/null" \
  '{"tool_name":"Bash","tool_input":{"command":"grep -r todo /repo 2>/dev/null"}}'
check 0 "bash redirect into temp dir" \
  '{"tool_name":"Bash","tool_input":{"command":"seq 1 40 > /tmp/claude-501/scratch/f.txt"}}'
check 0 "bash read-only command" \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la /repo"}}'
check 0 "bash from subagent" \
  '{"agent_id":"abc","tool_name":"Bash","tool_input":{"command":"printf \"a\" > /repo/big.txt"}}'
check 0 "bash piped grep, no redirect" \
  '{"tool_name":"Bash","tool_input":{"command":"cat /repo/f.txt | grep -c line"}}'
check 0 "bash heredoc to stdin, no file redirect" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"python3 /repo/route.py <<'EOF'\n{\\\"a\\\":1}\nEOF\"}}"
check 2 "bash redirect without a space" \
  '{"tool_name":"Bash","tool_input":{"command":"echo x >/repo/f.txt"}}'
check 0 "bash stderr to stdout only" \
  '{"tool_name":"Bash","tool_input":{"command":"make test 2>&1 | tail -5"}}'
check 0 "bash redirect to stderr" \
  '{"tool_name":"Bash","tool_input":{"command":"echo warn >&2"}}'
check 2 "bash heredoc writes a script under /tmp" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat > /tmp/x.py <<'EOF'\nprint(1)\nEOF\"}}"
check 0 "bash heredoc writes data under /tmp" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat > /tmp/data.json <<'EOF'\n{}\nEOF\"}}"
check 2 "bash heredoc writes a script under a variable temp path" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"S=/tmp/claude-1000/scratch; cat > \$S/knock.py <<'EOF'\nprint(1)\nEOF\"}}"
check 2 "bash tee writes a script under /tmp" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"tee /tmp/run.sh <<'EOF'\necho hi\nEOF\"}}"
check 0 "bash heredoc to stdin under /tmp, no script file" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"python3 - <<'EOF'\nprint(1)\nEOF\"}}"
check 0 "bash redirect writes data under /tmp" \
  '{"tool_name":"Bash","tool_input":{"command":"printf x > /tmp/out.txt"}}'
check 2 "bash sed -i with an expression before the script file" \
  '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ /tmp/fix.sh"}}'
check 2 "bash sed -i.bak -e before the script file" \
  '{"tool_name":"Bash","tool_input":{"command":"sed -i.bak -e s/a/b/ /tmp/fix.sh"}}'
check 0 "bash sed -i on a data file under /tmp" \
  '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ /tmp/notes.txt"}}'
check 2 "bash heredoc writes a quoted script path" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"S=/tmp/claude-1000/scratch; cat > \\\"\$S/x.py\\\" <<'EOF'\nprint(1)\nEOF\"}}"
check 2 "bash tee writes a quoted script path" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"tee '/tmp/run.sh' <<'EOF'\necho hi\nEOF\"}}"
check 2 "bash sed -i on a quoted script path" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -i 's/a/b/' \\\"/tmp/fix.sh\\\"\"}}"
check 0 "bash heredoc writes a quoted data path under /tmp" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat > \\\"/tmp/data.json\\\" <<'EOF'\n{}\nEOF\"}}"

# Inline scripts piped into an interpreter through a heredoc.
body30=$(printf 'line\n%.0s' $(seq 1 30))
body5=$(printf 'line\n%.0s' $(seq 1 5))
py30=$(printf "python3 - <<'EOF'\n%s\nEOF" "$body30")
py30json=$(jq -Rs . <<<"$py30")
py5=$(printf "python3 - <<'EOF'\n%s\nEOF" "$body5")
py5json=$(jq -Rs . <<<"$py5")
commit30=$(printf "git commit -q -F - <<'EOF'\n%s\nEOF" "$body30")
commit30json=$(jq -Rs . <<<"$commit30")
node30=$(printf "node - <<EOF\n%s\nEOF" "$body30")
node30json=$(jq -Rs . <<<"$node30")
two_heredoc=$(printf "cat <<A\n%s\nA\nbash <<B\n%s\nB" "$body5" "$body30")
two_heredocjson=$(jq -Rs . <<<"$two_heredoc")

check 2 "inline 30-line python3 heredoc" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py30json}}"
check 0 "inline 5-line python3 heredoc" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py5json}}"
check 0 "git commit -F - heredoc, not an interpreter" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$commit30json}}"
check 2 "inline 30-line node heredoc" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$node30json}}"
CLAUDE_1337_INLINE_LINES=0 check 0 "inline check disabled via CLAUDE_1337_INLINE_LINES=0" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py30json}}"
check 2 "two heredocs, second one over the limit" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$two_heredocjson}}"
CLAUDE_1337_INLINE_LINES=40 check 0 "inline check with a raised limit" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py30json}}"

"$HOOK" --rules | grep -q '^# Orchestrator mode' && echo "ok   mode on: rules printed" || { echo "FAIL mode on: rules missing"; fail=1; }

unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR
CLAUDE_1337_ORCHESTRATOR=1 check 2 "env switch turns mode on" "$write"

# Per-session small-edit cap. Isolate state in a scratch TMPDIR.
export CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=true
edit_cap_tmpdir=$(mktemp -d)
export TMPDIR="$edit_cap_tmpdir"
trap 'rm -rf "$edit_cap_tmpdir"' EXIT

small_edit_a() {
  printf '{"session_id":"ecap-%s-a","tool_name":"Edit","tool_input":{"file_path":"/repo/a.py","old_string":"a","new_string":"b"}}' "$$"
}

for n in 1 2 3 4 5; do
  check 0 "edit cap: small edit $n/5 session ecap-a" "$(small_edit_a)"
done
sixth_err=$(printf '%s' "$(small_edit_a)" | "$HOOK" 2>&1 >/dev/null)
sixth_exit=$?
[ "$sixth_exit" -eq 2 ] && echo "ok   edit cap: sixth small edit session ecap-a" \
  || { echo "FAIL edit cap: sixth small edit session ecap-a (exit $sixth_exit, want 2)"; fail=1; }
printf '%s' "$sixth_err" | grep -q "small edit #6" \
  && echo "ok   edit cap: stderr names #6" || { echo "FAIL edit cap: stderr missing #6 ($sixth_err)"; fail=1; }

check 0 "edit cap: exempt path not counted after cap" \
  "{\"session_id\":\"ecap-$$-a\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/x\",\"content\":\"x\"}}"

check 2 "edit cap: large edit in fresh session does not count" \
  "{\"session_id\":\"ecap-$$-b\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/repo/a.py\",\"old_string\":\"a\",\"new_string\":$bigjson}}"
for n in 1 2 3 4 5; do
  check 0 "edit cap: small edit $n/5 session ecap-b" \
    "{\"session_id\":\"ecap-$$-b\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/repo/b.py\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
done
check 2 "edit cap: sixth small edit session ecap-b" \
  "{\"session_id\":\"ecap-$$-b\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/repo/b.py\",\"old_string\":\"a\",\"new_string\":\"b\"}}"

CLAUDE_1337_EDIT_CAP=0 check 0 "edit cap: disabled via CLAUDE_1337_EDIT_CAP=0" "$(small_edit_a)"

check 0 "edit cap: fresh counter for session ecap-c" \
  "{\"session_id\":\"ecap-$$-c\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/repo/c.py\",\"old_string\":\"a\",\"new_string\":\"b\"}}"

no_session_edit='{"tool_name":"Edit","tool_input":{"file_path":"/repo/nosession.py","old_string":"a","new_string":"b"}}'
check 0 "edit cap: no session_id, repeat 1/3" "$no_session_edit"
check 0 "edit cap: no session_id, repeat 2/3" "$no_session_edit"
check 0 "edit cap: no session_id, repeat 3/3" "$no_session_edit"

exit $fail
