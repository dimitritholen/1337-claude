#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit, active only in orchestrator
# mode (plugin option `orchestrator`, or CLAUDE_1337_ORCHESTRATOR=1). Keeps the main
# session an orchestrator: subagent calls (payload carries agent_id) always pass; the
# main session may make edits of <= MAX_LINES new lines and write under ~/.claude or
# a temp dir. Everything else is refused with a pointer to 1337:builder.
#
# With --rules it prints hooks/orchestrator.md instead (SessionStart), under the same
# on/off condition.
#
# Exit 2 + stderr refuses; exit 0 allows. Every failure path exits 0.
# 1337: later: Bash (sed, heredocs) can still edit files from the main session;
# add a Bash matcher if that loophole gets used in practice.
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
