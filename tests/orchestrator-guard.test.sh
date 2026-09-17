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
"$HOOK" --rules | grep -q '^# Orchestrator mode' && echo "ok   mode on: rules printed" || { echo "FAIL mode on: rules missing"; fail=1; }

unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR
CLAUDE_1337_ORCHESTRATOR=1 check 2 "env switch turns mode on" "$write"

exit $fail
