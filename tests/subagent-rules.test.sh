#!/usr/bin/env bash
# Tests for hooks/subagent-rules.sh: feeds crafted SubagentStart payloads and
# asserts what comes back on stdout. Inject = JSON with additionalContext;
# skip = empty stdout, exit 0.
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/subagent-rules.sh"
fail=0

check() { # inject|skip description agent_type matcher-env
  local got out
  out=$(printf '{"session_id":"t","agent_type":"%s"}' "$3" | \
    env ${4:+CLAUDE_1337_SUBAGENT_MATCHER="$4"} "$HOOK" 2>/dev/null)
  if [ "$1" = inject ]; then
    if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart"
        and (.hookSpecificOutput.additionalContext | test("1337"))' >/dev/null 2>&1; then
      printf 'ok   %s\n' "$2"
    else
      printf 'FAIL %s (no valid injection)\n' "$2"; fail=1
    fi
  else
    [ -z "$out" ] && printf 'ok   %s\n' "$2" || { printf 'FAIL %s (unexpected output)\n' "$2"; fail=1; }
  fi
}

unset CLAUDE_1337_SUBAGENT_MATCHER CLAUDE_1337_SUBAGENT_RULES

check inject "no matcher: injects into every subagent" "general-purpose" ""
check inject "matcher match: injects" "general-purpose" "general"
check skip "matcher non-match: skips" "general-purpose" "^explore$"
check inject "matcher is unanchored and case-insensitive" "Explore" "explore"
check inject "invalid regex: fails open" "general-purpose" "([unclosed"
check inject "matcher set but no agent_type: fails open" "" "general"

# Disabled env check needs its own env, the helper cannot express it.
out=$(printf '{"session_id":"t","agent_type":"general-purpose"}' | \
  CLAUDE_1337_SUBAGENT_RULES=0 "$HOOK" 2>/dev/null)
[ -z "$out" ] && printf 'ok   disable env wins over everything\n' || { printf 'FAIL disable env\n'; fail=1; }

exit $fail
