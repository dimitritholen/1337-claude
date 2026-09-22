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
  '{"tool_name":"Bash","tool_input":{"command":"echo todo 2>/dev/null"}}'
check 0 "bash redirect into temp dir" \
  '{"tool_name":"Bash","tool_input":{"command":"seq 1 40 > /tmp/claude-501/scratch/f.txt"}}'
check 0 "bash read-only command" \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la /repo"}}'
check 0 "bash from subagent" \
  '{"agent_id":"abc","tool_name":"Bash","tool_input":{"command":"printf \"a\" > /repo/big.txt"}}'
check 2 "bash piped grep, no redirect, cat still dumps the file" \
  '{"tool_name":"Bash","tool_input":{"command":"cat /repo/f.txt | grep -c line"}}'
check 0 "bash piped grep, filter only, no file operand" \
  '{"tool_name":"Bash","tool_input":{"command":"ps aux | grep foo"}}'
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
check 0 "python3 heredoc body writes via open(), pinned to current behaviour" \
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
  "{\"session_id\":\"ecap-$$-a\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/x\",\"content\":\"x\"}}"

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
check 0 "bash grep filters a pipe, no file operand" \
  '{"tool_name":"Bash","tool_input":{"command":"ps aux | grep foo"}}'
check 2 "bash grep -r over a directory" \
  '{"tool_name":"Bash","tool_input":{"command":"grep -r pattern src/"}}'
check 0 "bash git diff stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff"}}'
check 0 "bash git diff with revision and path stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff HEAD~1 -- src/lib.rs"}}'
check 0 "bash git diff --stat stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff --stat"}}'
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
check 0 "bash ripwire stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"ripwire . --for=\"x\""}}'
py_read=$(printf "python3 - <<'EOF'\nopen('secret.txt')\nEOF")
py_readjson=$(jq -Rs . <<<"$py_read")
check 2 "python3 heredoc containing open( is a read" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_readjson}}"
check 0 "bash read-dump command from a subagent still passes" \
  '{"agent_id":"abc","tool_name":"Bash","tool_input":{"command":"cat /repo/f.txt"}}'

# The mode of an inline open() is its own argument, after a comma: a filename
# starting with w, a or x is still a read.
bash_json() { jq -Rs . <<<"$1"; }
py_read_arg=$(bash_json 'python3 -c '"'"'print(open("app.py").read())'"'"'')
py_write_arg=$(bash_json 'python3 -c '"'"'open("out.w","w").write(x)'"'"'')
py_pathlib=$(bash_json 'python3 -c '"'"'print(Path("app.py").read_text())'"'"'')
py_mode_kw=$(bash_json 'python3 -c '"'"'open("notes.txt", mode="a").write(x)'"'"'')
check 2 "python3 -c open() on a file whose name starts with a" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_read_arg}}"
check 0 "python3 -c open() in write mode, filename starting with o" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_write_arg}}"
check 2 "python3 -c pathlib read_text()" \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$py_pathlib}}"
check 0 "python3 -c open(mode=\"a\") keyword mode" \
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
check 0 "bash grep as a pipeline filter" \
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
check 2 "bash recursive grep as a pipeline stage" \
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
check 0 "bash grep filtering ps output stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"ps aux | grep foo"}}'
check 0 "bash grep filtering git log output stays allowed" \
  '{"tool_name":"Bash","tool_input":{"command":"git log --oneline | grep fix"}}'
# Refused for the `cat`, which dumps the file, not for the `grep`, which only
# counts lines on stdin.
check 2 "bash cat into a counting grep, refused for the cat" \
  '{"tool_name":"Bash","tool_input":{"command":"cat f | grep -c line"}}'

exit $fail
