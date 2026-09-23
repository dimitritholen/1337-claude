#!/usr/bin/env bash
# SubagentStart hook: injects the compact 1337 rules (hooks/subagent.md) into
# every subagent the session spawns, so the rules reach the workers and not
# only the main session (SessionStart context never reaches subagents).
#
# Scope with CLAUDE_1337_SUBAGENT_MATCHER: an unanchored, case-insensitive
# regex tested against the subagent's agent_type ("explore|general" matches
# either, "^general$" is exact). Unset means inject into every subagent.
# An invalid regex, a missing or unparseable agent_type, or any failure all
# fail OPEN (inject), so scoping never silently drops the rules.
# CLAUDE_1337_SUBAGENT_RULES=0 disables injection entirely.
#
# A read-only agent_type (CLAUDE_1337_SUBAGENT_READONLY, an unanchored,
# case-insensitive regex, default "scout|checker|explore" so it covers
# 1337:scout, 1337:checker, Explore and codebase-memory-scout) gets the
# digest with its "# Work on the minimum" and "# Evaluate the task briefly"
# sections cut by awk, since a read-only worker has nothing to build or
# evaluate for scope. Setting it to an empty string gives nobody the short
# digest. A missing agent_type, an invalid regex, or awk failing or printing
# nothing all fall back to the full file, the same fail-open rule as above.
#
# Output is the hookSpecificOutput JSON form; plain stdout is dropped for
# SubagentStart. Every failure path exits 0 with no output.
set -u

[ "${CLAUDE_1337_SUBAGENT_RULES:-1}" != "0" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

digest_file="$(dirname "$0")/subagent.md"
[ -f "$digest_file" ] || exit 0
digest="$(cat "$digest_file")"

payload="$(cat)"
agent_type=$(printf '%s' "$payload" | jq -r '.agent_type // empty' 2>/dev/null) || agent_type=""

matcher="${CLAUDE_1337_SUBAGENT_MATCHER:-}"
if [ -n "$matcher" ] && [ -n "$agent_type" ]; then
  rc=0
  jq -ne --arg re "$matcher" --arg at "$agent_type" '$at | test($re; "i")' >/dev/null 2>&1 || rc=$?
  # rc 1 = definite non-match: skip. rc 0 = match, rc 5 = invalid regex:
  # both fail open and inject.
  [ "$rc" -eq 1 ] && exit 0
fi

readonly_re="${CLAUDE_1337_SUBAGENT_READONLY-scout|checker|explore}"
if [ -n "$readonly_re" ] && [ -n "$agent_type" ]; then
  rc=0
  jq -ne --arg re "$readonly_re" --arg at "$agent_type" '$at | test($re; "i")' >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    short=$(awk '
      /^# / {
        if ($0 == "# Work on the minimum" || $0 == "# Evaluate the task briefly") { skip=1; next }
        skip=0
      }
      skip { next }
      { print }
    ' "$digest_file" 2>/dev/null)
    arc=$?
    [ "$arc" -eq 0 ] && [ -n "$short" ] && digest="$short"
  fi
fi

jq -n --arg ctx "$digest" \
  '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $ctx}}'
exit 0
