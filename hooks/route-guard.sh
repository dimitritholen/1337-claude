#!/usr/bin/env bash
# PreToolUse hook for Agent|Task, active only in tiered mode (plugin option
# `tiered`, or CLAUDE_1337_TIERED=1). Enforces that every 1337:builder
# dispatch spends a model tier the router actually assigned, instead of a
# hand-picked one.
#
# Scope: only a call with subagent_type "1337:builder" is judged; every
# other agent type, and any payload without a subagent_type, passes.
#
# Evidence: the session transcript (JSONL, at .transcript_path) is scanned
# for the LAST line matching the marker `1337-tier-route: `, printed by
# skills/tier/route.py on stdout (so it lands inside a tool_result of a Bash
# call). What follows the prefix is JSON: {"model":..., "floor":...,
# "steps":[{"id":..,"tier":"sonnet","confidence":..,"escalated":bool}, ...]}.
#
# No marker anywhere in the transcript means the router never ran this
# session: refused. Otherwise the routed tiers (one per step) form a
# multiset; every 1337:builder dispatch found AFTER that last marker line
# spends one entry (its `model` must match a still-unspent tier, removed
# one-for-one in dispatch order). A dispatch once every routed tier is
# already spent, or whose `model` is not among what remains, is refused. A
# later marker resets the budget: only dispatches after the LAST marker
# count.
#
# Mirrors the mode gate of hooks/tiered-rules.sh and hooks/dispatch-nudge.sh
# (same four env switches), and the transcript-parsing/refusal shape of
# hooks/dispatch-nudge.sh and hooks/orchestrator-guard.sh.
#
# This step does not fail open on: no OpenRouter/TypeSafe key, a failed
# router call, a missing/unreadable transcript, or an off switch for this
# hook specifically — those are task #674. Every OTHER failure path (no jq,
# a payload that fails to parse, a marker line that fails to parse as JSON)
# exits 0, same as every other hook here.
#
# Exit 2 + stderr refuses; exit 0 allows.
set -u

[ "${CLAUDE_PLUGIN_OPTION_TIERED:-false}" = "true" ] || [ "${CLAUDE_1337_TIERED:-0}" = "1" ] || [ "${EVAL_CLAUDE_1337_TIERED:-0}" = "1" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"

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

result=$(jq -R 'fromjson? // empty' "$transcript" 2>/dev/null | jq -s '
  def texts_of(entry):
    (entry.message.content? // [])
    | if type == "array" then
        [.[] | select(.type == "tool_result")
          | (.content
              | if type == "string" then .
                elif type == "array" then ([.[]? | select(.type == "text") | .text] | join("\n"))
                else empty end)]
      else [] end;
  def agents_of(entry):
    (entry.message.content? // [])
    | if type == "array" then
        [.[] | select(.type == "tool_use" and (.name == "Agent" or .name == "Task")
                and ((.input.subagent_type // "") == "1337:builder"))
          | (.input.model // "")]
      else [] end;
  # One entry per transcript line, in file order, carrying its own index.
  [to_entries[] | {idx: .key, texts: texts_of(.value), agents: agents_of(.value)}] as $entries
  | ([$entries[] | .idx as $i | .texts[] | split("\n")[]
      | select(startswith("1337-tier-route: "))
      | {idx: $i, line: (ltrimstr("1337-tier-route: "))}]) as $markers
  | if ($markers | length) == 0 then
      {found: false}
    else
      ($markers | last) as $last
      | ($last.line | fromjson? // null) as $marker
      | if $marker == null then
          {found: false}
        else
          ([$entries[] | select(.idx > $last.idx) | .agents[]]) as $dispatched
          | {
              found: true,
              steps: ($marker.steps // []),
              dispatched: $dispatched
            }
        end
    end
' 2>/dev/null) || exit 0

[ -n "$result" ] || exit 0

found=$(printf '%s' "$result" | jq -r '.found' 2>/dev/null) || exit 0

if [ "$found" != "true" ]; then
  printf 'blocked (1337 tiered mode): 1337:builder dispatched with no tier routing this session. Write the steps to a JSON file and run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` once for all of them, then dispatch at the tier it assigns.\n' >&2
  exit 2
fi

steps_count=$(printf '%s' "$result" | jq -r '.steps | length' 2>/dev/null) || exit 0
dispatch_count=$(printf '%s' "$result" | jq -r '.dispatched | length' 2>/dev/null) || exit 0
case "$steps_count" in ''|*[!0-9]*) exit 0 ;; esac
case "$dispatch_count" in ''|*[!0-9]*) exit 0 ;; esac

if [ "$dispatch_count" -ge "$steps_count" ]; then
  printf 'blocked (1337 tiered mode): every routed step (%d) already has a 1337:builder dispatch this route. Run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` again before dispatching more.\n' \
    "$steps_count" >&2
  exit 2
fi

# Remaining tiers: the routed multiset minus one entry per dispatch already
# made since the last marker, removed one-for-one in dispatch order.
remaining=$(printf '%s' "$result" | jq -c '
  def remove_one(arr; x):
    (arr | index(x)) as $i
    | if $i == null then arr else (arr[0:$i] + arr[$i+1:]) end;
  ([.steps[].tier]) as $routed
  | reduce .dispatched[] as $t ($routed; remove_one(.; $t))
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
