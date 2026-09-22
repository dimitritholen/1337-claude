#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit|Bash, active only in
# orchestrator mode (plugin option `orchestrator`, or CLAUDE_1337_ORCHESTRATOR=1).
# Keeps the main session an orchestrator: subagent calls (payload carries
# agent_id) always pass; the main session may make edits of <= MAX_LINES new
# lines and write under ~/.claude or a temp dir. Bash commands that write
# files (redirects, tee, sed -i) are refused the same way — the default
# "create a file" path is a Bash redirect, not Write. A bare heredoc only
# feeds stdin and passes; `cat <<EOF > file` is caught by its redirect.
# Heredoc bodies fed to anything but an interpreter are data, not commands:
# they are stripped from the text before the write-pattern greps run, so a
# commit message body mentioning `sed -i` or `> file.py` is not mistaken for
# one. Everything else is refused with a pointer to 1337:builder.
#
# With --rules it prints hooks/orchestrator.md instead (SessionStart), under the same
# on/off condition.
#
# EVAL_CLAUDE_1337_ORCHESTRATOR=1 is the switch eval cases use, since `claude plugin
# eval` cases may only set EVAL_* variables.
#
# Exit 2 + stderr refuses; exit 0 allows. Every failure path exits 0.
# 1337: later: Bash cp/mv/rm/mkdir from the main session still write the tree;
# add those to the write-patterns if that loophole gets used in practice.
set -u

MAX_LINES=20

[ "${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-false}" = "true" ] || [ "${CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || [ "${EVAL_CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || exit 0

if [ "${1:-}" = "--rules" ]; then
  cat "$(dirname "$0")/orchestrator.md"
  exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"

agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
[ -n "$agent_id" ] && exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || exit 0

case "$file" in
  "$HOME"/.claude/*|/tmp/*|/private/tmp/*|/var/folders/*) exit 0 ;;
esac

case "$tool" in
  Bash)
    bash_cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    [ -n "$bash_cmd" ] || exit 0
    clean=$(printf '%s\n' "$bash_cmd" | sed -e 's#[0-9]*&\?>[[:space:]]*/dev/null##g' -e 's#[0-9]*>&1##g')
    # Strip the bodies of heredocs whose consumer is not an interpreter
    # before the write-pattern greps run below: such a body is data (a
    # commit message, a here-doc payload for `cat > file`), not shell text,
    # so mentions of `sed -i` or `> foo.py` inside it must not trip the
    # regexes. The opener line is kept so `cat <<EOF > out.py` and
    # `tee out.py <<EOF` are still caught by their own redirect/tee match.
    # Bodies consumed by an interpreter (`bash <<EOF`, `python3 - <<EOF`)
    # are left in place, unchanged from today's scan.
    clean=$(printf '%s\n' "$clean" | awk '
      function is_interp(t) {
        return (t=="python"||t=="python3"||t=="python2"||t=="node"||t=="bash"||t=="sh"||t=="zsh"||t=="dash"||t=="ruby"||t=="perl"||t=="php"||t=="deno"||t=="bun"||t=="osascript")
      }
      BEGIN { in_body=0 }
      {
        line=$0
        if (!in_body) {
          print line
          if (match(line, /<<-?[ \t]*"?'"'"'?[A-Za-z_][A-Za-z0-9_]*"?'"'"'?/)) {
            seg = substr(line, RSTART, RLENGTH)
            dash = (seg ~ /^<<-/) ? 1 : 0
            marker = seg
            sub(/^<<-?[ \t]*/, "", marker)
            gsub(/["'"'"']/, "", marker)
            prefix = substr(line, 1, RSTART - 1)
            n = split(prefix, toks, /[ \t]+/)
            interp = ""
            interp_idx = 0
            for (i = 1; i <= n; i++) { if (toks[i] != "" && is_interp(toks[i])) { interp = toks[i]; interp_idx = i } }
            if (interp != "") {
              has_file = 0
              for (i = interp_idx + 1; i <= n; i++) { if (toks[i] != "" && toks[i] != "-" && substr(toks[i], 1, 1) != "-") has_file = 1 }
              if (has_file) interp = ""
            }
            cur_marker = marker; cur_dash = dash; cur_interp = interp
            in_body = 1
          }
        } else {
          test_line = line
          if (cur_dash) sub(/^\t+/, "", test_line)
          if (test_line == cur_marker) {
            in_body = 0
            print line
            next
          }
          if (cur_interp != "") print line
        }
      }
    ')
    # Inline scripts piped into an interpreter through a heredoc are builder
    # work past a line limit (CLAUDE_1337_INLINE_LINES, default 20, 0
    # disables). Walk the command line by line: a line carrying `<<`/`<<-`
    # (optionally quoted marker) opens a heredoc body that runs to the line
    # matching the marker (leading tabs stripped for `<<-`). The consumer is
    # counted only when the text before `<<` ends on one of the listed
    # interpreter tokens with nothing after it but flags or a bare `-`
    # (stdin); a real filename argument (`python3 script.py <<EOF`) is left
    # alone as a grey area. `git commit -F - <<EOF` and `cat <<EOF` never
    # match an interpreter token, so they pass regardless of body length.
    inline_limit="${CLAUDE_1337_INLINE_LINES:-20}"
    if [ "$inline_limit" != "0" ]; then
      inline_hit=$(printf '%s\n' "$bash_cmd" | awk -v limit="$inline_limit" '
        function is_interp(t) {
          return (t=="python"||t=="python3"||t=="python2"||t=="node"||t=="bash"||t=="sh"||t=="zsh"||t=="dash"||t=="ruby"||t=="perl"||t=="php"||t=="deno"||t=="bun"||t=="osascript")
        }
        BEGIN { in_body=0 }
        {
          line=$0
          if (!in_body) {
            if (match(line, /<<-?[ \t]*"?'"'"'?[A-Za-z_][A-Za-z0-9_]*"?'"'"'?/)) {
              seg = substr(line, RSTART, RLENGTH)
              dash = (seg ~ /^<<-/) ? 1 : 0
              marker = seg
              sub(/^<<-?[ \t]*/, "", marker)
              gsub(/["'"'"']/, "", marker)
              prefix = substr(line, 1, RSTART - 1)
              n = split(prefix, toks, /[ \t]+/)
              interp = ""
              interp_idx = 0
              for (i = 1; i <= n; i++) { if (toks[i] != "" && is_interp(toks[i])) { interp = toks[i]; interp_idx = i } }
              if (interp != "") {
                has_file = 0
                for (i = interp_idx + 1; i <= n; i++) { if (toks[i] != "" && toks[i] != "-" && substr(toks[i], 1, 1) != "-") has_file = 1 }
                if (has_file) interp = ""
              }
              cur_marker = marker; cur_dash = dash; cur_interp = interp
              body_count = 0
              in_body = 1
              next
            }
          } else {
            test_line = line
            if (cur_dash) sub(/^\t+/, "", test_line)
            if (test_line == cur_marker) {
              in_body = 0
              if (!found && cur_interp != "" && body_count > limit) { print body_count, cur_interp; found = 1 }
              next
            }
            body_count++
          }
        }
      ')
      if [ -n "$inline_hit" ]; then
        body_lines=${inline_hit%% *}
        interp=${inline_hit#* }
        printf 'blocked (1337 orchestrator mode): inline %s-line script piped into %s; scripts over %s lines are builder work. Dispatch it to 1337:builder with a self-contained brief.\n' \
          "$body_lines" "$interp" "$inline_limit" >&2
        exit 2
      fi
    fi
    # Code files are builder work regardless of directory: refuse them even
    # under the temp-dir exemption below. Data files under temp stay allowed.
    code_ext='py|sh|bash|js|mjs|cjs|ts|rb|go|rs|php|pl|lua|html|htm|css'
    # The target may be quoted ("f.py", 'f.py'); sed takes its expression
    # between the -i flag and the file, so skip anything up to the last token.
    if printf '%s\n' "$clean" | grep -qiE "(^|[[:space:];&(])[0-9]*>+[[:space:]]*[\"']?[^[:space:];&|<>]+\\.($code_ext)[\"']?([[:space:];&|]|\$)" \
      || printf '%s\n' "$clean" | grep -qiE "(^|[[:space:];&(])tee([[:space:]]+-[A-Za-z]+)*[[:space:]]+[\"']?[^[:space:];&|<>]+\\.($code_ext)[\"']?([[:space:];&|]|\$)" \
      || printf '%s\n' "$clean" | grep -qiE "sed[[:space:]]+([^;&|]*[[:space:]])?-[A-Za-z]*i[^;&|]*[[:space:]][\"']?[^[:space:];&|<>]+\\.($code_ext)[\"']?([[:space:];&|]|\$)"; then
      printf 'blocked (1337 orchestrator mode): Bash command writes a code file (%.80s). Scripts are builder work even under temp directories; dispatch it to 1337:builder with a self-contained brief.\n' "$bash_cmd" >&2
      exit 2
    fi
    case "$bash_cmd" in
      *"/tmp/"*|*"/private/tmp/"*|*"/var/folders/"*|*".claude/"*) exit 0 ;;
    esac
    if printf '%s\n' "$clean" | grep -qE '(^|[[:space:];&(])tee([[:space:]]|$)|sed[[:space:]]+(-[a-zA-Z]+ )*-i|(^|[[:space:];&(])[0-9]*>+[[:space:]]*[^&>[:space:]]'; then
      printf 'blocked (1337 orchestrator mode): Bash command writes files (%.80s). Dispatch it to 1337:builder with a self-contained brief; the main session may only write under ~/.claude and temp directories.\n' "$bash_cmd" >&2
      exit 2
    fi
    exit 0
    ;;
  Edit)
    lines=$(printf '%s' "$payload" | jq -r '.tool_input.new_string // ""' | awk 'END { print NR }')
    ;;
  MultiEdit)
    lines=$(printf '%s' "$payload" | jq -r '[.tool_input.edits[]?.new_string] | join("\n")' | awk 'END { print NR }')
    ;;
  *)
    printf 'blocked (1337 orchestrator mode): %s on %s writes a whole file, which the main session may not do outside ~/.claude and temp directories. Dispatch it to 1337:builder with a self-contained brief.\n' \
      "$tool" "$file" >&2
    exit 2
    ;;
esac

if [ "${lines:-0}" -le "$MAX_LINES" ]; then
  edit_cap="${CLAUDE_1337_EDIT_CAP:-5}"
  if [ "$edit_cap" != "0" ]; then
    session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
    if [ -n "$session_id" ]; then
      # No lock: parallel small edits from the main session are rare enough
      # that a lost increment here is an acceptable risk.
      edit_state="${TMPDIR:-/tmp}/claude-1337-edit-cap-$session_id"
      printf '%s %s\n' "$tool" "$file" >> "$edit_state" 2>/dev/null || exit 0
      edit_count=$(awk 'END { print NR }' "$edit_state" 2>/dev/null) || exit 0
      if [ "$edit_count" -gt "$edit_cap" ]; then
        printf 'blocked (1337 orchestrator mode): small edit #%d this session (cap %d). Bundle the remaining corrections into one 1337:builder brief. CLAUDE_1337_EDIT_CAP=0 disables.\n' \
          "$edit_count" "$edit_cap" >&2
        exit 2
      fi
    fi
  fi
  exit 0
fi

printf 'blocked (1337 orchestrator mode): %s on %s is more than %d lines. Dispatch it to 1337:builder with a self-contained brief.\n' \
  "$tool" "$file" "$MAX_LINES" >&2
exit 2
