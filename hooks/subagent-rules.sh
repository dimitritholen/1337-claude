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

jq -n --arg ctx "$digest" \
  '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $ctx}}'
exit 0
