#!/usr/bin/env bash
# tools/replay.sh <transcript.jsonl> — #658
#
# Replays a real session transcript's tool_use calls through the CURRENT
# hooks/orchestrator-guard.sh and hooks/read-cap.sh (orchestrator mode on,
# session_id fixed to "replay" so per-session state like the edit cap
# accumulates the same way it did in the real run), and compares the
# verdict each hook gives today against what the transcript actually
# recorded a PreToolUse hook doing at the time.
#
# Turn key: the promptId (falling back to the uuid) of the closest
# preceding non-sidechain "user" entry — tool_result entries are "user"
# entries too and carry the originating promptId, so this lines up with the
# turn key read-cap.sh derives itself from a live prompt_id.
#
# Recorded verdict: refused when the tool_use's matching tool_result (by
# tool_use_id) is an error whose text names a PreToolUse hook refusal;
# allowed otherwise (including when there is no matching tool_result at
# all, e.g. the call is still pending at the end of the transcript).
#
# Output: a TSV (line, tool, first, verdict, recorded, next) followed by a
# summary block. See tests/orchestrator-guard.test.sh and
# tests/read-cap.test.sh for how these two hooks read their payload.
set -u

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: $(basename "$0") <transcript.jsonl>" >&2
  exit 1
fi
transcript="$1"

command -v jq >/dev/null 2>&1 || { echo "replay.sh needs jq" >&2; exit 1; }

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
GUARD="$ROOT/hooks/orchestrator-guard.sh"
READCAP="$ROOT/hooks/read-cap.sh"

STATEDIR="$(mktemp -d)"
trap 'rm -rf "$STATEDIR"' EXIT
export TMPDIR="$STATEDIR"
export CLAUDE_1337_ORCHESTRATOR=1

# 1. Every non-sidechain tool_use, in file order, tagged with its turn key
#    and the source line number of the assistant message it came from.
events=$(jq -c -n '
  foreach inputs as $e (
    {key: null};
    (if ($e.type == "user" and ($e.isSidechain != true)) then
       .key = ($e.promptId // $e.uuid // .key)
     else . end);
    ( .key as $k
      | if ($e.type == "assistant" and ($e.isSidechain != true)) then
          (($e.message.content // []) | map(select(.type == "tool_use"))
           | map({turn_key: $k, id: .id, name: .name, input: .input, line: input_line_number}))
        else []
        end
    )
  ) | .[]
' "$transcript") || { echo "replay.sh: failed to parse $transcript" >&2; exit 1; }

if [ -z "$events" ]; then
  echo "replay.sh: no tool_use events found in $transcript" >&2
  exit 1
fi

# 2. tool_use_id -> recorded verdict, from the matching tool_result.
declare -A recorded_verdict
while IFS=$'\t' read -r id refused; do
  [ -n "$id" ] || continue
  recorded_verdict["$id"]="$refused"
done < <(jq -r '
  select(.type == "user") | .message.content[]? | select(.type == "tool_result")
  | [.tool_use_id, ((.is_error == true) and ((.content | tostring) | test("PreToolUse.*hook error")))]
  | @tsv
' "$transcript")

mapfile -t events_arr < <(printf '%s\n' "$events" | jq -c '.')
total=${#events_arr[@]}

printf 'line\ttool\tfirst\tverdict\trecorded\tnext\n'

allowed=0 refused=0 flip_to_allowed=0 flip_to_refused=0

for ((i = 0; i < total; i++)); do
  ev="${events_arr[$i]}"
  turn_key=$(jq -r '.turn_key // ""' <<<"$ev")
  id=$(jq -r '.id' <<<"$ev")
  name=$(jq -r '.name' <<<"$ev")
  input=$(jq -c '.input' <<<"$ev")
  line=$(jq -r '.line' <<<"$ev")

  case "$name" in
    Bash)
      first=$(jq -r '.command // ""' <<<"$input" | awk 'NR==1{print $1; exit}')
      ;;
    Read|Edit|Write)
      first=$(jq -r '.file_path // ""' <<<"$input" | xargs -r basename 2>/dev/null)
      ;;
    *)
      first=""
      ;;
  esac
  [ -n "$first" ] || first="-"

  payload=$(jq -n --arg sid "replay" --arg pid "$turn_key" --arg tn "$name" --argjson ti "$input" \
    '{session_id: $sid, prompt_id: $pid, tool_name: $tn, tool_input: $ti, transcript_path: ""}')

  # Only feed each hook the tool_names hooks.json actually routes to it —
  # otherwise every tool the real harness never showed these hooks (Agent,
  # AskUserQuestion, mcp__tasqx__*, ...) would hit orchestrator-guard.sh's
  # catch-all "writes a whole file" refusal.
  g=0
  case "$name" in
    Edit|Write|MultiEdit|NotebookEdit|Bash)
      printf '%s' "$payload" | "$GUARD" >/dev/null 2>&1
      g=$?
      ;;
  esac
  r=0
  case "$name" in
    Read|Grep|Glob|Bash|WebFetch|mcp__codebase-memory-mcp__get_code_snippet|mcp__codebase-memory-mcp__search_code|mcp__codebase-memory-mcp__search_graph)
      printf '%s' "$payload" | "$READCAP" >/dev/null 2>&1
      r=$?
      ;;
  esac

  if [ "$g" -eq 2 ] || [ "$r" -eq 2 ]; then
    verdict=refused
  else
    verdict=allowed
  fi

  if [ "${recorded_verdict[$id]:-}" = "true" ]; then
    recorded=refused
  else
    recorded=allowed
  fi

  next="-"
  if [ $((i + 1)) -lt "$total" ]; then
    next=$(jq -r '.name' <<<"${events_arr[$((i + 1))]}")
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$line" "$name" "$first" "$verdict" "$recorded" "$next"

  if [ "$verdict" = allowed ]; then allowed=$((allowed + 1)); else refused=$((refused + 1)); fi
  [ "$recorded" = refused ] && [ "$verdict" = allowed ] && flip_to_allowed=$((flip_to_allowed + 1))
  [ "$recorded" = allowed ] && [ "$verdict" = refused ] && flip_to_refused=$((flip_to_refused + 1))
done

echo
printf 'allowed %d\n' "$allowed"
printf 'refused %d\n' "$refused"
printf 'then-refused-now-allowed %d\n' "$flip_to_allowed"
printf 'then-allowed-now-refused %d\n' "$flip_to_refused"
