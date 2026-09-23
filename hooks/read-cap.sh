#!/usr/bin/env bash
# PreToolUse hook for Read|Grep|Glob|Bash|WebFetch|mcp__codebase-memory-mcp__
# (get_code_snippet|search_code|search_graph) — see hooks.json's read-cap
# matcher, #662; keep both lists in sync — active only in orchestrator mode
# (plugin option `orchestrator`, or CLAUDE_1337_ORCHESTRATOR=1). Caps how
# many of each the main session may run per user turn: CLAUDE_1337_READ_CAP
# Reads (also WebFetch, the three mcp tools, and a Bash call whose command
# reads a file — see bash_is_read below), CLAUDE_1337_GREP_CAP Grep/Glob
# calls, both default 0 — the main session reads nothing by default. A
# positive integer allows that many per turn; 0 refuses every call of that
# kind; the value `off` (any case) drops the cap for that kind entirely,
# i.e. disables this hook for it. Subagent calls (payload carries agent_id)
# always pass the cap. Their first Grep or Glob is a one-time nudge instead:
# refused once with a message pointing at ripwire (keyed per agent_id,
# skipped if ripwire is not on PATH), then every later call from that agent
# passes untouched. Subagent Reads, Bash, WebFetch and mcp calls are never
# nudged or counted.
#
# A Read/Grep/Glob whose target path falls under the session scratchpad or a
# temp dir ($TMPDIR, /tmp, /private/tmp, /var/folders) or under $HOME/.claude
# is exempt: that is data the session produced itself, not repository
# payload. Mirrors the carve-out in hooks/orchestrator-guard.sh.
#
# Turn key is prompt_id; when the payload omits it (older clients), falls
# back to a cksum of the last user message pulled from transcript_path, the
# way hooks/terse-governor.sh does. Counts are kept in a per-session state
# file, one "<turnkey> <kind>" line per call, appended (never rewritten) so
# concurrent tool calls in the same turn don't race each other away. Appending
# and counting is one critical section, held with an atomic `mkdir` lock: run
# unlocked, parallel calls all append before any of them counts, so each sees
# the full total and every one is refused. The lock holder stamps the lock with
# its start time; a lock older than 5 seconds (or one that never got a stamp)
# is stale and is cleared. After ~1s of waiting the cap is applied unlocked
# rather than stall the session.
#
# The refusal names two ways forward: `ripwire`, for code discovery, when it
# is on PATH; and dispatching 1337:scout for anything ripwire can't help with
# (a config, a lockfile, a transcript, prose) or when the file's literal
# contents are wanted.
#
# Exit 2 + stderr refuses over cap; exit 0 allows. Every failure path exits 0.
#
# EVAL_CLAUDE_1337_ORCHESTRATOR=1 is the switch eval cases use, since `claude plugin
# eval` cases may only set EVAL_* variables.
set -u

[ "${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-false}" = "true" ] || [ "${CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || [ "${EVAL_CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

. "$(dirname "$0")/lib/git-subcommand.sh"
. "$(dirname "$0")/lib/mask-quotes.sh"

# A Bash call counts as a read only when it has a segment (split on |, ;,
# &&, ||; not a full shell parse) whose first word is a plain file-reader
# (cat, head, tail, less, more, nl, od, xxd, strings, rg, ag, ack — these
# always count), `sed -n`, `grep`/`egrep`/`fgrep`/`awk`/`jq` WITH a path
# operand (a second non-flag argument, so a pure stdin filter like
# `ps aux | grep x` or `git log | grep fix` does not count), or `git
# cat-file`/`git grep`/`git show <rev>:<path>` (a `git show` operand
# containing a colon; plain `git show HEAD` or `--stat` is metadata, same
# as `git diff`, and does not count), also behind git global options and
# the command/builtin/exec/env prefixes; git behind a global option it
# cannot parse, or behind a `-c alias.*` config, counts too. Any other Bash
# command passes uncounted.
#
# The split and the first-word check run on $cmd after hooks/lib/mask-
# quotes.sh has blunted the separator characters inside quoted spans, so
# `echo "run; cat file"` or `git commit -m "x; head first"` is one segment,
# not two — the quoted `;` runs no command. `$( )` and backticks stay live
# even inside double quotes, so `echo "$(true; cat f)"` still counts.
bash_is_read() {
  local cmd first second nonflag arg
  cmd="$(mask_quotes <<<"$1")"
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] || continue
    # The unquoted split above can still leave a glob (`cat *.rs`): disable
    # expansion for the word-split so it is seen as a literal operand, not
    # expanded against this hook's own cwd.
    set -f
    set -- $seg
    set +f
    # VAR=val assignments and the command/builtin/exec/env prefixes (with
    # their flags, and env's VAR=val arguments) run the next word; skip them
    # so `command git cat-file -p X` is seen as git.
    while [ "$#" -gt 0 ]; do
      case "$1" in
        [A-Za-z_]*=*) shift ;;
        command|builtin)
          shift
          while [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done
          ;;
        exec|env)
          first="$1"; shift
          while [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; do
            case "$first $1" in
              "exec -a"|"env -u"|"env -C"|"env --unset"|"env --chdir") shift ;;
            esac
            [ "$#" -gt 0 ] && shift
          done
          ;;
        *) break ;;
      esac
    done
    first="${1:-}"
    second="${2:-}"
    case "$first" in
      head|tail)
        # head and tail: -n/-c/--lines/--bytes take separate arguments.
        # For head/tail, `-n 5` means "5 lines", `-c 100` means "100 bytes".
        shift
        nonflag=0
        skip_next=0
        for arg in "$@"; do
          if [ "$skip_next" -eq 1 ]; then
            skip_next=0
            continue
          fi
          case "$arg" in
            -[nc]|-[nc]*[0-9]|--lines|--bytes)
              # Flags that take separate arguments for head/tail.
              # If attached (-n5), it's already a single token (skip it as flag).
              # If separate (-n 5 or --lines 5), skip the flag and mark to skip the next token.
              # --lines=N and --bytes=N are single tokens, not two.
              case "$arg" in
                -[nc]|--lines|--bytes) skip_next=1 ;;
              esac
              ;;
            -*)
              # Other flags: skip them
              ;;
            *)
              # Non-flag operand: count it as a potential file
              nonflag=$((nonflag + 1))
              ;;
          esac
        done
        [ "$nonflag" -ge 1 ] && return 0
        ;;
      cat|less|more|nl|od|xxd|strings)
        # For these readers, all flags are boolean (no separate arguments).
        # cat -n (number lines), od -c (character format), etc. are flags with no args.
        # Safe to over-count by treating all tokens that don't start with - as files.
        shift
        nonflag=0
        for arg in "$@"; do
          case "$arg" in
            -*)
              # All flags: skip them (they don't take arguments)
              ;;
            *)
              # Non-flag operand: count it as a potential file
              nonflag=$((nonflag + 1))
              ;;
          esac
        done
        [ "$nonflag" -ge 1 ] && return 0
        ;;
      rg|ag|ack) return 0 ;;
      sed)
        shift
        nonflag=0
        for arg in "$@"; do
          case "$arg" in
            -*) ;;
            *) nonflag=$((nonflag + 1)) ;;
          esac
        done
        [ "$nonflag" -ge 2 ] && return 0
        ;;
      grep|egrep|fgrep|awk|jq)
        shift
        nonflag=0
        for arg in "$@"; do
          case "$arg" in
            -*) ;;
            *) nonflag=$((nonflag + 1)) ;;
          esac
        done
        [ "$nonflag" -ge 2 ] && return 0
        ;;
      git)
        # Global options in front (`git -C /repo show ...`) are skipped by
        # hooks/lib/git-subcommand.sh; one it cannot parse (git_sub
        # starting with -) counts as a possible read.
        shift
        git_subcommand "$@"
        # A -c alias.* config can rename any subcommand into a read; an
        # alias cannot shadow a builtin, so `git diff` stays uncounted.
        if [ "$git_sub" != diff ] \
          && printf ' %s' "${@:1:$git_sub_at}" | grep -qiE -- " -c ['\"]?alias\."; then
          return 0
        fi
        case "$git_sub" in
          cat-file|grep|-*) return 0 ;;
          show)
            # `git show <rev>` / `--stat` etc is metadata, same as `git
            # diff`: allowed. Only the rev:path form dumps a file's
            # contents, so it counts — an operand after `show` containing a
            # colon.
            shift "$git_sub_at"
            for arg in "$@"; do
              case "$arg" in
                *:*) return 0 ;;
              esac
            done
            ;;
        esac
        ;;
    esac
  done <<EOF
$(printf '%s' "$cmd" | sed -E 's/(\|\||&&|[|;])/\n/g')
EOF
  return 1
}

# Helper function to acquire a directory-based lock with stale detection.
# Takes the lock directory path as argument. Sets the global variable 'held' to
# 1 if lock acquired, 0 if not. On acquisition, arms an EXIT trap that removes
# the lock directory, in the same statement group that sets 'held' and writes
# the timestamp stamp, so acquisition and cleanup-registration stay atomic
# with respect to the process dying; callers that release the lock manually
# must also `trap - EXIT` once they do. Retries 50 times with 0.02 second
# sleep between attempts; treats a lock older than 5 seconds (or without a
# valid timestamp) as stale and removes it.
acquire_lock() {
  local lock_path="$1"

  held=0
  spin=0
  while [ "$spin" -lt 50 ]; do
    if mkdir "$lock_path" 2>/dev/null; then
      held=1
      printf '%s\n' "${EPOCHSECONDS:-$(date +%s)}" > "$lock_path/ts" 2>/dev/null
      trap "rm -rf '$lock_path' 2>/dev/null" EXIT
      break
    fi
    spin=$((spin + 1))
    stamp=$(cat "$lock_path/ts" 2>/dev/null)
    case "$stamp" in
      ''|*[!0-9]*) [ "$spin" -ge 25 ] && rm -rf "$lock_path" 2>/dev/null ;;
      *) [ "$(( ${EPOCHSECONDS:-$(date +%s)} - stamp ))" -ge 5 ] && rm -rf "$lock_path" 2>/dev/null ;;
    esac
    sleep 0.02
  done
}

payload="$(cat)"

agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
if [ -n "$agent_id" ]; then
  # Subagent calls carry agent_id and always pass the cap, but a subagent's
  # first Grep/Glob is a nudge point: it may not have heard about ripwire
  # (only some agent types get it in their prompt). Refuse that one call,
  # once per agent_id, naming ripwire; every later call this run goes
  # through untouched. Read is never nudged, and there is no nudge at all
  # when ripwire is not on PATH to route to.
  sub_tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
  case "$sub_tool" in
    Grep|Glob) ;;
    *) exit 0 ;;
  esac
  command -v ripwire >/dev/null 2>&1 || exit 0

  nudge_state="${TMPDIR:-/tmp}/claude-1337-read-cap-nudge-$agent_id"
  nudge_lock="$nudge_state.lock"

  acquire_lock "$nudge_lock"

  already_nudged=0
  [ -e "$nudge_state" ] && already_nudged=1
  : > "$nudge_state" 2>/dev/null || true

  if [ "$held" = 1 ]; then
    rm -rf "$nudge_lock" 2>/dev/null
    trap - EXIT
  fi

  [ "$already_nudged" = 0 ] || exit 0

  printf 'nudge (1337): first Grep/Glob this run — try ripwire first: `ripwire <dir> --for="<what you are after>" --legend=compact` (then --expand=SYM, --callers=SYM, --impact=SYM, --uses=SYM, --grep=STR). Retry with Grep/Glob if ripwire does not cover it; later calls this run are not nudged.\n' >&2
  exit 2
fi

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

case "$tool" in
  Read) kind=read; cap="${CLAUDE_1337_READ_CAP:-0}" ;;
  Grep|Glob) kind=grep; cap="${CLAUDE_1337_GREP_CAP:-0}" ;;
  WebFetch|mcp__codebase-memory-mcp__get_code_snippet|mcp__codebase-memory-mcp__search_code|mcp__codebase-memory-mcp__search_graph)
    kind=read; cap="${CLAUDE_1337_READ_CAP:-0}" ;;
  Bash)
    bash_command=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    bash_is_read "$bash_command" || exit 0
    kind=read; cap="${CLAUDE_1337_READ_CAP:-0}" ;;
  *) exit 0 ;;
esac

# `off` (any case) drops the cap for this kind entirely.
cap_lc=$(printf '%s' "$cap" | tr '[:upper:]' '[:lower:]')
[ "$cap_lc" != "off" ] || exit 0

# A target under the session's own scratch space is exempt: it's data the
# session produced, not repository payload. Mirrors orchestrator-guard.sh:46.
target=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || exit 0
case "$target" in
  "$HOME"/.claude/*|/tmp/*|/private/tmp/*|/var/folders/*) exit 0 ;;
esac

session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$session_id" ] || exit 0

turn_key=$(printf '%s' "$payload" | jq -r '.prompt_id // empty' 2>/dev/null) || exit 0
if [ -z "$turn_key" ]; then
  transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    # One jq call: pick the last non-sidechain user entry and hand back its
    # uuid and its text, separated by \u0001. uuid wins when present; the
    # text is the last-resort cksum fallback for transcripts without one.
    last_user=$(jq -rs '
      map(select(.type == "user" and (.isSidechain != true)))
      | last
      | if . == null then empty
        else [(.uuid // ""),
              ((.message.content // "")
               | if type == "string" then .
                 else ([.[]? | select(.type == "text") | .text] | join("\n"))
                 end)]
             | join("\u0001")
        end' "$transcript" 2>/dev/null)
    if [ -n "$last_user" ]; then
      uuid_part="${last_user%%$'\x01'*}"
      text_part="${last_user#*$'\x01'}"
      if [ -n "$uuid_part" ]; then
        turn_key="$uuid_part"
      elif [ -n "$text_part" ]; then
        turn_key=$(printf '%s' "$text_part" | cksum | awk '{print $1}')
      fi
    fi
  fi
fi
[ -n "$turn_key" ] || exit 0

state="${TMPDIR:-/tmp}/claude-1337-read-cap-$session_id"
lock="$state.lock"

acquire_lock "$lock"

# The state file's first line is the turn key alone. A key that differs
# from the one on file means a new turn: truncate to just that key line
# before appending this call's entry, so counts never leak across turns.
current_key=$(head -n 1 "$state" 2>/dev/null)
if [ "$current_key" != "$turn_key" ]; then
  printf '%s\n' "$turn_key" > "$state" 2>/dev/null || exit 0
fi

printf '%s %s\n' "$turn_key" "$kind" >> "$state" 2>/dev/null || exit 0

count=$(grep -c -F -x "$turn_key $kind" "$state" 2>/dev/null) || exit 0

if [ "$held" = 1 ]; then
  rm -rf "$lock" 2>/dev/null
  trap - EXIT
fi

[ "$count" -le "$cap" ] && exit 0

# Two ways forward: ripwire maps code, but says nothing useful about a JSON
# config, a lockfile, a transcript or a prose doc — for those, or for wanting
# a file's literal contents, dispatch 1337:scout instead.
if command -v ripwire >/dev/null 2>&1; then
  route='For code: `ripwire <dir> --for="<what you are after>" --legend=compact`, then `--expand=SYM`, `--callers=SYM`, `--impact=SYM`, `--uses=SYM`, `--grep=STR` as follow-ups.
For anything else (config, lockfile, transcript, prose), or when the file contents themselves are wanted: dispatch 1337:scout with the question; it reads in its own context.'
else
  route='Dispatch 1337:scout with the question; it reads in its own context.'
fi

if [ "$kind" = "read" ]; then
  printf 'blocked (1337 orchestrator mode): Read #%d this turn (cap %d).\n%s\nCLAUDE_1337_READ_CAP=off disables.\n' "$count" "$cap" "$route" >&2
else
  printf 'blocked (1337 orchestrator mode): Grep/Glob #%d this turn (cap %d).\n%s\nCLAUDE_1337_GREP_CAP=off disables.\n' "$count" "$cap" "$route" >&2
fi
exit 2
