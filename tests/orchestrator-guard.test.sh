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

# ~/.claude is not all scratch: config, the installed plugin's hooks/skills
# and other non-data paths under it are off-limits (#695).
check 2 "write to ~/.claude/settings.json is refused" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/settings.json\",\"content\":\"x\"}}"
check 2 "edit under the installed plugin's cache is refused" \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.claude/plugins/cache/x/hooks/a.sh\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
check 2 "bash redirect to ~/.claude/settings.local.json is refused" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > $HOME/.claude/settings.local.json\"}}"
check 2 "mkdir under the installed plugin is refused" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"mkdir -p $HOME/.claude/plugins/evil\"}}"
check 2 "tee to ~/.claude/CLAUDE.md is refused" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"tee $HOME/.claude/CLAUDE.md\"}}"
check 2 "a .. step out of the data allowlist into plugins is still refused" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > $HOME/.claude/projects/../plugins/x\"}}"
check 0 "write to ~/.claude/projects memory stays allowed" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/projects/-home-x/memory/a.md\",\"content\":\"x\"}}"
check 0 "bash redirect into a temp claude-* scratch dir stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"echo x > /tmp/claude-1000/s/msg.txt"}}'
check 0 "bash redirect to a ~/.claude/.1337-* state file stays allowed" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo on > $HOME/.claude/.1337-terse\"}}"
# Plan mode writes its plan file under ~/.claude/plans.
check 0 "write to a ~/.claude/plans plan file is allowed" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/plans/x.md\",\"content\":\"x\"}}"
check 0 "bash redirect to ~/.claude/plans is allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"echo hi > ~/.claude/plans/x.md"}}'
check 2 "a .. step out of ~/.claude/plans to settings.json is refused (Write)" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/plans/../settings.json\",\"content\":\"x\"}}"
check 2 "a .. step out of ~/.claude/plans to settings.json is refused (Bash)" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > $HOME/.claude/plans/../settings.json\"}}"

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
  '{"tool_name":"Bash","tool_input":{"command":"echo todo 2>/dev/null"}}'
CLAUDE_1337_BASH_ALLOW=seq check 0 "bash redirect into temp dir (seq via CLAUDE_1337_BASH_ALLOW)" \
  '{"tool_name":"Bash","tool_input":{"command":"seq 1 40 > /tmp/claude-501/scratch/f.txt"}}'
check 0 "bash read-only command" \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la /repo"}}'

# #704: a redirect target that still carries an unexpanded variable after
# resolution (a loop variable, here) is refused with a message naming the
# unexpanded variable, not the generic write message; a literal temp target
# inside a loop stays allowed.
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"for i in 1 2 3; do claude plugin eval . --case x --json > /tmp/claude-1000/scratch/eval-$i.json 2>&1; done"}}' | CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=true ./hooks/orchestrator-guard.sh 2>&1)
got=$?
if [ "$got" -eq 2 ] && printf '%s' "$out" | grep -q "unexpanded variable"; then
  echo "ok   bash redirect target with unexpanded loop variable is refused, naming the variable"
else
  echo "FAIL bash redirect target with unexpanded loop variable is refused, naming the variable (exit $got, output: $out)"; fail=1
fi
check 0 "bash redirect into a temp dir with a literal target inside a loop" \
  '{"tool_name":"Bash","tool_input":{"command":"for i in 1 2; do echo x > /tmp/claude-1000/scratch/out.json; done"}}'
check 0 "bash from subagent" \
  '{"agent_id":"abc","tool_name":"Bash","tool_input":{"command":"printf \"a\" > /repo/big.txt"}}'
check 2 "bash piped grep, no redirect, cat still dumps the file" \
  '{"tool_name":"Bash","tool_input":{"command":"cat /repo/f.txt | grep -c line"}}'
CLAUDE_1337_BASH_ALLOW=ps check 0 "bash piped grep, filter only, no file operand" \
  '{"tool_name":"Bash","tool_input":{"command":"ps aux | grep foo"}}'
check 2 "python3 script outside the plugin, heredoc on stdin" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"python3 /repo/route.py <<'EOF'\n{\\\"a\\\":1}\nEOF\"}}"
check 0 "bash heredoc to stdin of the tier router, no file redirect" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"python3 skills/tier/route.py <<'EOF'\n{\\\"a\\\":1}\nEOF\"}}"
check 2 "bash redirect without a space" \
  '{"tool_name":"Bash","tool_input":{"command":"echo x >/repo/f.txt"}}'
CLAUDE_1337_BASH_ALLOW=make check 0 "bash stderr to stdout only (make via CLAUDE_1337_BASH_ALLOW)" \
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
check 2 "python3 - fed a heredoc is an inline script, off the allowlist" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"python3 - <<'EOF'\nprint(1)\nEOF\"}}"
check 0 "bash redirect writes data under /tmp" \
  '{"tool_name":"Bash","tool_input":{"command":"printf x > /tmp/out.txt"}}'
check 2 "bash sed -i with an expression before the script file" \
  '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ /tmp/fix.sh"}}'
check 2 "bash sed -i.bak -e before the script file" \
  '{"tool_name":"Bash","tool_input":{"command":"sed -i.bak -e s/a/b/ /tmp/fix.sh"}}'
check 2 "bash sed -i on a data file under /tmp: sed -i is off the allowlist" \
  '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ /tmp/notes.txt"}}'
check 2 "bash heredoc writes a quoted script path" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"S=/tmp/claude-1000/scratch; cat > \\\"\$S/x.py\\\" <<'EOF'\nprint(1)\nEOF\"}}"
check 2 "bash tee writes a quoted script path" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"tee '/tmp/run.sh' <<'EOF'\necho hi\nEOF\"}}"
check 2 "bash sed -i on a quoted script path" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -i 's/a/b/' \\\"/tmp/fix.sh\\\"\"}}"
check 0 "bash heredoc writes a quoted data path under /tmp" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat > \\\"/tmp/data.json\\\" <<'EOF'\n{}\nEOF\"}}"

# Inline scripts piped into an interpreter through a heredoc: every one is off
# the allowlist, whatever its length. CLAUDE_1337_INLINE_LINES is gone.
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
check 2 "inline 5-line python3 heredoc" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py5json}}"
check 0 "git commit -F - heredoc, not an interpreter" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$commit30json}}"
check 2 "inline 30-line node heredoc" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$node30json}}"
CLAUDE_1337_INLINE_LINES=0 check 2 "CLAUDE_1337_INLINE_LINES=0 no longer lets an inline script through" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py30json}}"
check 2 "two heredocs, second one over the limit" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$two_heredocjson}}"
CLAUDE_1337_INLINE_LINES=40 check 2 "CLAUDE_1337_INLINE_LINES=40 no longer lets an inline script through" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py30json}}"

# Heredoc bodies fed to a non-interpreter consumer are data, not commands:
# write patterns mentioned inside them must not trip the guard.
commit_sed=$(printf "git commit -q -F - <<'EOF'\nsed -i into code files\nEOF")
commit_sedjson=$(jq -Rs . <<<"$commit_sed")
commit_catpy=$(printf "git commit -q -F - <<'EOF'\nrefuse cat > out.py\nEOF")
commit_catpyjson=$(jq -Rs . <<<"$commit_catpy")
commit_tee=$(printf "git commit -q -F - <<'EOF'\nuse tee here\nEOF")
commit_teejson=$(jq -Rs . <<<"$commit_tee")
commit_nested=$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nmentions > a.py\nEOF\n)"')
commit_nestedjson=$(jq -Rs . <<<"$commit_nested")
cat_stdin_only=$(printf "cat <<'EOF'\necho hi > a.py\nEOF")
cat_stdin_onlyjson=$(jq -Rs . <<<"$cat_stdin_only")
cat_redirect=$(printf "cat <<'EOF' > out.py\nhello\nEOF")
cat_redirectjson=$(jq -Rs . <<<"$cat_redirect")
tee_opener=$(printf "tee out.py <<'EOF'\nhello\nEOF")
tee_openerjson=$(jq -Rs . <<<"$tee_opener")
bash_interp_body=$(printf "bash <<'EOF'\necho hi > a.py\nEOF")
bash_interp_bodyjson=$(jq -Rs . <<<"$bash_interp_body")
py_write_body=$(printf "python3 - <<'EOF'\nline1\nopen(\"a.py\",\"w\")\nline3\nEOF")
py_write_bodyjson=$(jq -Rs . <<<"$py_write_body")

check 0 "heredoc body mentions sed -i, non-interpreter consumer" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$commit_sedjson}}"
check 0 "heredoc body mentions cat > out.py, non-interpreter consumer" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$commit_catpyjson}}"
check 0 "heredoc body mentions tee, non-interpreter consumer" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$commit_teejson}}"
check 0 "nested heredoc body mentions a redirect, git commit -m \$(cat <<EOF)" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$commit_nestedjson}}"
check 0 "cat heredoc to stdin only, body mentions a redirect" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$cat_stdin_onlyjson}}"
check 2 "cat heredoc with a real redirect on the opener line" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$cat_redirectjson}}"
check 2 "tee heredoc with a real target on the opener line" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$tee_openerjson}}"
check 2 "bash heredoc body is scanned, interpreter consumer" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$bash_interp_bodyjson}}"
check 2 "python3 heredoc body writes via open(): python3 - is off the allowlist" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_write_bodyjson}}"

"$HOOK" --rules | grep -q '^# Orchestrator mode' && echo "ok   mode on: rules printed" || { echo "FAIL mode on: rules missing"; fail=1; }

unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR
CLAUDE_1337_ORCHESTRATOR=1 check 2 "env switch turns mode on" "$write"

unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR CLAUDE_1337_ORCHESTRATOR
EVAL_CLAUDE_1337_ORCHESTRATOR=1 check 2 "eval switch turns mode on" "$write"
unset EVAL_CLAUDE_1337_ORCHESTRATOR

# Per-session edit cap, shared by small edits and ripwire symbol edits.
# Isolate state in a scratch TMPDIR; every case uses its own session id.
export CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=true
edit_cap_tmpdir=$(mktemp -d)
export TMPDIR="$edit_cap_tmpdir"
trap 'rm -rf "$edit_cap_tmpdir"' EXIT

small_edit() { # session-suffix [file]
  printf '{"session_id":"ecap-%s-%s","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
    "$$" "$1" "${2:-/repo/a.py}"
}
ripwire_edit() { # session-suffix
  printf '{"session_id":"ecap-%s-%s","tool_name":"Bash","tool_input":{"command":"ripwire . --replace-symbol-body=parse --edit-payload=/tmp/payload.txt"}}' \
    "$$" "$1"
}
ripwire_map() { # session-suffix
  printf '{"session_id":"ecap-%s-%s","tool_name":"Bash","tool_input":{"command":"ripwire . --for=\\"x\\" --legend=compact"}}' \
    "$$" "$1"
}
ripwire_edit_plan() { # session-suffix
  printf '{"session_id":"ecap-%s-%s","tool_name":"Bash","tool_input":{"command":"ripwire . --edit-plan=/tmp/plan.json --apply"}}' \
    "$$" "$1"
}
ripwire_edit_plan_dry_run() { # session-suffix
  printf '{"session_id":"ecap-%s-%s","tool_name":"Bash","tool_input":{"command":"ripwire . --edit-plan=/tmp/plan.json --dry-run"}}' \
    "$$" "$1"
}

for n in 1 2 3; do
  check 0 "edit cap: small edit $n/3 session ecap-a" "$(small_edit a)"
done
fourth_err=$(printf '%s' "$(small_edit a)" | "$HOOK" 2>&1 >/dev/null)
fourth_exit=$?
[ "$fourth_exit" -eq 2 ] && echo "ok   edit cap: fourth small edit session ecap-a" \
  || { echo "FAIL edit cap: fourth small edit session ecap-a (exit $fourth_exit, want 2)"; fail=1; }
printf '%s' "$fourth_err" | grep -q "edit #4" \
  && echo "ok   edit cap: stderr names #4" || { echo "FAIL edit cap: stderr missing #4 ($fourth_err)"; fail=1; }
printf '%s' "$fourth_err" | grep -q "1337:builder" \
  && echo "ok   edit cap: stderr points at 1337:builder" || { echo "FAIL edit cap: stderr missing 1337:builder ($fourth_err)"; fail=1; }

check 0 "edit cap: exempt path not counted after cap" \
  "{\"session_id\":\"ecap-$$-a\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/projects/p/x\",\"content\":\"x\"}}"

check 2 "edit cap: large edit in fresh session does not count" \
  "{\"session_id\":\"ecap-$$-b\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/repo/a.py\",\"old_string\":\"a\",\"new_string\":$bigjson}}"
for n in 1 2 3; do
  check 0 "edit cap: small edit $n/3 session ecap-b" "$(small_edit b /repo/b.py)"
done
check 2 "edit cap: fourth small edit session ecap-b" "$(small_edit b /repo/b.py)"

# A ripwire symbol edit writes into the repository and spends one unit of the
# same budget: two hand edits plus one ripwire edit fill the cap of 3.
check 0 "edit cap: small edit 1/3 session ecap-r" "$(small_edit r)"
check 0 "edit cap: small edit 2/3 session ecap-r" "$(small_edit r)"
check 0 "edit cap: ripwire symbol edit 3/3 session ecap-r" "$(ripwire_edit r)"
check 2 "edit cap: small edit after the ripwire edit filled the cap" "$(small_edit r)"
check 2 "edit cap: another ripwire symbol edit past the cap" "$(ripwire_edit r)"

# Payload on stdin through a heredoc, and the insert forms, are the same route.
rw_stdin=$(printf "ripwire . --insert-after-symbol=parse --edit-payload=- <<'EOF'\nfn added() {}\nEOF")
rw_stdinjson=$(jq -Rs . <<<"$rw_stdin")
check 0 "edit cap: ripwire insert-after with a stdin payload" \
  "{\"session_id\":\"ecap-$$-s\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$rw_stdinjson}}"

# A map query carries no --edit-payload: it neither writes nor counts, however
# often it runs.
for n in 1 2 3 4 5; do
  check 0 "edit cap: ripwire map query $n does not count" "$(ripwire_map q)"
done
for n in 1 2 3; do
  check 0 "edit cap: small edit $n/3 after five map queries" "$(small_edit q)"
done
check 2 "edit cap: fourth small edit session ecap-q" "$(small_edit q)"

# --edit-plan with --apply applies a transaction and spends one unit of the
# same budget, the same as the single-symbol edit forms.
check 0 "edit cap: small edit 1/3 session ecap-p" "$(small_edit p)"
check 0 "edit cap: small edit 2/3 session ecap-p" "$(small_edit p)"
check 0 "edit cap: ripwire edit-plan --apply 3/3 session ecap-p" "$(ripwire_edit_plan p)"
check 2 "edit cap: small edit after the edit-plan filled the cap" "$(small_edit p)"
check 2 "edit cap: another ripwire edit-plan past the cap" "$(ripwire_edit_plan p)"

# --edit-plan with --dry-run only preflights: it neither writes nor counts,
# however often it runs.
for n in 1 2 3 4 5; do
  check 0 "edit cap: ripwire edit-plan --dry-run $n does not count" "$(ripwire_edit_plan_dry_run dp)"
done
for n in 1 2 3; do
  check 0 "edit cap: small edit $n/3 after five edit-plan dry-runs" "$(small_edit dp)"
done
check 2 "edit cap: fourth small edit session ecap-dp" "$(small_edit dp)"

CLAUDE_1337_EDIT_CAP=0 check 0 "edit cap: disabled via CLAUDE_1337_EDIT_CAP=0" "$(small_edit a)"
CLAUDE_1337_EDIT_CAP=1 check 0 "edit cap: CLAUDE_1337_EDIT_CAP=1, first edit" "$(small_edit one)"
CLAUDE_1337_EDIT_CAP=1 check 2 "edit cap: CLAUDE_1337_EDIT_CAP=1, second edit" "$(small_edit one)"

check 0 "edit cap: fresh counter for session ecap-c" "$(small_edit c /repo/c.py)"

# Subagent calls never reach the counter, whatever the session id says.
sub_edit="{\"agent_id\":\"abc\",\"session_id\":\"ecap-$$-a\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/repo/a.py\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
for n in 1 2 3 4; do
  check 0 "edit cap: subagent edit $n unaffected by a filled cap" "$sub_edit"
done
check 0 "edit cap: subagent ripwire symbol edit unaffected" \
  "{\"agent_id\":\"abc\",\"session_id\":\"ecap-$$-a\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ripwire . --replace-symbol-body=parse --edit-payload=/tmp/p.txt\"}}"

no_session_edit='{"tool_name":"Edit","tool_input":{"file_path":"/repo/nosession.py","old_string":"a","new_string":"b"}}'
check 0 "edit cap: no session_id, repeat 1/3" "$no_session_edit"
check 0 "edit cap: no session_id, repeat 2/3" "$no_session_edit"
check 0 "edit cap: no session_id, repeat 3/3" "$no_session_edit"

# Read-dumping Bash commands: refused with a pointer to ripwire / 1337:scout,
# in the same words as the read-cap hook.
check 2 "bash cat dumps a source file" \
  '{"tool_name":"Bash","tool_input":{"command":"cat src/foo.rs"}}'
check 0 "bash cat under /tmp stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"cat /tmp/x.json"}}'
CLAUDE_1337_BASH_ALLOW=ps check 0 "bash grep filters a pipe, no file operand" \
  '{"tool_name":"Bash","tool_input":{"command":"ps aux | grep foo"}}'
check 2 "bash grep -r over a directory" \
  '{"tool_name":"Bash","tool_input":{"command":"grep -r pattern src/"}}'
check 0 "bash git diff stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff"}}'
check 0 "bash git diff with revision and path stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff HEAD~1 -- src/lib.rs"}}'
check 0 "bash git diff --stat stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff --stat"}}'
check 0 "bash git diff HEAD stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff HEAD"}}'
check 2 "bash git diff --no-index dumps an arbitrary file" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff --no-index /dev/null tools/x.py"}}'
check 2 "bash git -C . diff --stat --no-index is refused too" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C . diff --stat --no-index a b"}}'
check 2 "bash git diff /dev/null <file> (implicit --no-index) dumps a file" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff /dev/null tools/x.py"}}'
check 0 "bash git show HEAD (no colon operand) stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git show HEAD"}}'
check 0 "bash git show --stat HEAD stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git show --stat HEAD"}}'
check 2 "bash git show rev:path dumps a file's contents" \
  '{"tool_name":"Bash","tool_input":{"command":"git show HEAD:src/lib.rs"}}'
check 2 "bash git show sha:path dumps a file's contents" \
  '{"tool_name":"Bash","tool_input":{"command":"git show abc123:Cargo.toml"}}'
check 2 "bash git show :path (index form) dumps a file's contents" \
  '{"tool_name":"Bash","tool_input":{"command":"git show :src/lib.rs"}}'
check 2 "bash git cat-file -p dumps a file's contents" \
  '{"tool_name":"Bash","tool_input":{"command":"git cat-file -p HEAD:src/lib.rs"}}'
check 2 "bash git grep searches tracked file contents" \
  '{"tool_name":"Bash","tool_input":{"command":"git grep -n TODO"}}'
check 0 "bash git log stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git log"}}'
check 0 "bash git blame stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git blame src/lib.rs"}}'
# A git global option in front does not hide the subcommand
# (hooks/lib/git-subcommand.sh): the three readers are still refused, and
# everything else behaves exactly as its plain form.
check 2 "bash git -C <path> show rev:path dumps a file's contents" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo show HEAD:secret.py"}}'
check 2 "bash git --no-pager grep searches tracked file contents" \
  '{"tool_name":"Bash","tool_input":{"command":"git --no-pager grep foo"}}'
check 2 "bash git -C . cat-file dumps a file's contents" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C . cat-file -p X"}}'
check 2 "bash git -C with a quoted path holding a space, then show rev:path" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C '"'"'/my repo'"'"' show HEAD:secret.py"}}'
check 2 "bash git -c <k=v> --git-dir <v> show rev:path" \
  '{"tool_name":"Bash","tool_input":{"command":"git -c core.pager=cat --git-dir /r/.git show HEAD:a.py"}}'
check 0 "bash git -C /repo show HEAD (no colon operand) stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo show HEAD"}}'
check 0 "bash git -c with a colon in its value, then show HEAD, stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git -c url.a:b.insteadOf=c show HEAD"}}'
check 0 "bash git -C . diff stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C . diff"}}'
check 0 "bash git --no-pager diff HEAD stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git --no-pager diff HEAD"}}'
check 0 "bash git -C /repo log --oneline stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo log --oneline"}}'
check 0 "bash git -C /repo status stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /repo status"}}'
check 0 "bash git --version stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git --version"}}'
# An unknown option where a global option goes cannot be skipped safely (it
# may take a value that hides the subcommand), so it is refused as a read.
check 2 "bash git with an unknown global option is refused as a possible read" \
  '{"tool_name":"Bash","tool_input":{"command":"git --frobnicate show HEAD"}}'
check 0 "bash ripwire stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"ripwire . --for=\"x\""}}'
py_read=$(printf "python3 - <<'EOF'\nopen('secret.txt')\nEOF")
py_readjson=$(jq -Rs . <<<"$py_read")
check 2 "python3 heredoc containing open( is a read" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_readjson}}"
check 0 "bash read-dump command from a subagent still passes" \
  '{"agent_id":"abc","tool_name":"Bash","tool_input":{"command":"cat /repo/f.txt"}}'

# The mode of an inline open() is its own argument, after a comma: a filename
# starting with w, a or x is still a read. A write-mode open is not a read, but
# python3 -c is off the allowlist, so it is refused all the same.
bash_json() { jq -Rs . <<<"$1"; }
py_read_arg=$(bash_json 'python3 -c '"'"'print(open("app.py").read())'"'"'')
py_write_arg=$(bash_json 'python3 -c '"'"'open("out.w","w").write(x)'"'"'')
py_pathlib=$(bash_json 'python3 -c '"'"'print(Path("app.py").read_text())'"'"'')
py_mode_kw=$(bash_json 'python3 -c '"'"'open("notes.txt", mode="a").write(x)'"'"'')
check 2 "python3 -c open() on a file whose name starts with a" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_read_arg}}"
check 2 "python3 -c open() in write mode: not a read, but off the allowlist" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_write_arg}}"
check 2 "python3 -c pathlib read_text()" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_pathlib}}"
check 2 "python3 -c open(mode=\"a\") keyword mode: not a read, but off the allowlist" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_mode_kw}}"

# The temp carve-out covers the write target, not the whole command: a source
# under the repository is still a read-dump, whatever the redirect says.
check 2 "bash cat of a source file redirected into temp" \
  '{"tool_name":"Bash","tool_input":{"command":"cat src/lib.rs > /tmp/out.txt"}}'
check 2 "bash cp of a source file into temp" \
  '{"tool_name":"Bash","tool_input":{"command":"cp src/lib.rs /tmp/"}}'
check 0 "bash echo into temp stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"echo hi > /tmp/out.txt"}}'

# Tree scanners dump the working tree with no path operand at all.
check 2 "bash rg with no path operand" \
  '{"tool_name":"Bash","tool_input":{"command":"rg TODO"}}'
check 2 "bash grep -rn with no path operand" \
  '{"tool_name":"Bash","tool_input":{"command":"grep -rn TODO"}}'
check 0 "bash bare grep on stdin" \
  '{"tool_name":"Bash","tool_input":{"command":"grep TODO"}}'
CLAUDE_1337_BASH_ALLOW=ps check 0 "bash grep as a pipeline filter" \
  '{"tool_name":"Bash","tool_input":{"command":"ps aux | grep claude"}}'
check 0 "bash grep filtering git output" \
  '{"tool_name":"Bash","tool_input":{"command":"git log | grep fix"}}'
check 0 "bash ripwire piped into head" \
  '{"tool_name":"Bash","tool_input":{"command":"ripwire . --for=x | head"}}'


# Pipeline segmentation, pinned. The walk over every segment, keeping which
# separator fed it, is the thing under these cases: a first-word test plus a
# count of the whole command's operands passes all of the above and still lets
# every one of the five below through.
# A reader anywhere in the command, not only at the head: a first-word test
# sees `cd` here and never looks at the second segment.
check 2 "bash reader in the second segment of an &&-chain" \
  '{"tool_name":"Bash","tool_input":{"command":"cd src && cat lib.rs"}}'
# `;` is not a pipe: the scanner after it reads the tree, it does not filter
# anyone's stdout, so the pipeline carve-out must not reach it.
check 2 "bash tree scanner after a semicolon" \
  '{"tool_name":"Bash","tool_input":{"command":"true; rg TODO"}}'
# -r walks the tree from the working directory even in a pipeline stage, so
# "it is piped, therefore it is only a filter" is not sound.
CLAUDE_1337_BASH_ALLOW=ps check 2 "bash recursive grep as a pipeline stage" \
  '{"tool_name":"Bash","tool_input":{"command":"ps aux | grep -r TODO"}}'
# A pipeline stage can still name a file operand of its own; the operand count
# has to be per segment, not over the whole command.
check 2 "bash pipeline stage with its own file operand" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x | sed -n '1,80p' src/lib.rs\"}}"
# A reader after `;` is its own command with its own operands, not a filter on
# what `ls` printed.
check 2 "bash reader after a semicolon" \
  '{"tool_name":"Bash","tool_input":{"command":"ls; head -50 README.md"}}'

# The other direction, so none of the five above can be satisfied by refusing
# every pipeline: a segment fed by `|` with no file operand of its own really
# is just a filter on another command's stdout.
CLAUDE_1337_BASH_ALLOW=ps check 0 "bash grep filtering ps output stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"ps aux | grep foo"}}'
check 0 "bash grep filtering git log output stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git log --oneline | grep fix"}}'
# Refused for the `cat`, which dumps the file, not for the `grep`, which only
# counts lines on stdin.
check 2 "bash cat into a counting grep, refused for the cat" \
  '{"tool_name":"Bash","tool_input":{"command":"cat f | grep -c line"}}'

# Quoted text is data, not commands. The walk above splits on `;`, `|`, `&&`
# and `||`, so before masking a commit message or an echo that merely NAMED a
# refused command parsed as one: `git commit -m "... cd src && cat lib.rs ..."`
# was refused for a `cat` that runs nothing.
qcommit=$(bash_json 'cd /repo && git add hooks/orchestrator-guard.sh && git commit -q -m "x" -m "pins cd src && cat lib.rs among the bypasses"')
check 0 "bash commit message naming a refused command" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$qcommit}}"
check 0 "bash echo naming cat inside quotes" \
  '{"tool_name":"Bash","tool_input":{"command":"echo \"run cat file to check\""}}'
check 0 "bash echo with a semicolon and a reader inside quotes" \
  '{"tool_name":"Bash","tool_input":{"command":"echo \"step one; head -5 notes\""}}'
check 0 "bash grep pattern containing a semicolon" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep 'foo;bar' /tmp/x.txt\"}}"
check 0 "bash commit message containing a pipe and a tree scanner" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"pipe: ps aux | grep -r TODO\""}}'
# Masking one span disarms that span only: everything outside quotes still
# parses as it did, on the same line.
check 2 "bash quoted string followed by a real reader" \
  '{"tool_name":"Bash","tool_input":{"command":"echo \"hi\" && cat src/lib.rs"}}'
check 2 "bash reader with a quoted path operand" \
  '{"tool_name":"Bash","tool_input":{"command":"cat \"src/lib.rs\""}}'
# The span keeps its path characters, so a quoted scratch operand is still
# recognised as the session's own output.
check 0 "bash reader with a quoted temp-dir operand" \
  '{"tool_name":"Bash","tool_input":{"command":"cat \"/tmp/my file.json\""}}'
# An unterminated quote is parsed as commands, not masked away: refusing more
# than the shell would is the safe direction, failing open is not.
check 2 "bash unterminated quote after a reader" \
  '{"tool_name":"Bash","tool_input":{"command":"cd src && cat lib.rs \"oops"}}'
# A backslash-escaped quote does not end the span: the whole message is data.
esc_q=$(bash_json 'cd . && git commit -m "he said \"cat file; head -3 x\" once"')
check 0 "bash escaped quote inside a quoted message" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$esc_q}}"
# A single quote inside double quotes is data; a double quote inside single
# quotes likewise, and neither may swallow the rest of the command.
mixed_q=$(bash_json 'cd . && echo "it'"'"'s cat lib.rs; head -5 f"')
check 0 "bash apostrophe inside a double-quoted message" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$mixed_q}}"
mixed_r=$(bash_json 'grep '"'"'a"b'"'"' src/lib.rs && cat src/lib.rs')
check 2 "bash double quote inside a single-quoted pattern, reader after it" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$mixed_r}}"
# Command substitution IS executed, so it is never masked: a separator inside
# `$( )` still starts a segment of its own.
sub_read=$(bash_json 'echo "$(true; cat src/lib.rs)"')
check 2 "bash reader inside a command substitution in quotes" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$sub_read}}"
# Masking must not blind the inline-interpreter rule, which reads heredoc
# bodies: quotes and separators in the body change nothing about the open().
py_body=$(bash_json "$(printf 'python3 - <<%s\nprint(\"x; cat y\")\nopen(%ssecret.txt%s)\nEOF' "'EOF'" "'" "'")")
check 2 "python3 heredoc body with quotes and separators is still read" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_body}}"

# The Bash allowlist (#659). The write rule used to be a denylist of write
# patterns; every form below got past it. Each segment's first word must now
# be on the allowlist, so these are refused whatever they write to.
check_err() { # expected-exit stderr-fragment description payload
  local got err
  err=$(printf '%s' "$4" | "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$1" ] && { [ "$1" -eq 0 ] || printf '%s' "$err" | grep -qF -- "$2"; }; then
    printf 'ok   %s\n' "$3"
  else
    printf 'FAIL %s (exit %s, want %s; %s)\n' "$3" "$got" "$1" "$(printf '%s' "$err" | head -1)"; fail=1
  fi
}
bash_payload() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(bash_json "$1")"; }
allow_err="is not on the main-session allowlist"
for c in 'cp /tmp/x.py src/x.py' 'mv /tmp/x.py src/x.py' 'rm -rf src' 'patch -p1 < /tmp/x.diff' \
  'git apply /tmp/x.diff' 'curl -o src/x.py https://example.com/x' "bash -c 'echo hi > a.txt'" \
  "$(printf "cat <<'EOF' | python3\nprint(1)\nEOF")" "$(printf "uv run - <<'EOF'\nprint(1)\nEOF")" \
  "$(printf "python3 -c 'import os\nos.remove(\"a\")\nprint(1)'")" 'git checkout -- src/a.py' 'git reset --hard' \
  'echo $(rm -rf src)' 'echo `rm -rf src`' 'PATH=/tmp/evil:$PATH ls' "git -c core.pager='sh -c x' log" \
  "git log | sed 's/x/y/e'" "sed -n 'w out.txt' /tmp/in.txt" "awk 'BEGIN { system(\"rm -rf src\") }'" \
  'find /tmp/claude-1000/s -delete' 'git config user.name x' 'make test'; do
  check_err 2 "$allow_err" "refused by the allowlist: $(printf '%s' "$c" | head -1)" "$(bash_payload "$c")"
done
# The segment that failed is named in the refusal.
check_err 2 'Bash segment `rm -rf src`' "refusal names the segment" "$(bash_payload 'git status && rm -rf src')"
check_err 2 'CLAUDE_1337_BASH_ALLOW' "refusal names the extension variable" "$(bash_payload 'make test')"
CLAUDE_1337_BASH_ALLOW="make cargo" check 0 "CLAUDE_1337_BASH_ALLOW=make allows make test" "$(bash_payload 'make test')"
CLAUDE_1337_BASH_ALLOW="make cargo" check 0 "CLAUDE_1337_BASH_ALLOW takes several words" "$(bash_payload 'cargo test && make')"

# Quoted text and heredoc bodies are data; redirects are judged per target.
check 0 "a > inside a quoted commit message is not a redirect" "$(bash_payload 'git commit -m "fix: a > b"')"
check 0 "git status 2>/dev/null" "$(bash_payload 'git status 2>/dev/null')"
check 0 "echo into a data file under /tmp" "$(bash_payload 'echo x > /tmp/n.txt')"
check_err 2 "writes a code file" "echo into a code file under /tmp" "$(bash_payload 'echo x > /tmp/n.py')"
check_err 2 "Bash command writes files" "echo into the tree" "$(bash_payload 'echo x > src/a.txt')"
check_err 2 "Bash command writes files" "tee into the tree" "$(bash_payload 'echo x | tee src/a.txt')"
check_err 2 "Bash command writes files" "git diff --output into the tree" "$(bash_payload 'git diff --output=src/d.txt')"
check_err 2 "unexpanded variable" "a variable target that is not a temp path" "$(bash_payload 'S=src; echo x > $S/a.txt')"

# #726: a leading `cd`/`pushd` sets the effective directory a later relative
# redirect target in the same command resolves against, instead of judging
# it against the hook's own cwd.
check 0 "cd into the data allowlist, then a relative append" \
  "$(bash_payload 'cd ~/.claude/projects/x && echo a >> notes.md')"
check 0 "cd into the data allowlist by absolute path, then a relative append" \
  "$(bash_payload "cd $HOME/.claude/projects/x && echo a >> notes.md")"
check 0 "cd /tmp, then a relative redirect" "$(bash_payload 'cd /tmp && echo a > out.json')"
check_err 2 "writes a code file" "cd /tmp, then a relative redirect to a code file is still refused" \
  "$(bash_payload 'cd /tmp && echo a > run.sh')"
check_err 2 "outside the data allowlist" "cd off the data allowlist under ~/.claude is still refused" \
  "$(bash_payload 'cd ~/.claude/plugins && echo a > x.json')"
check_err 2 "Bash command writes files" "cd to an unresolved variable leaves the target judged as today" \
  "$(bash_payload 'cd "$SOMEVAR" && echo a > f.md')"
check 0 "cd .. walks back up the tracked directory lexically" \
  "$(bash_payload 'cd ~/.claude/projects/x && cd .. && echo a > f.md')"
check_err 2 "Bash command writes files" "a cd inside a ( ) group does not carry to the rest of the command" \
  "$(bash_payload '(cd /tmp) && echo a > f.md')"
check_err 2 "Bash command writes files" "no cd at all: a plain relative redirect is unaffected" \
  "$(bash_payload 'echo a > f.md')"
# The directory carries only across &&: after ; || | & or a newline the cd
# may have failed or run in a subshell, so the shell may still be in the repo.
for c in 'cd /tmp/nope; echo x > README.md' 'cd /tmp || true; echo x > README.md' \
  'cd /tmp | echo x > README.md' 'cd /tmp & echo x > README.md' 'cd /tmp && true; echo x > README.md' \
  "$(printf 'cd /tmp\necho x > README.md')" 'true || cd /tmp && echo x > README.md' \
  '! cd /tmp && echo x > README.md' 'echo | cd /tmp && echo x > README.md' \
  'cd /tmp && (true) && echo x > README.md' 'cd /tmp > README.md'; do
  check_err 2 "Bash command writes files" "the cd does not carry: $(printf '%s' "$c" | tr '\n' ' ')" "$(bash_payload "$c")"
done
check 0 "an unbroken && chain keeps the cd directory" \
  "$(bash_payload 'cd /tmp && echo a > a.json && echo b > b.json')"
check 0 "a substitution inside the chain does not break it" \
  "$(bash_payload 'cd /tmp && echo $(date) > a.json')"

# hooks/lib/tokenize.sh reports each segment's ending operator (tok_sep) and
# nesting depth (tok_depth).
tok_seps() ( # command -> "words:sep:depth" per segment, space separated, a substitution placeholder as @
  . "$(dirname "$HOOK")/lib/tokenize.sh"
  out=""
  while IFS= read -r rec; do
    case "$rec" in "S$TOK_US"*) ;; *) continue ;; esac
    tok_parse "$rec"
    w="${tok_words[*]}"
    out="$out ${w//$TOK_PH/@}:$tok_sep:$tok_depth"
  done < <(printf '%s\n' "$1" | tokenize)
  printf '%s' "${out# }"
)
tok_case() { # expected command
  local got desc
  got=$(tok_seps "$2"); desc=$(printf '%s' "$2" | tr '\n' ' ')
  if [ "$got" = "$1" ]; then printf 'ok   tok_sep/tok_depth: %s\n' "$desc"; else printf 'FAIL tok_sep/tok_depth: %s (got %s, want %s)\n' "$desc" "$got" "$1"; fail=1; fi
}
tok_case 'a:&&:0 b:||:0 c:;:0 d:|:0 e:&:0 f::0' 'a && b || c; d | e & f'
tok_case 'a:nl:0 b:|:0 c::0' "$(printf 'a\nb |& c')"
tok_case 'x:;:1 y::1 z::1 echo @ @::0' 'echo $(x; y) `z`'
tok_case 'a:(:0 b:&&:1 c:):1 d::0' 'a ( b && c ) && d'
tok_case 'x::1 cat @::0' 'cat <(x)'

check 0 "a heredoc body naming rm -rf is data for git commit -F -" \
  "$(bash_payload "$(printf "git commit -q -F - <<'EOF'\nclean up: rm -rf build\nEOF")")"
check 0 "a multi-line quoted commit message is one word" \
  "$(bash_payload "$(printf 'git commit -m "line one\nline two; rm -rf x"')")"

# #704: `$(< file)` (and its backtick/assignment equivalents) is a
# command-substitution segment with no command word at all, so it slipped
# past the reader detection above, which only runs when there is one.
check_err 2 "reads a file's contents via \$(< file)" '$(< file) dumps the file' \
  "$(bash_payload 'echo $(< hooks/evaluate.md)')"
check_err 2 "reads a file's contents via \$(< file)" 'backtick < file) dumps the file' \
  "$(bash_payload 'echo `< hooks/evaluate.md`')"
check_err 2 "reads a file's contents via \$(< file)" 'a variable assigned from $(< file) dumps the file' \
  "$(bash_payload 'x=$(< hooks/evaluate.md); echo $x')"
check 0 "\$(< /dev/null) stays allowed" "$(bash_payload 'echo $(< /dev/null)')"
# #720: a scratch-path target gets the same treatment via $(< file) as it
# does for `cat` (line ~329: "bash cat under /tmp stays allowed").
check 0 "\$(< /tmp/x) under a scratch path stays allowed" "$(bash_payload 'echo $(< /tmp/x)')"
check_err 2 "unquoted heredoc body" "a command substitution in an unquoted heredoc body" \
  "$(bash_payload "$(printf 'cat <<EOF\n$(rm -rf src)\nEOF')")"
check 0 "arithmetic << is not a heredoc" "$(bash_payload 'echo $((1 << 2))')"
check_err 2 "$allow_err" "arithmetic << does not swallow the next line" \
  "$(bash_payload "$(printf 'echo $((1 << 2))\nrm -rf src')")"
check_err 2 "reads a file's contents via cat" "an input redirect from a tree file is a read" "$(bash_payload 'cat < src/lib.rs')"

# mktemp creates a file where -p/--tmpdir points: judged like any target.
for c in 'mktemp -p src' 'mktemp -psrc' 'mktemp --tmpdir=src' 'mktemp --tmpdir src' 'mktemp src/x.XXXX' 'mktemp -p /tmp/../repo'; do
  check_err 2 "Bash command writes files" "mktemp into the tree: $c" "$(bash_payload "$c")"
done
for c in 'mktemp -d' 'mktemp' 'mktemp -p /tmp' 'mktemp -d -p "$TMPDIR" x.XXXX' 'mktemp -t x.XXXX' 'mktemp --tmpdir=/tmp x.XXXX'; do
  check 0 "mktemp into temp: $c" "$(bash_payload "$c")"
done

# The forms the orchestrator session itself runs stay allowed.
check 0 "orchestrator commit-and-push chain" \
  "$(bash_payload 'cd /home/x/repo && git add a b && git commit -q -F /tmp/claude-1000/s/msg.txt && git push -q origin main && git log --oneline -1')"
check 0 "two git diffs in one chain" "$(bash_payload 'git diff --stat && git diff hooks/x.sh')"
check 0 "the tier router, repo-relative" "$(bash_payload 'python3 skills/tier/route.py /tmp/claude-1000/s/steps.json')"
check 0 "the tier router through CLAUDE_PLUGIN_ROOT" \
  "$(bash_payload 'python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" /tmp/claude-1000/s/steps.json')"
check 0 "the tier router through CLAUDE_PLUGIN_ROOT, stdin heredoc (the documented form)" \
  "$(bash_payload "$(printf 'python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <<'"'"'EOF'"'"'\n{\"task\":\"t\",\"steps\":[]}\nEOF')")"
check 0 "the visual generator by its absolute path" \
  "$(bash_payload "python3 $(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/skills/visual/generate.py --model x")"
check 2 "a route.py outside the plugin is not the tier router" "$(bash_payload 'python3 /tmp/skills/tier/route.py')"
check 0 "git status --short" "$(bash_payload 'git status --short')"
check 0 "the test runner" "$(bash_payload 'bash tests/run-all.sh 2>&1 | tail -5')"
check 0 "the replay tool" "$(bash_payload 'bash tools/replay.sh /tmp/t.jsonl')"
check 0 "a read-only pipeline" "$(bash_payload 'ls -la | grep x | wc -l')"
check 0 "command -v looks a name up without running it" "$(bash_payload 'command -v rm')"

# Edits count the larger of old and new text; a MultiEdit sums its edits.
old400=$(jq -Rs . <<<"$(printf 'old %s\n' $(seq 1 400))")
check 2 "an Edit replacing 400 lines with 2 counts the 400" \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/repo/a.py\",\"old_string\":$old400,\"new_string\":\"a\\nb\"}}"
body12=$(jq -Rs . <<<"$(printf 'line\n%.0s' $(seq 1 12))")
check 2 "a MultiEdit of two 12-line edits sums to 24" \
  "{\"tool_name\":\"MultiEdit\",\"tool_input\":{\"file_path\":\"/repo/a.py\",\"edits\":[{\"old_string\":\"a\",\"new_string\":$body12},{\"old_string\":\"b\",\"new_string\":$body12}]}}"
CLAUDE_1337_MAX_LINES=40 CLAUDE_1337_EDIT_CAP=0 check 0 "CLAUDE_1337_MAX_LINES raises the edit limit" \
  "{\"tool_name\":\"MultiEdit\",\"tool_input\":{\"file_path\":\"/repo/a.py\",\"edits\":[{\"old_string\":\"a\",\"new_string\":$body12},{\"old_string\":\"b\",\"new_string\":$body12}]}}"
check_err 2 "writes a code file" "Write of a code file under /tmp" \
  '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.py","content":"print(1)"}}'
check 0 "Write of a data file under /tmp" \
  '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.json","content":"{}"}}'
check 2 "Write through a .. step out of /tmp" \
  '{"tool_name":"Write","tool_input":{"file_path":"/tmp/../repo/x.txt","content":"x"}}'

# No-op shell builtins as a segment's first word neither read nor write (#704).
check 0 "for/continue over eval dirs" \
  "$(bash_payload 'for d in evals/*/; do n=$(basename $d); [ $n = results ] && continue; printf "%s\n" "$n"; done')"
check 0 "for/break" "$(bash_payload 'for i in 1 2; do break; done')"
check 0 "true" "$(bash_payload 'true')"
check 0 ": (colon no-op)" "$(bash_payload ':')"
check_err 2 "$allow_err" "while read loop over a file is refused (content dump)" \
  "$(bash_payload 'while read l; do echo "$l"; done < hooks/evaluate.md')"
check_err 2 "$allow_err" "read from a file is refused (content dump)" \
  "$(bash_payload 'read l < hooks/evaluate.md; echo "$l"')"
check_err 2 "$allow_err" "continue does not launder a refused segment after it" \
  "$(bash_payload 'continue; rm -rf x')"

# Read-only git subcommands that print metadata, not file contents (#704).
for c in 'git check-ignore -v x' 'git check-attr text x' 'git rev-parse HEAD' 'git merge-base main HEAD' \
  'git for-each-ref' 'git name-rev HEAD' 'git ls-files'; do
  check 0 "read-only git subcommand: $c" "$(bash_payload "$c")"
done

# Branch creation only: `git switch -c`/`--create` and `git checkout -b`,
# never a bare switch/checkout of an existing branch or a force-create.
check 0 "git switch -c" "$(bash_payload 'git switch -c fix/x')"
check 0 "git switch --create" "$(bash_payload 'git switch --create fix/x')"
check 0 "git checkout -b with a start point" "$(bash_payload 'git checkout -b fix/x main')"
check 0 "git switch -c behind git -C" "$(bash_payload 'git -C /some/dir switch -c fix/x')"
check_err 2 "$allow_err" "git switch to an existing branch is refused" "$(bash_payload 'git switch main')"
check_err 2 "$allow_err" "git checkout of an existing branch is refused" "$(bash_payload 'git checkout main')"
check_err 2 "$allow_err" "git checkout -- path is refused" "$(bash_payload 'git checkout -- file.txt')"
check_err 2 "$allow_err" "git switch -C force-create is refused" "$(bash_payload 'git switch -C fix/x')"
check_err 2 "$allow_err" "git checkout -B force-create is refused" "$(bash_payload 'git checkout -B fix/x')"
check_err 2 "$allow_err" "git checkout -f -b is refused" "$(bash_payload 'git checkout -f -b fix/x')"
check_err 2 "$allow_err" "git switch -c --discard-changes is refused" "$(bash_payload 'git switch -c fix/x --discard-changes')"
check_err 2 "$allow_err" "git checkout -b -m is refused" "$(bash_payload 'git checkout -b fix/x -m')"
check_err 2 "$allow_err" "git switch --force-create is refused" "$(bash_payload 'git switch --force-create fix/x')"

# #723: a subagent's Bash calls otherwise pass untouched, except for the one
# shape that can wipe a parallel builder's finished work in the shared tree.
sub_payload() { printf '{"agent_id":"abc","tool_name":"Bash","tool_input":{"command":%s}}' "$(bash_json "$1")"; }
sub_err="Never revert, stash, reset, clean or overwrite"
check_err 2 "$sub_err" "subagent: git checkout -- path is refused" "$(sub_payload 'git checkout -- x')"
check_err 2 "$sub_err" "subagent: git checkout . is refused" "$(sub_payload 'git checkout .')"
check_err 2 "$sub_err" "subagent: git checkout <rev> -- <path> is refused" "$(sub_payload 'git checkout main -- x')"
check_err 2 "$sub_err" "subagent: git restore is refused" "$(sub_payload 'git restore x')"
check_err 2 "$sub_err" "subagent: git reset --hard is refused" "$(sub_payload 'git reset --hard')"
check_err 2 "$sub_err" "subagent: git reset --merge is refused" "$(sub_payload 'git reset --merge')"
check_err 2 "$sub_err" "subagent: git reset --keep is refused" "$(sub_payload 'git reset --keep')"
check_err 2 "$sub_err" "subagent: git stash is refused" "$(sub_payload 'git stash')"
check_err 2 "$sub_err" "subagent: git stash pop is refused" "$(sub_payload 'git stash pop')"
check_err 2 "$sub_err" "subagent: git clean is refused" "$(sub_payload 'git clean -fd')"
check_err 2 "$sub_err" "subagent: git -C . checkout -- x is refused" "$(sub_payload 'git -C . checkout -- x')"

check 0 "subagent: git status is allowed" "$(sub_payload 'git status')"
check 0 "subagent: git diff is allowed" "$(sub_payload 'git diff')"
check 0 "subagent: git stash list is allowed" "$(sub_payload 'git stash list')"
check 0 "subagent: git stash show is allowed" "$(sub_payload 'git stash show')"
check 0 "subagent: git checkout -b feat is allowed" "$(sub_payload 'git checkout -b feat')"
check 0 "subagent: git log is allowed" "$(sub_payload 'git log')"

unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR CLAUDE_1337_ORCHESTRATOR
check 0 "subagent git checkout -- x allowed with orchestrator mode off" "$(sub_payload 'git checkout -- x')"
export CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=true

CLAUDE_1337_SUBAGENT_GIT_GUARD=off check 0 "subagent git checkout -- x allowed with the env switch off" "$(sub_payload 'git checkout -- x')"

# A main-session payload still behaves exactly as before: `git checkout --
# x` (and `.`) stay refused by the allowlist's checkout/switch rule, not by
# the subagent guard, which never runs for a payload with no agent_id.
check_err 2 "$allow_err" "main session: git checkout -- x is still refused by the allowlist" "$(bash_payload 'git checkout -- x')"

# No jq: the guard cannot read the call, so it refuses instead of passing.
nojq_bin="$edit_cap_tmpdir/nojq-bin"
mkdir -p "$nojq_bin" && ln -s "$(command -v bash)" "$nojq_bin/bash"
nojq_err=$(printf '%s' "$(bash_payload 'cat src/lib.rs')" | PATH="$nojq_bin" "$HOOK" 2>&1 >/dev/null)
nojq_exit=$?
if [ "$nojq_exit" -eq 2 ] && printf '%s' "$nojq_err" | grep -q 'jq is missing'; then
  echo "ok   jq missing: refuses with a one-line message"
else
  echo "FAIL jq missing (exit $nojq_exit: $nojq_err)"; fail=1
fi

exit $fail
