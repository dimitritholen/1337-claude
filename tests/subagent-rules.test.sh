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

# The injected digest carries the ripwire-first rule (WOR: ripwire named in
# hooks/subagent.md so every subagent type hears it, not just scout/builder).
if grep -q 'ripwire' "$(dirname "$HOOK")/subagent.md"; then
  printf 'ok   hooks/subagent.md carries the ripwire rule\n'
else
  printf 'FAIL hooks/subagent.md missing the ripwire rule\n'; fail=1
fi

# Disabled env check needs its own env, the helper cannot express it.
out=$(printf '{"session_id":"t","agent_type":"general-purpose"}' | \
  CLAUDE_1337_SUBAGENT_RULES=0 "$HOOK" 2>/dev/null)
[ -z "$out" ] && printf 'ok   disable env wins over everything\n' || { printf 'FAIL disable env\n'; fail=1; }

# hooks/subagent.md carries the new ripwire-expand/git-diff sentence.
if grep -qF -- 'Once ripwire has named the' "$(dirname "$HOOK")/subagent.md" && \
    grep -qF -- 'never by reading the whole file' "$(dirname "$HOOK")/subagent.md"; then
  printf 'ok   hooks/subagent.md carries the expand/git-diff sentence\n'
else
  printf 'FAIL hooks/subagent.md missing the expand/git-diff sentence\n'; fail=1
fi

digest() { # agent_type [readonly-env]
  printf '{"session_id":"t","agent_type":"%s"}' "$1" | \
    env ${2+CLAUDE_1337_SUBAGENT_READONLY="$2"} "$HOOK" 2>/dev/null | \
    jq -r '.hookSpecificOutput.additionalContext'
}

headings_check() { # description agent_type readonly-env(unset marker "-") want-short(1|0)
  local desc="$1" at="$2" renv="$3" short="$4" out kept cut ok=1
  if [ "$renv" = "-" ]; then
    out=$(digest "$at")
  else
    out=$(digest "$at" "$renv")
  fi
  for kept in 'Locate before opening' 'Name your assumptions' 'Reply tight'; do
    printf '%s' "$out" | grep -qF "# $kept" || ok=0
  done
  if [ "$short" = 1 ]; then
    for cut in 'Work on the minimum' 'Evaluate the task briefly'; do
      printf '%s' "$out" | grep -qF "# $cut" && ok=0
    done
  else
    for cut in 'Work on the minimum' 'Evaluate the task briefly'; do
      printf '%s' "$out" | grep -qF "# $cut" || ok=0
    done
  fi
  if [ "$ok" = 1 ]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n' "$desc"; fail=1
  fi
}

unset CLAUDE_1337_SUBAGENT_READONLY
headings_check "checker gets the short digest (default READONLY)" "checker" - 1
headings_check "scout gets the short digest (default READONLY)" "1337:scout" - 1
headings_check "Explore gets the short digest (default READONLY)" "Explore" - 1
headings_check "builder gets all five sections" "builder" - 0
headings_check "general-purpose gets all five sections" "general-purpose" - 0
headings_check "missing agent_type gets all five sections" "" - 0
headings_check "READONLY='' gives checker the full file" "checker" "" 0
headings_check "invalid READONLY regex falls back to the full file" "checker" "([unclosed" 0
headings_check "custom READONLY regex is applied" "builder" "builder" 1

exit $fail
