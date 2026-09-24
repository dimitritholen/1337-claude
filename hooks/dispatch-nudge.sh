#!/usr/bin/env bash
# Stop hook: once per session, when orchestrator or tiered mode is on, nudge
# the main session to dispatch to 1337:builder if it ran the code steps
# itself instead. Parses the session transcript (JSONL) for tool_use blocks:
# a Write/Edit/MultiEdit past the orchestrator guard's size threshold, or a
# Bash command that writes a code file / feeds a heredoc into an interpreter,
# counts as a code step; an Agent call to 1337:builder counts as a dispatch. Three
# or more code steps with zero dispatches trips the nudge.
#
# Mirrors the mode switches in hooks/orchestrator-guard.sh and
# hooks/tiered-rules.sh, and the size/extension rules in
# hooks/orchestrator-guard.sh, so the two hooks agree on what counts as
# builder work.
#
# Exit 2 + stderr blocks the stop and feeds the nudge to the agent; exit 0 in
# every other path. Failure never blocks a session. CLAUDE_1337_DISPATCH_NUDGE=0
# opts out; CLAUDE_1337_DISPATCH_NUDGE_WRITES overrides the threshold (default 3).
set -u

MAX_LINES=20

[ "${CLAUDE_1337_DISPATCH_NUDGE:-1}" != "0" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

. "${0%/*}/lib/mode.sh"

orchestrator_on=0
mode_on orchestrator && orchestrator_on=1

tiered=0
mode_on tiered && tiered=1

[ "$orchestrator_on" = "1" ] || [ "$tiered" = "1" ] || exit 0

payload="$(cat)"

active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[ "$active" = "true" ] && exit 0

session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$session_id" ] || session_id="default"

flag="${TMPDIR:-/tmp}/claude-1337-dispatch-nudge-$session_id"
[ -e "$flag" ] && exit 0

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
[ -n "$transcript" ] && [ -f "$transcript" ] && [ -r "$transcript" ] || exit 0

# Same code extensions and write-pattern regexes as orchestrator-guard.sh
# (lines 114-119), plus the guard's heredoc-into-interpreter list (line 65),
# but counted regardless of body length: any heredoc into an interpreter is
# builder work for this hook.
code_ext='py|sh|bash|js|mjs|cjs|ts|rb|go|rs|php|pl|lua|html|htm|css'
redirect_re="(^|[\\s;&(])[0-9]*>+\\s*[\"']?[^\\s;&|<>]+\\.(${code_ext})[\"']?([\\s;&|]|\$)"
tee_re="(^|[\\s;&(])tee([\\s]+-[A-Za-z]+)*[\\s]+[\"']?[^\\s;&|<>]+\\.(${code_ext})[\"']?([\\s;&|]|\$)"
sedi_re="sed[\\s]+([^;&|]*[\\s])?-[A-Za-z]*i[^;&|]*[\\s][\"']?[^\\s;&|<>]+\\.(${code_ext})[\"']?([\\s;&|]|\$)"
interp_re="(^|[\\s;&(])(python3?|python2|node|bash|sh|zsh|dash|ruby|perl|php|deno|bun|osascript)([\\s]+-[^\\s]+)*[\\s]*-?[\\s]*<<-?"

counts=$(jq -R 'fromjson? // empty' "$transcript" 2>/dev/null | jq -s \
  --arg ext "$code_ext" \
  --arg redirect_re "$redirect_re" \
  --arg tee_re "$tee_re" \
  --arg sedi_re "$sedi_re" \
  --arg interp_re "$interp_re" \
  --argjson maxlines "$MAX_LINES" \
  -r '
  def lc(s): (s // "") | split("\n") | length;
  def is_code_file: (.input.file_path // "") | test("\\.(" + $ext + ")$"; "i");
  def multiedit_max:
    ([.input.edits[]? | ([lc(.old_string), lc(.new_string)] | max)]) as $a
    | if ($a | length) == 0 then 0 else ($a | max) end;
  [.[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")] as $blocks
  | ($blocks | map(select(.name=="Agent" and (.input.subagent_type // "")=="1337:builder")) | length) as $dispatches
  | ($blocks | map(select(
      (.name=="Write" and is_code_file and (lc(.input.content) > $maxlines))
      or (.name=="Edit" and is_code_file and (([lc(.input.old_string), lc(.input.new_string)] | max) > $maxlines))
      or (.name=="MultiEdit" and is_code_file and (multiedit_max > $maxlines))
      or (.name=="Bash" and (
          ((.input.command // "") | test($redirect_re; "im"))
          or ((.input.command // "") | test($tee_re; "im"))
          or ((.input.command // "") | test($sedi_re; "im"))
          or ((.input.command // "") | test($interp_re; "im"))
        ))
    )) | length) as $writes
  | "\($dispatches) \($writes)"
  ' 2>/dev/null) || exit 0

[ -n "$counts" ] || exit 0
dispatches=${counts% *}
writes=${counts#* }
case "$dispatches" in ''|*[!0-9]*) exit 0 ;; esac
case "$writes" in ''|*[!0-9]*) exit 0 ;; esac

nudge_writes="${CLAUDE_1337_DISPATCH_NUDGE_WRITES:-3}"
[ "$writes" -ge "$nudge_writes" ] || exit 0
[ "$dispatches" -ge 1 ] && exit 0

: > "$flag" 2>/dev/null || exit 0

if [ "$tiered" = "1" ]; then
  printf '%d code steps ran in the main session, none through 1337:builder; tiered routing never ran. Dispatch the next step through 1337:builder or set CLAUDE_1337_ORCHESTRATOR=0.\n' "$writes" >&2
else
  printf '%d code steps ran in the main session, none through 1337:builder. Dispatch the next step through 1337:builder or set CLAUDE_1337_ORCHESTRATOR=0.\n' "$writes" >&2
fi
exit 2
