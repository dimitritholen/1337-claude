# Shared filter: lists 1337:builder dispatches (tool name Agent or Task)
# from a slice of a Claude Code transcript (JSONL), excluding a dispatch a
# PreToolUse hook refused before it ever ran — the gap hooks/route-guard.sh
# and hooks/review-gate.sh each have today (they scan for the tool_use and
# never look at its tool_result).
#
# CALLING CONVENTION: feed the RAW transcript text (or a `tail -n +N` slice
# of it) as ONE string, via `jq -R -s`, and always pass `--argjson offset N`
# (0 when the whole transcript is fed):
#
#   tail -n "+$((marker_ln + 1))" "$transcript" \
#     | jq -R -s --argjson offset "$marker_ln" -f \
#         "${CLAUDE_PLUGIN_ROOT}/hooks/lib/builder-dispatches.jq"
#
# jq cannot recover a file's line numbers once JSONL has been read one
# object at a time (input_line_number resets per invocation, and a plain
# `-s` slurp of already-parsed objects loses position entirely), so this
# filter takes the text WHOLE and splits it itself: the array index after
# `split("\n")` IS the line number within the slice. `$offset` is the
# number of lines already skipped before the slice starts (what a prior
# `tail -n +N` cut off), added back so the `line` field in the output is a
# real 1-based line number in the ORIGINAL file — the same number
# `grep -n`/`sed -n` on that file would report. A caller that needs an
# anchor line (review-gate's own `tail -n +N`) reads it from there instead
# of grepping the transcript a second time.
#
# OUTPUT: a JSON array, oldest dispatch first, one entry per KEPT builder
# dispatch:
#   {"id": "<tool_use id>", "name": "Agent"|"Task",
#    "model": <string|null>, "line": <1-based line number>}
#
# KEPT:
#   - a dispatch with no tool_result yet at all (pending: the call being
#     judged right now, e.g. from inside the PreToolUse payload itself);
#   - a dispatch that ran and came back with its own error (anything NOT
#     shaped like a PreToolUse refusal) — a builder failing on its own
#     still spent the dispatch.
# DROPPED:
#   - a dispatch whose tool_result IS a PreToolUse hook refusal, matched on
#     the refusal TEXT SHAPE (`PreToolUse:Agent hook error: ...` /
#     `PreToolUse:Task hook error: ...`), not on `is_error` alone: a
#     builder that ran and failed on its own also sets `is_error`, and that
#     dispatch must still count as spent.
#
# Refusal shape pinned from a real transcript (session
# 3e2aa0eb-9ba6-4cb0-a71c-0dafbfd0c4ad.jsonl, PreToolUse:Agent hook error
# from hooks/review-gate.sh and hooks/route-guard.sh): the tool_result's
# `content` is a plain STRING starting with `PreToolUse:Agent hook error:`,
# `is_error` is `true`. A dispatch that ran normally instead comes back
# with `content` as an ARRAY of `{"type":"text","text":"Async agent
# launched successfully. (This too..."}`, no `is_error` at all. Task-named
# dispatches are assumed to mirror Agent's shape with `PreToolUse:Task hook
# error:` (unverified: no Task-named builder refusal was found in the
# transcripts sampled).

def offset: $offset;

def texts_of(content):
  if (content | type) == "string" then content
  elif (content | type) == "array" then
    ([content[]? | select(.type == "text") | .text] | join("\n"))
  else "" end;

def is_hook_refusal(text):
  (text // "") | test("^PreToolUse:(Agent|Task) hook error:");

(split("\n")
 | to_entries
 | map(select(.value != "")
     | {n: (.key + 1 + offset), entry: (.value | (try fromjson catch null))})
 | map(select(.entry != null))
) as $lines
|
# Every builder tool_use, in file order, with its line number.
([$lines[] | select(.entry.type == "assistant")
   | .n as $n
   | (.entry.message.content? // [])[]?
   | select(.type == "tool_use" and (.name == "Agent" or .name == "Task")
       and ((.input.subagent_type // "") == "1337:builder"))
   | {id: .id, name: .name, model: (.input.model // null), line: $n}]
) as $dispatches
|
# A tool_use without an id, or a tool_result without a tool_use_id, cannot
# be paired: the dispatch counts as pending (kept) instead of crashing the
# filter, since a crash makes callers fail open.
# Every tool_result seen, indexed by the id it answers — text extracted the
# same way whether it came back as a plain string or an array of
# {type:text} blocks.
([$lines[] | select(.entry.type == "user")
   | (.entry.message.content? // [])
   | if type == "array" then .[] else empty end
   | select(.type == "tool_result" and ((.tool_use_id | type) == "string"))
   | {key: .tool_use_id, value: texts_of(.content)}]
 | from_entries
) as $results
|
[$dispatches[] | select(
    (if (.id | type) == "string" then $results[.id] else null end) as $text
    | ($text == null) or (is_hook_refusal($text) | not)
  )]
