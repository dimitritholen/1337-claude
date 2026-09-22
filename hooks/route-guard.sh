#!/usr/bin/env bash
# PreToolUse hook for Agent|Task, active only in tiered mode (plugin option
# `tiered`, or CLAUDE_1337_TIERED=1). Enforces that every 1337:builder
# dispatch spends a model tier the router actually assigned, instead of a
# hand-picked one.
#
# Scope: only a call with subagent_type "1337:builder" is judged; every
# other agent type, and any payload without a subagent_type, passes. A
# dispatch made by a subagent rather than the main session (payload carries
# agent_id) always passes too: the main session routes, or falls back,
# before it ever calls one — mirrors hooks/orchestrator-guard.sh:97-98 and
# the subagent carve-out in hooks/read-cap.sh.
#
# Evidence: the session transcript (JSONL, at .transcript_path) is scanned
# for the LAST line matching the marker `1337-tier-route: `, printed by
# skills/tier/route.py on stdout (so it lands inside a tool_result of a Bash
# call). What follows the prefix is JSON: {"model":..., "floor":...,
# "steps":[{"id":..,"tier":"sonnet","confidence":..,"escalated":bool}, ...]}.
# Each transcript line is one JSONL entry, so a `grep -n` line number IS
# that entry's position: only the tail after the last marker line is ever
# parsed with jq (task #674 — a 22MB transcript slurped whole into one jq -s
# array cost 0.56s/147MB; grep -n streams the search instead).
#
# No marker anywhere in the transcript means the router never ran this
# session: refused. Otherwise the routed tiers (one per step) form a
# multiset; every 1337:builder dispatch found AFTER that last marker line
# spends one entry (its `model` must match a still-unspent tier, removed
# one-for-one in dispatch order). A dispatch once every routed tier is
# already spent, or whose `model` is not among what remains, is refused. A
# later marker resets the budget: only dispatches after the LAST marker
# count. A marker line whose JSON fails to parse is treated the same as no
# marker at all (refused) — a corrupt or forged marker must not buy a
# dispatch.
#
# Deadlock guard (task #674): skills/tier/route.py exits 3 with no key and 4
# when the API call itself failed; hooks/tiered.md already tells the session
# to size those steps by hand instead of retrying. If the LAST route.py
# invocation this session (a Bash tool_use whose command names
# skills/tier/route.py) is not followed by a valid marker — whether because
# it printed a recognisable `tier-route: ` failure line, or printed nothing
# recognisable at all — that attempt is treated as failed, not routed:
# 1337:builder dispatches are let through with a one-line stderr notice
# instead of refused forever. `CLAUDE_1337_ROUTE_GUARD=off` disables the
# whole hook, same `off` convention as CLAUDE_1337_READ_CAP/GREP_CAP in
# hooks/read-cap.sh.
#
# Mirrors the mode gate of hooks/tiered-rules.sh and hooks/dispatch-nudge.sh
# (same four env switches), and the transcript-parsing/refusal shape of
# hooks/dispatch-nudge.sh and hooks/orchestrator-guard.sh.
#
# This step does not fail open on: no jq, a payload that fails to parse, or
# a payload with no `model` at all (that dispatch is simply refused: with no
# model to compare, it can never be "one of the remaining tiers"). A
# missing/unreadable transcript_path stays silent (this step cannot tell
# "router never ran" from "cannot see the transcript"); an existing, readable
# but empty transcript is NOT the same thing — no marker can be in it, so it
# is refused like any other transcript with no marker.
#
# Exit 2 + stderr refuses; exit 0 allows.
set -u

[ "${CLAUDE_PLUGIN_OPTION_TIERED:-false}" = "true" ] || [ "${CLAUDE_1337_TIERED:-0}" = "1" ] || [ "${EVAL_CLAUDE_1337_TIERED:-0}" = "1" ] || exit 0

# `off` (any case) disables this hook entirely.
guard_lc=$(printf '%s' "${CLAUDE_1337_ROUTE_GUARD:-}" | tr '[:upper:]' '[:lower:]')
[ "$guard_lc" != "off" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"

# A nested dispatch made by a subagent, not the main session, always passes.
agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
[ -n "$agent_id" ] && exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$tool" in
  Agent|Task) ;;
  *) exit 0 ;;
esac

subagent_type=$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0
[ "$subagent_type" = "1337:builder" ] || exit 0

model=$(printf '%s' "$payload" | jq -r '.tool_input.model // empty' 2>/dev/null) || exit 0

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
# A missing/unreadable transcript is one of the #674 fail-open cases: this
# step cannot tell "router never ran" from "cannot see the transcript", so
# it stays silent rather than guessing.
[ -n "$transcript" ] && [ -f "$transcript" ] && [ -r "$transcript" ] || exit 0

MARKER_PREFIX='1337-tier-route: '

# Last file line that could hold a marker, and last file line that could be
# a route.py invocation. `grep -n -F` streams the file; it does not load it.
marker_ln=$(grep -n -F -- "$MARKER_PREFIX" "$transcript" 2>/dev/null | tail -1 | cut -d: -f1)
route_ln=$(grep -n -F -- 'skills/tier/route.py' "$transcript" 2>/dev/null | tail -1 | cut -d: -f1)

# The deadlock guard: the most recent route.py invocation (if any) produced
# no marker after it — refused a valid marker, printed a recognisable
# `tier-route: ` failure, or printed nothing intelligible at all, all count
# the same way here (route.py never prints a marker on a failure path, so
# "no marker after the call" already covers every one of them; a
# `tier-route: ` line, when present, only confirms it).
if [ -n "$route_ln" ] && { [ -z "$marker_ln" ] || [ "$route_ln" -gt "$marker_ln" ]; }; then
  printf '1337 tiered mode: the last tier-router attempt this session did not route (no key, or the call failed) — sizing steps by hand per hooks/tiered.md; 1337:builder dispatch allowed without a routed tier this once.\n' >&2
  exit 0
fi

if [ -z "$marker_ln" ]; then
  printf 'blocked (1337 tiered mode): 1337:builder dispatched with no tier routing this session. Write the steps to a JSON file and run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` once for all of them, then dispatch at the tier it assigns.\n' >&2
  exit 2
fi

# Extract the marker's JSON payload from just that one line: same
# tool_result/text-splitting shape as before, applied to a single entry.
marker_json=$(sed -n "${marker_ln}p" "$transcript" | jq -r --arg mp "$MARKER_PREFIX" '
  def texts_of(entry):
    (entry.message.content? // [])
    | if type == "array" then
        [.[] | select(.type == "tool_result")
          | (.content
              | if type == "string" then .
                elif type == "array" then ([.[]? | select(.type == "text") | .text] | join("\n"))
                else empty end)]
      else [] end;
  ([texts_of(.)[]? | split("\n")[] | select(startswith($mp))] | last // empty)
' 2>/dev/null)
marker_json="${marker_json#"$MARKER_PREFIX"}"

if [ -z "$marker_json" ] || ! printf '%s' "$marker_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
  printf 'blocked (1337 tiered mode): 1337:builder dispatched with no tier routing this session. Write the steps to a JSON file and run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` once for all of them, then dispatch at the tier it assigns.\n' >&2
  exit 2
fi

# Only the tail after the marker line matters: dispatches spend the budget
# in file order, streamed instead of slurped.
dispatched=$(tail -n "+$((marker_ln + 1))" "$transcript" | jq -R 'fromjson? // empty' 2>/dev/null | jq -s '
  [.[] | (.message.content? // [])
    | if type == "array" then .[] else empty end
    | select(.type == "tool_use" and (.name == "Agent" or .name == "Task")
        and ((.input.subagent_type // "") == "1337:builder"))
    | (.input.model // "")]
' 2>/dev/null) || exit 0
[ -n "$dispatched" ] || exit 0

steps_count=$(printf '%s' "$marker_json" | jq -r '.steps | length' 2>/dev/null) || exit 0
dispatch_count=$(printf '%s' "$dispatched" | jq -r 'length' 2>/dev/null) || exit 0
case "$steps_count" in ''|*[!0-9]*) exit 0 ;; esac
case "$dispatch_count" in ''|*[!0-9]*) exit 0 ;; esac

if [ "$dispatch_count" -ge "$steps_count" ]; then
  printf 'blocked (1337 tiered mode): every routed step (%d) already has a 1337:builder dispatch this route. Run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` again before dispatching more.\n' \
    "$steps_count" >&2
  exit 2
fi

# Remaining tiers: the routed multiset minus one entry per dispatch already
# made since the last marker, removed one-for-one in dispatch order.
remaining=$(jq -n --argjson marker "$marker_json" --argjson dispatched "$dispatched" '
  def remove_one(arr; x):
    (arr | index(x)) as $i
    | if $i == null then arr else (arr[0:$i] + arr[$i+1:]) end;
  ([$marker.steps[].tier]) as $routed
  | reduce $dispatched[] as $t ($routed; remove_one(.; $t))
' 2>/dev/null) || exit 0
[ -n "$remaining" ] || exit 0

is_remaining=$(printf '%s' "$remaining" | jq --arg m "$model" 'any(.[]; . == $m)' 2>/dev/null) || exit 0

if [ "$is_remaining" = "true" ]; then
  exit 0
fi

remaining_list=$(printf '%s' "$remaining" | jq -r 'join(", ")' 2>/dev/null) || exit 0
[ -n "$remaining_list" ] || remaining_list="none"

printf 'blocked (1337 tiered mode): 1337:builder dispatched at model %s, not one of the tiers routing still owes this step (%s). Dispatch at one of the remaining tiers, or run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` again to re-route.\n' \
  "${model:-<none>}" "$remaining_list" >&2
exit 2
