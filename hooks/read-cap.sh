#!/usr/bin/env bash
# PreToolUse hook for Read|Grep|Glob|Bash|mcp__codebase-memory-mcp__
# (get_code_snippet|search_code|search_graph) — see hooks.json's read-cap
# matcher, #662; keep both lists in sync — active only in orchestrator mode
# (plugin option `orchestrator`, or CLAUDE_1337_ORCHESTRATOR=1). Caps how
# many of each the main session may run per user turn: CLAUDE_1337_READ_CAP
# Reads (also the three mcp tools, and a Bash call whose command
# reads a file — see bash_is_read below), CLAUDE_1337_GREP_CAP Grep/Glob
# calls, both default 0 — the main session reads nothing by default. A
# positive integer allows that many per turn; 0 refuses every call of that
# kind; the value `off` (any case) drops the cap for that kind entirely,
# i.e. disables this hook for it. Subagent calls (payload carries agent_id)
# always pass the cap. Their first Grep or Glob is a one-time nudge instead:
# refused once with a message pointing at ripwire (keyed per agent_id,
# skipped if ripwire is not on PATH), then every later call from that agent
# passes untouched. Subagent Reads, Bash and mcp calls are never
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
. "$(dirname "$0")/lib/tokenize.sh"

# A Bash call counts as a read only when it has a segment whose command word
# is a plain file-reader with a file operand (cat, head, tail, less, more,
# nl, od, xxd, strings), rg/ag/ack (these always count), `sed`/`grep`/
# `egrep`/`fgrep`/`awk` WITH a path operand (a second non-flag argument, so
# a pure stdin filter like `ps aux | grep x` or `git log | grep fix` does
# not count), `jq` judged by jq's own option grammar (see the jq case
# below: `--arg`/`--argjson`/`--indent`/`-L` consume a value that is never
# a file, `--slurpfile`/`--rawfile`/`-f`/`--from-file` read a file on their
# own regardless of anything else on the line, `--args`/`--jsonargs` turn
# the rest of the line into positional arguments, and what's left needs a
# second non-flag operand past the filter, same as sed/grep/awk), or `git
# cat-file`/`git grep`/`git show <rev>:<path>` (a `git show` operand
# containing a colon; plain `git show HEAD` or `--stat` is metadata, same
# as `git diff`, and does not count), also behind git global options; git
# behind a global option it cannot parse, or behind a `-c alias.*` config,
# counts too. An input redirect (`< file`) counts as one operand. Any
# other Bash command passes uncounted.
#
# Segments and words come from hooks/lib/tokenize.sh, the lexer
# orchestrator-guard.sh judges with, so both hooks split a command the same
# way: quoted text and heredoc bodies are data (`echo "run; cat file"` or a
# heredoc line reading `cat file` is no read), the inside of $( ), backticks
# and <( ) is a segment of its own (`x=$(cat f)` is), and the
# VAR=val/command/builtin/exec/env prefixes and the shell keywords (if, do,
# !, { ...) are skipped before the command word. A `command -v`/`-V` lookup
# runs nothing. Words come out of the tokenizer, never an unquoted
# expansion, so `cat *.rs` is one literal operand, not globbed against this
# hook's cwd.
bash_is_read() {
  local lex rec first nonflag arg skip_next inputs op prev alias_cfg ri
  lex=$(printf '%s\n' "$1" | tokenize) || return 1
  while IFS= read -r rec; do
    case "$rec" in "S$TOK_US"*) ;; *) continue ;; esac
    tok_parse "$rec"
    if [ "$tok_at" -ge "$tok_nw" ]; then
      # No command word: a bare input-redirect segment ($(< file), a
      # backtick equivalent, or a variable assigned from one) still reads
      # the file's contents into the substitution result. /dev/null and
      # friends stay uncounted, same as everywhere else.
      for ((ri = 0; ri < tok_nr; ri++)); do
        op="${tok_rops[$ri]}"
        while [[ $op == [0-9]* ]]; do op="${op#?}"; done
        [ "$op" = "<" ] || continue
        case "${tok_rtgs[$ri]}" in
          /dev/null|/dev/stdin) ;;
          *) return 0 ;;
        esac
      done
      continue
    fi
    [ "$tok_lookup" = 0 ] || continue
    set -- "${tok_words[@]:$tok_at}"
    first="$1"
    shift
    inputs=0
    for op in "${tok_rops[@]+"${tok_rops[@]}"}"; do
      while [[ $op == [0-9]* ]]; do op="${op#?}"; done
      [ "$op" = "<" ] && inputs=$((inputs + 1))
    done
    case "$first" in
      head|tail)
        # head and tail: -n/-c/--lines/--bytes take a separate argument
        # (`-n 5` is 5 lines, `-c 100` is 100 bytes), which is skipped;
        # attached forms (-n5, --lines=5) are one flag word.
        nonflag=$inputs
        skip_next=0
        for arg in "$@"; do
          if [ "$skip_next" -eq 1 ]; then
            skip_next=0
            continue
          fi
          case "$arg" in
            -[nc]|--lines|--bytes) skip_next=1 ;;
            -*) ;;
            *) nonflag=$((nonflag + 1)) ;;
          esac
        done
        [ "$nonflag" -ge 1 ] && return 0
        ;;
      cat|less|more|nl|od|xxd|strings)
        # All flags of these readers are boolean (cat -n numbers lines, od
        # -c picks a format): every word not starting with - is a file.
        nonflag=$inputs
        for arg in "$@"; do
          case "$arg" in -*) ;; *) nonflag=$((nonflag + 1)) ;; esac
        done
        [ "$nonflag" -ge 1 ] && return 0
        ;;
      rg|ag|ack) return 0 ;;
      sed|grep|egrep|fgrep|awk)
        nonflag=$inputs
        for arg in "$@"; do
          case "$arg" in -*) ;; *) nonflag=$((nonflag + 1)) ;; esac
        done
        [ "$nonflag" -ge 2 ] && return 0
        ;;
      jq)
        # jq's options are not all flag-then-operand like sed/grep/awk:
        # --arg/--argjson take NAME and VALUE (neither a file), --indent
        # and -L take one value word (a number, a module dir), the
        # boolean switches take none. --slurpfile/--rawfile and
        # -f/--from-file each read a FILE that is not the jq program's
        # operand slot, so their presence alone is a read, regardless of
        # anything else on the line (-n -f prog.jq reads prog.jq with no
        # other operand at all). --args/--jsonargs turns everything after
        # it into positional arguments, never files, so counting stops
        # there. What's left follows the sed/grep/awk rule: the first
        # non-flag word is the filter, not a file, so it takes two or
        # more non-flag operands to count as a read.
        nonflag=$inputs
        skip_next=0
        for arg in "$@"; do
          if [ "$skip_next" -gt 0 ]; then
            skip_next=$((skip_next - 1))
            continue
          fi
          case "$arg" in
            --arg | --argjson) skip_next=2 ;;
            --indent | -L) skip_next=1 ;;
            --slurpfile | --rawfile | -f | --from-file) return 0 ;;
            --args | --jsonargs) break ;;
            --tab | -n | --null-input | -r | -c | -e | -s | -j | -a | -S | -C | -M) ;;
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
        git_subcommand "$@"
        # A -c alias.* config can rename any subcommand into a read; an
        # alias cannot shadow a builtin, so `git diff` stays uncounted.
        prev="" alias_cfg=0
        for arg in "${@:1:$git_sub_at}"; do
          if [ "$prev" = "-c" ]; then
            case "$arg" in [aA][lL][iI][aA][sS].*) alias_cfg=1 ;; esac
          fi
          prev="$arg"
        done
        [ "$alias_cfg" = 1 ] && [ "$git_sub" != diff ] && return 0
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
  done <<<"$lex"
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
  mcp__codebase-memory-mcp__get_code_snippet|mcp__codebase-memory-mcp__search_code|mcp__codebase-memory-mcp__search_graph)
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
  route='Free instead: `git status`, `git diff --stat`, `ls`, or `ripwire <dir> --for="<what you are after>" --legend=compact`.
For code: `ripwire <dir> --for="<what you are after>" --legend=compact`, then `--expand=SYM`, `--callers=SYM`, `--impact=SYM`, `--uses=SYM`, `--grep=STR` as follow-ups.
For anything else (config, lockfile, transcript, prose), or when the file contents themselves are wanted: dispatch 1337:scout with the question; it reads in its own context.'
else
  route='Free instead: `git status`, `git diff --stat`, `ls`.
Dispatch 1337:scout with the question; it reads in its own context.'
fi

if [ "$kind" = "read" ]; then
  printf 'blocked (1337 orchestrator mode): Read #%d this turn (cap %d).\n%s\nCLAUDE_1337_READ_CAP=off disables.\n' "$count" "$cap" "$route" >&2
else
  printf 'blocked (1337 orchestrator mode): Grep/Glob #%d this turn (cap %d).\n%s\nCLAUDE_1337_GREP_CAP=off disables.\n' "$count" "$cap" "$route" >&2
fi
exit 2
