#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit|Bash, active only in
# orchestrator mode (plugin option `orchestrator`, or CLAUDE_1337_ORCHESTRATOR=1).
# Keeps the main session an orchestrator: subagent calls (payload carries
# agent_id) always pass; the main session may make edits of <= MAX_LINES new
# lines and write under ~/.claude or a temp dir. Bash commands that write
# files (redirects, tee, sed -i) are refused the same way — the default
# "create a file" path is a Bash redirect, not Write. A bare heredoc only
# feeds stdin and passes; `cat <<EOF > file` is caught by its redirect.
# Everything else is refused with a pointer to 1337:builder.
#
# With --rules it prints hooks/orchestrator.md instead (SessionStart), under the same
# on/off condition.
#
# Exit 2 + stderr refuses; exit 0 allows. Every failure path exits 0.
# 1337: later: Bash cp/mv/rm/mkdir from the main session still write the tree;
# add those to the write-patterns if that loophole gets used in practice.
set -u

MAX_LINES=20

[ "${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-false}" = "true" ] || [ "${CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || exit 0

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

[ "${lines:-0}" -le "$MAX_LINES" ] && exit 0

printf 'blocked (1337 orchestrator mode): %s on %s is more than %d lines. Dispatch it to 1337:builder with a self-contained brief.\n' \
  "$tool" "$file" "$MAX_LINES" >&2
exit 2
