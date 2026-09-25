#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit|Bash, active only in
# orchestrator mode (plugin option `orchestrator`, CLAUDE_1337_ORCHESTRATOR=1,
# or EVAL_CLAUDE_1337_ORCHESTRATOR=1, the switch eval cases use since `claude
# plugin eval` cases may only set EVAL_* variables).
# Keeps the main session an orchestrator: subagent calls (payload carries
# agent_id) pass with one exception, a Bash git command that would revert,
# stash, reset, clean or overwrite another parallel builder's finished work
# in the shared tree (#723; see subagent_git_guard below,
# CLAUDE_1337_SUBAGENT_GIT_GUARD=off disables it); the main session may make
# edits of <= MAX_LINES lines (CLAUDE_1337_MAX_LINES, else the plugin option
# max_edit_lines in /config, else 20; an edit
# counts the larger of its old and new text, a MultiEdit the sum over its
# edits) and write under ~/.claude or a temp dir, where a code file is still
# refused.
# 1337: later: mcp write tools in the matcher
#
# Bash is judged against an ALLOWLIST, not a list of write patterns: the
# command is split into segments (| ; & && || newlines, subshells, and the
# inside of every $( ), backtick and <( ) as segments of their own), and the
# first word of every segment, after VAR=val assignments and the
# command/builtin/exec/env prefixes, must be one the main session may run:
# read-only inspection (ls cat head tail wc find grep rg awk jq sort uniq cut
# tr diff stat file which type echo printf test cd pwd date ... sleep), git
# with a bookkeeping subcommand, sed without -i, the plugin's own scripts
# (skills/tier/route.py, skills/visual/*.py), the test runners
# (tests/*.test.sh, tests/run-all.sh, tools/replay.sh), claude, tasqx and
# ripwire. CLAUDE_1337_BASH_ALLOW adds first words (space-separated). Anything
# else is refused with the segment named: a denylist of write patterns leaked
# cp, rm, patch, git apply, curl -o and every interpreter that writes from
# inside its own script, and an allowlist has no such gaps to find.
#
# Quoted text and heredoc bodies are data, not commands: the lexer
# (hooks/lib/tokenize.sh, shared with read-cap.sh) keeps a quoted span
# inside its word and drops a heredoc body before any segment is
# judged, so a commit message that mentions `rm -rf` or `a > b` runs nothing.
# `$( )` and backticks are executed even inside double quotes and in an
# unquoted heredoc body; the first become segments of their own, the second
# is refused, since the guard does not parse heredoc bodies.
#
# An allowed segment may still write through a redirect (> >> &> 2> <>), tee,
# sort -o or uniq's output operand. Each target is judged on its own: under
# ~/.claude, a temp dir or /dev/null it passes, except that a code file
# (.py .sh .js and the like) under temp is refused as builder work; anywhere
# else it is refused. `2>&1`, `>&2` and `2>/dev/null` are fine. A literal
# assignment to a temp path (`S=/tmp/x; ... > $S/f.txt`) resolves; any other
# variable in a target does not, and is refused. Assignments to variables
# that pick the code an allowed command runs (PATH, LD_*, GIT_*, PAGER,
# BASH_ENV and the like) are refused, and so are `git -c` keys that name a
# program (core.pager, diff.external, ...).
#
# Bash commands that DUMP a file's contents into context (cat, head, tail,
# sed -n/awk/grep/jq over a path, find, cp/mv out of the tree, an inline
# interpreter that opens a file) are refused too, on top of the allowlist and
# before it, for the same reason the read-cap hook watches Read|Grep|Glob: the
# main session must not pour whole files into its own expensive context. A
# tree scanner needs no path operand to dump one: rg/ag/ack at the head of a
# pipeline, and grep -r, read the working tree by default and are refused with
# or without a path. A pipeline stage that only filters another command's
# stdout (no file operand of its own, e.g. `git log | grep fix`) is not a
# reader, and neither is a bare `grep pattern` on stdin. Operands under a temp
# dir or ~/.claude are the session's own scratch, not repository payload, and
# do not count, the same carve-out read-cap.sh makes. The refusal names the
# two ways forward in the same words as hooks/read-cap.sh;
# tests/rule-copies.test.sh keeps the copies aligned.
#
# One Bash write route into the repository stays open: ripwire's own symbol
# edit (--replace-symbol-body / --insert-before-symbol / --insert-after-symbol
# with --edit-payload), and its transactional twin --edit-plan=FILE with
# --apply. Both resolve the definition(s) themselves and answer with a
# receipt, so they are the only way to change code without the session having
# read the file first. Each draws on the same per-session edit budget as a
# small Edit. A ripwire run without --edit-payload is a map query, and
# --edit-plan with --dry-run only preflights: neither writes nor counts.
#
# With --rules it prints hooks/orchestrator.md instead (SessionStart), under
# the same on/off condition; jq missing at that point only prepends a
# warning (see jq_off_hint/jq_missing_body below), since --rules needs no jq
# itself and the session should still get its context.
#
# Exit 2 + stderr refuses; exit 0 allows. jq missing in orchestrator mode
# refuses every later PreToolUse call with an actionable message (install
# instructions per OS, how to turn orchestrator mode off) — the guard cannot
# read the call, so it fails closed; a payload jq cannot parse passes.
set -u

# CLAUDE_1337_MAX_LINES wins when set; else the plugin option `max_edit_lines`
# (CLAUDE_PLUGIN_OPTION_MAX_EDIT_LINES) when it is a positive integer; else 20.
MAX_LINES="${CLAUDE_1337_MAX_LINES:-20}"
if [ -z "${CLAUDE_1337_MAX_LINES:-}" ]; then
  case "${CLAUDE_PLUGIN_OPTION_MAX_EDIT_LINES:-}" in
    ''|*[!0-9]*|0) ;;
    *) MAX_LINES="$CLAUDE_PLUGIN_OPTION_MAX_EDIT_LINES" ;;
  esac
fi
case "$MAX_LINES" in ''|*[!0-9]*) MAX_LINES=20 ;; esac

. "${0%/*}/lib/mode.sh"
mode_on orchestrator || exit 0

# How to turn orchestrator mode off, accurate to lib/mode.sh: the plugin
# option and the env vars are OR'd together, so once the plugin option is
# on, CLAUDE_1337_ORCHESTRATOR cannot override it back off — only /plugin can.
jq_off_hint() {
  if _opt_is_on "${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-}"; then
    echo 'Or turn orchestrator mode off: the plugin option "orchestrator" is on (change it via /plugin) — CLAUDE_1337_ORCHESTRATOR alone cannot override a plugin option that is on.'
  else
    echo 'Or turn orchestrator mode off: unset CLAUDE_1337_ORCHESTRATOR (or EVAL_CLAUDE_1337_ORCHESTRATOR, whichever is set).'
  fi
}

# Shared body for the SessionStart warning and the hard refusal below;
# tests/orchestrator-guard.test.sh checks both.
jq_missing_body() {
  cat <<'EOF'
jq is required for 1337 orchestrator mode. Install it:
  macOS:          brew install jq
  Debian/Ubuntu:  sudo apt install jq
  Fedora:         sudo dnf install jq
EOF
  jq_off_hint
}

if [ "${1:-}" = "--rules" ]; then
  command -v jq >/dev/null 2>&1 || {
    echo "WARNING (1337 orchestrator mode): $(jq_missing_body | tr '\n' ' ')"
  }
  cat "$(dirname "$0")/orchestrator.md"
  exit 0
fi

command -v jq >/dev/null 2>&1 || {
  echo "blocked (1337 orchestrator mode): jq is missing from PATH, so the guard cannot read this tool call and refuses it. $(jq_missing_body | tr '\n' ' ')" >&2
  exit 2
}

PLUGIN_ROOT="$(CDPATH= cd -- "${0%/*}/.." && pwd -P)"
. "${0%/*}/lib/read-route.sh"

# Code files are builder work regardless of directory: refused even under the
# temp-dir exemption. Data files under temp stay allowed. dispatch-nudge.sh
# carries the same line; tests/dispatch-nudge.test.sh keeps them equal.
code_ext='py|sh|bash|js|mjs|cjs|ts|rb|go|rs|php|pl|lua|html|htm|css'

is_code() { # path
  local lc
  lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [[ $lc =~ \.($code_ext)$ ]]
}

# ~/.claude is not all scratch: config (settings.json, settings.local.json,
# CLAUDE.md), hooks, agents, skills, commands and, above all, plugins/ (the
# INSTALLED copy of this plugin, whose hooks and skills/tier/route.py the
# main session goes on to run) live under it too, and a write there is a way
# to rewrite the router or turn this guard off. Only the data locations the
# main session and this plugin's own scripts legitimately write to are
# exempt: session scratch and per-project memory files under
# ~/.claude/projects/, ~/.claude/todos/, ~/.claude/plans/ (plan mode writes its
# plan file there), and this plugin's own state files
# (~/.claude/.1337-*, e.g. .1337-terse written by /1337:terse). Everything
# else under ~/.claude is refused like any other tree write. Used by the
# Write/Edit path check, judge_target (Bash redirect/tee/mkdir/mktemp/sort
# targets) and note_assignment (variable resolution) alike, so the exemption
# cannot be widened in one place and forgotten in another. The caller is
# expected to have $HOME, ~ and any variables already resolved into $1 (as
# resolve_target does for the Bash side); a `..` step is caught by the tree
# fallback in target_class before this ever runs.
is_claude_data() { # resolved absolute path
  case "$1" in
    "${HOME:-/nonexistent}"/.claude/projects/* | "${HOME:-/nonexistent}"/.claude/todos/* \
      | "${HOME:-/nonexistent}"/.claude/plans/*) return 0 ;;
    "${HOME:-/nonexistent}"/.claude/.1337-*) return 0 ;;
  esac
  return 1
}

# The per-session edit budget, drawn on by small Edit/MultiEdit calls and by
# ripwire's symbol edit alike: both change code the main session has not read,
# so they share one allowance. Returns 2 when the call is past the cap, 0 when
# it may go ahead; every failure path allows.
count_edit() { # label recorded in the state file
  local edit_cap session_id edit_state edit_count
  edit_cap="${CLAUDE_1337_EDIT_CAP:-3}"
  [ "$edit_cap" != "0" ] || return 0
  session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null) || return 0
  [ -n "$session_id" ] || return 0
  # No lock: parallel small edits from the main session are rare enough
  # that a lost increment here is an acceptable risk.
  edit_state="${TMPDIR:-/tmp}/claude-1337-edit-cap-$session_id"
  printf '%s\n' "$1" >> "$edit_state" 2>/dev/null || return 0
  edit_count=$(awk 'END { print NR }' "$edit_state" 2>/dev/null) || return 0
  if [ "$edit_count" -gt "$edit_cap" ]; then
    printf 'blocked (1337 orchestrator mode): edit #%d this session (cap %d); hand edits and ripwire symbol edits draw on the same budget. The route left is a 1337:builder dispatch with a self-contained brief. CLAUDE_1337_EDIT_CAP=0 disables.\n' \
      "$edit_count" "$edit_cap" >&2
    return 2
  fi
  return 0
}

# The two ways forward out of a refused read, in the same words as
# Both read refusals, the git one and the generic one, say the same thing bar
# the description of what was caught, and end on that route. Refuses on the
# spot: there is nothing left for the caller to decide.
refuse_read() { # what was caught, the command
  printf 'blocked (1337 orchestrator mode): Bash command %s (%.80s).\n%s\n' "$1" "$2" "$(read_route)" >&2
  exit 2
}

refuse_segment() { # segment text
  printf 'blocked (1337 orchestrator mode): Bash segment `%.120s` is not on the main-session allowlist. The main session runs read-only inspection, git bookkeeping, the test runners and the plugin'"'"'s own scripts; anything else is a 1337:builder dispatch (changes) or a 1337:checker dispatch (runs and verification) with a self-contained brief. CLAUDE_1337_BASH_ALLOW="<word> ..." adds first words to the allowlist.\n' "$1" >&2
  exit 2
}

refuse_code_write() { # command
  printf 'blocked (1337 orchestrator mode): Bash command writes a code file (%.80s). Scripts are builder work even under temp directories; dispatch it to 1337:builder with a self-contained brief.\n' "$1" >&2
  exit 2
}

refuse_write() { # command
  printf 'blocked (1337 orchestrator mode): Bash command writes files (%.80s). Dispatch it to 1337:builder with a self-contained brief; the main session may only write under the ~/.claude data allowlist (projects, todos, .1337-* state) and temp directories.\n' "$1" >&2
  exit 2
}

# A write target still holding an unexpanded variable is refused: it could
# expand to `../` and leave the temp dir. Own message, so it names the fix.
refuse_var_target() { # command
  printf 'blocked (1337 orchestrator mode): Bash command writes to a redirect target that contains an unexpanded variable (%.80s). A variable in a write target could hold `../` and escape the temp dir at runtime, so it cannot be judged safe even under a temp path; use a literal path instead (e.g. a fixed filename, not one built from a loop variable).\n' "$1" >&2
  exit 2
}

# ~/.claude config (settings.json, settings.local.json, CLAUDE.md), hooks,
# agents, skills, commands and the installed plugin under ~/.claude/plugins
# (this plugin's own hooks and skills/tier/route.py, which the main session
# then runs) are off-limits in orchestrator mode: a write there could rewrite
# the router or turn this guard off. Named separately from refuse_write so
# the message points at the narrower cause.
refuse_claude_config() { # command
  printf 'blocked (1337 orchestrator mode): Bash command writes under ~/.claude outside the data allowlist (%.80s). Config, hooks, agents, skills, commands and the installed plugin under ~/.claude are off-limits in orchestrator mode; only ~/.claude/projects, ~/.claude/todos, ~/.claude/plans and ~/.claude/.1337-* state files are writable. Dispatch it to 1337:builder with a self-contained brief.\n' "$1" >&2
  exit 2
}

# #723: three 1337:builder subagents in one shared working tree is the
# documented shape (hooks/orchestrator.md), and one of them once saw test
# failures caused by the others' in-progress work and ran `git checkout --
# ...` to wipe it. A subagent otherwise passes this guard untouched (it may
# not have read the file it is fixing, unlike the main session); this one
# check still applies to it, since none of these git forms are a subagent's
# own edit going back. CLAUDE_1337_SUBAGENT_GIT_GUARD=off disables it.
refuse_subagent_revert() { # what was run
  printf 'blocked (1337 orchestrator mode): subagent Bash command runs %s. Never revert, stash, reset, clean or overwrite a file you did not change in this dispatch (#723, a parallel builder'"'"'s finished work); edit your own change back instead.\n' "$1" >&2
  exit 2
}

subagent_git_guard() { # the full bash command
  [ "${CLAUDE_1337_SUBAGENT_GIT_GUARD:-on}" != "off" ] || return 0
  . "$(dirname "$0")/lib/git-subcommand.sh"
  . "$(dirname "$0")/lib/tokenize.sh"
  local lex_out rec words nw at cmd args a form
  lex_out=$(printf '%s\n' "$1" | tokenize) || return 0
  while IFS= read -r rec; do
    case "$rec" in "S$TOK_US"*) ;; *) continue ;; esac
    tok_parse "$rec"
    words=(); [ "$tok_nw" -gt 0 ] && words=("${tok_words[@]}")
    at="$tok_at"; nw="$tok_nw"
    cmd=""
    [ "$at" -lt "$nw" ] && cmd="${words[$at]}"
    [ "$cmd" = git ] || continue
    args=()
    [ $((at + 1)) -lt "$nw" ] && args=("${words[@]:$((at + 1))}")
    git_subcommand "${args[@]}"
    case "$git_sub" in
      checkout)
        for a in "${args[@]:$git_sub_at}"; do
          case "$a" in
            -- | .) refuse_subagent_revert "git checkout with a pathspec" ;;
          esac
        done
        ;;
      restore) refuse_subagent_revert "git restore" ;;
      reset)
        for a in "${args[@]:$git_sub_at}"; do
          case "$a" in --hard | --merge | --keep) refuse_subagent_revert "git reset $a" ;; esac
        done
        ;;
      stash)
        form="${args[$git_sub_at]:-}"
        case "$form" in list | show) ;; *) refuse_subagent_revert "git stash${form:+ $form}" ;; esac
        ;;
      clean) refuse_subagent_revert "git clean" ;;
    esac
  done <<<"$lex_out"
  return 0
}

payload="$(cat)"

agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
if [ -n "$agent_id" ]; then
  tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
  if [ "$tool" = Bash ]; then
    bash_cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    [ -n "$bash_cmd" ] && subagent_git_guard "$bash_cmd"
  fi
  exit 0
fi

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || exit 0

# The ~/.claude data allowlist (is_claude_data) and temp dirs are the
# session's own scratch. A `..` step never counts as inside one, and a code
# file written under temp is still a script.
tmp_real="${TMPDIR:-}"
case "$tmp_real" in /?*) tmp_real="${tmp_real%/}" ;; *) tmp_real="" ;; esac
case "$file" in
  */../*|*/..) ;;
  *)
    is_claude_data "$file" && exit 0
    case "$file" in
      "${HOME:-/nonexistent}"/.claude/*)
        printf 'blocked (1337 orchestrator mode): %s on %s writes under ~/.claude outside the data allowlist. Config, hooks, agents, skills, commands and the installed plugin under ~/.claude are off-limits in orchestrator mode; only ~/.claude/projects, ~/.claude/todos, ~/.claude/plans and ~/.claude/.1337-* state files are writable. Dispatch it to 1337:builder with a self-contained brief.\n' \
          "$tool" "$file" >&2
        exit 2
        ;;
      /tmp/*|/private/tmp/*|/var/folders/*|"${tmp_real:-/nonexistent}"/*)
        if [ "$tool" = Write ] && is_code "$file"; then
          printf 'blocked (1337 orchestrator mode): Write on %s writes a code file. Scripts are builder work even under temp directories; dispatch it to 1337:builder with a self-contained brief.\n' "$file" >&2
          exit 2
        fi
        exit 0
        ;;
    esac
    ;;
esac

case "$tool" in
  Bash)
    bash_cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    [ -n "$bash_cmd" ] || exit 0
    . "$(dirname "$0")/lib/git-subcommand.sh"
    # The Bash lexer lives in hooks/lib/tokenize.sh, shared with read-cap.sh;
    # its header documents the S/B/X records read below.
    . "$(dirname "$0")/lib/tokenize.sh"
    US="$TOK_US"
    PH="$TOK_PH"
    lex_out=$(printf '%s\n' "$bash_cmd" | tokenize) || {
      printf 'blocked (1337 orchestrator mode): Bash command could not be split into segments (%.80s). Dispatch it to 1337:builder with a self-contained brief.\n' "$bash_cmd" >&2
      exit 2
    }
    segs=()
    bodies=()
    while IFS= read -r rec; do
      case "$rec" in
        "S$US"*) segs+=("$rec") ;;
        "B$US"*)
          rec="${rec#B"$US"}"
          bodies[${rec%%"$US"*}]="${rec#*"$US"}"
          ;;
        "X$US"*)
          printf 'blocked (1337 orchestrator mode): Bash command has %s, which this guard does not judge (%.80s). Quote the heredoc marker (<<'"'"'EOF'"'"'), or dispatch it to 1337:builder with a self-contained brief.\n' "${rec#X"$US"}" "$bash_cmd" >&2
          exit 2
          ;;
      esac
    done <<<"$lex_out"

    # Variables assigned in this command: a literal temp or ~/.claude value
    # resolves in a later write target; anything else leaves the variable
    # unresolved, so a target naming it counts as the tree.
    var_names=()
    var_vals=()

    # A bare `VAR=$(mktemp ...)` — no -p/--tmpdir/-t or template overriding
    # where it lands — is guaranteed under $TMPDIR by mktemp(1) itself, the
    # same guarantee a literal temp path carries; resolve VAR to a stand-in
    # temp path up front so `> $VAR/f` reads as scratch below. The nested
    # `$(mktemp ...)` call is still lexed and judged as its own segment, so
    # `VAR=$(mktemp -d -p /etc)` is refused there regardless of this.
    #
    # That guarantee dies the moment VAR is bound again anywhere else in the
    # command: `D=$(mktemp -d); D=src; echo x > $D/f` must not resolve $D.
    # mk_rebound looks for a second plain/`+=` assignment to VAR (the
    # mktemp one is the first) or a `read`/`declare`/`local`/`typeset`/
    # `export`/`for`/`select` naming VAR without one; either disqualifies
    # the variable and it is left unresolved, same as any other dynamic
    # value.
    mk_rebound() { # var
      local v="$1" assign_re bind_re scan cnt=0
      assign_re="(^|[^A-Za-z0-9_])$v"'\+?='
      scan="$bash_cmd"
      while [[ $scan =~ $assign_re ]]; do
        cnt=$((cnt + 1))
        scan="${scan#*"${BASH_REMATCH[0]}"}"
        [ "$cnt" -gt 1 ] && return 0
      done
      bind_re='(^|[;&|`(])[[:space:]]*(read|declare|local|typeset|export|for|select)([[:space:]]+-[A-Za-z][A-Za-z-]*)*[[:space:]]+'"$v"'([^A-Za-z0-9_=]|$)'
      [[ $bash_cmd =~ $bind_re ]] && return 0
      return 1
    }
    mk_scan="$bash_cmd"
    mk_re='([A-Za-z_][A-Za-z0-9_]*)=\$\([[:space:]]*mktemp(([^A-Za-z0-9_)][^)]*)?)\)'
    while [[ $mk_scan =~ $mk_re ]]; do
      mk_var="${BASH_REMATCH[1]}"; mk_argstr="${BASH_REMATCH[2]}"
      mk_scan="${mk_scan#*"${BASH_REMATCH[0]}"}"
      read -r -a mk_words <<<"$mk_argstr"
      mk_bare=1
      for mk_w in "${mk_words[@]}"; do
        case "$mk_w" in
          -p | --tmpdir | -p?* | --tmpdir=* | -t) mk_bare=0 ;;
          -*) ;;
          *) mk_bare=0 ;; # a bare template argument also picks the target
        esac
      done
      if [ "$mk_bare" = 1 ] && ! mk_rebound "$mk_var"; then
        var_names+=("$mk_var")
        var_vals+=("${tmp_real:-/tmp}/1337-mktemp")
      fi
    done

    # Lexically collapses . and .. in an absolute path (no filesystem
    # access): the one normaliser both the cd/pushd tracker below and
    # resolve_target's eff_dir join use, so `cd a/x && cd ..` and
    # `cd a && echo > ../f` land on the same string.
    normalize_path() { # absolute path
      local p="$1" part parts=() out=()
      IFS='/' read -r -a parts <<<"$p"
      for part in "${parts[@]+"${parts[@]}"}"; do
        case "$part" in
          '' | '.') ;;
          '..') [ "${#out[@]}" -gt 0 ] && out=("${out[@]:0:$((${#out[@]} - 1))}") ;;
          *) out+=("$part") ;;
        esac
      done
      if [ "${#out[@]}" -eq 0 ]; then printf '/'; else printf '/%s' "${out[@]}"; fi
    }
    # The effective directory the segment walk below tracks across cd/pushd:
    # unknown at the start (a relative target is judged exactly as before,
    # no cd having been seen), set absolute the moment a plain cd/pushd
    # names one, unknown again the moment that gets ambiguous or the next
    # separator is anything but && (see the end of judge_segment).
    eff_dir=""
    eff_dir_known=0
    prev_top_sep=""

    # Sets rt: the target with assigned variables, $HOME, ~ and $TMPDIR put
    # in, as far as they can be, then joined onto the tracked effective
    # directory when it is still relative and one is known — the fix for
    # #726: `cd ~/.claude/projects/x && echo a >> notes.md` must not judge
    # notes.md against the hook's own cwd.
    resolve_target() { # target
      local t="$1" k v val home_set=0 tmp_set=0
      for k in "${!var_names[@]}"; do
        v="${var_names[$k]}"; val="${var_vals[$k]}"
        [ "$v" = HOME ] && home_set=1
        [ "$v" = TMPDIR ] && tmp_set=1
        [ -n "$val" ] || continue
        t="${t//\$\{$v\}/$val}"
        while [[ $t =~ ^(.*)\$$v([^A-Za-z0-9_].*)?$ ]]; do t="${BASH_REMATCH[1]}$val${BASH_REMATCH[2]}"; done
      done
      if [ "$home_set" = 0 ] && [ -n "${HOME:-}" ]; then
        case "$t" in "~" | "~/"*) t="$HOME${t#\~}" ;; esac
        t="${t//\$\{HOME\}/$HOME}"
        while [[ $t =~ ^(.*)\$HOME([^A-Za-z0-9_].*)?$ ]]; do t="${BASH_REMATCH[1]}$HOME${BASH_REMATCH[2]}"; done
      fi
      if [ "$tmp_set" = 0 ]; then
        while [[ $t =~ ^(.*)\$\{TMPDIR(:?[-=][^}]*)?\}(.*)$ ]]; do t="${BASH_REMATCH[1]}/tmp/1337-scratch${BASH_REMATCH[3]}"; done
        while [[ $t =~ ^(.*)\$TMPDIR([^A-Za-z0-9_].*)?$ ]]; do t="${BASH_REMATCH[1]}/tmp/1337-scratch${BASH_REMATCH[2]}"; done
      fi
      if [ "$eff_dir_known" = 1 ]; then
        case "$t" in
          "" | /* | *"$PH"* | *'$'* | *'`'*) ;;
          *) t="$(normalize_path "$eff_dir/$t")" ;;
        esac
      fi
      rt="$t"
    }
    # Sets tc: dev (/dev/null and friends), claude (the ~/.claude data
    # allowlist, is_claude_data), temp, or tree for everything else,
    # including anything still dynamic.
    target_class() { # resolved target
      case "$1" in
        *"$PH"* | *'$'* | *'`'*) tc=var; return ;;
        */../* | */.. | ../* | ..) tc=tree; return ;;
        /dev/null | /dev/stdout | /dev/stderr | /dev/tty | /dev/fd/*) tc=dev; return ;;
      esac
      if is_claude_data "$1"; then
        tc=claude; return
      fi
      case "$1" in
        /tmp | /tmp/* | /private/tmp | /private/tmp/* | /var/folders | /var/folders/* \
          | "${tmp_real:-/nonexistent}" | "${tmp_real:-/nonexistent}"/*) tc=temp ;;
        *) tc=tree ;;
      esac
    }
    judge_target() { # target, [nocode]
      resolve_target "$1"
      target_class "$rt"
      case "$tc" in dev | claude) return 0 ;; esac
      [ "$tc" = var ] && refuse_var_target "$bash_cmd"
      case "$rt" in "${HOME:-/nonexistent}"/.claude/*) refuse_claude_config "$bash_cmd" ;; esac
      if [ -z "${2:-}" ] && is_code "$rt"; then refuse_code_write "$bash_cmd"; fi
      [ "$tc" = temp ] && return 0
      refuse_write "$bash_cmd"
    }
    # A read operand under a temp dir or ~/.claude is output the session
    # produced itself, not repository payload, as read-cap.sh exempts.
    is_scratch_operand() { # word
      case "$1" in *.claude/*) return 0 ;; esac
      resolve_target "$1"
      target_class "$rt"
      case "$tc" in temp | claude | dev) return 0 ;; esac
      return 1
    }
    # Variables that choose which program an allowed command runs, or what it
    # loads: an assignment to one turns `ls` or `git log` into anything.
    is_exec_var() { # name
      case "$1" in
        PATH | ENV | BASH_ENV | BASH_* | IFS | CDPATH | PROMPT_COMMAND | SHELLOPTS | BASHOPTS | LD_* | DYLD_* \
          | GIT_* | PAGER | MANPAGER | EDITOR | VISUAL | PYTHON* | PERL5* | PERLLIB | RUBY* | NODE_OPTIONS | JQ_LIBRARY_PATH | GAWK* | AWKPATH | AWKLIBPATH)
          return 0 ;;
      esac
      return 1
    }
    note_assignment() { # name value
      resolve_target "$2"
      target_class "$rt"
      var_names+=("$1")
      case "$tc" in temp | claude) var_vals+=("$rt") ;; *) var_vals+=("") ;; esac
    }

    # The plugin's own scripts: skills/tier/route.py and skills/visual/*.py,
    # named relative to the repository, through ${CLAUDE_PLUGIN_ROOT}, or by
    # an absolute path that is the same file as this plugin's copy.
    is_plugin_script() { # path
      local p="${1#./}" rel=""
      case "$p" in
        '${CLAUDE_PLUGIN_ROOT}/'*) rel="${p#\$\{CLAUDE_PLUGIN_ROOT\}/}" ;;
        '$CLAUDE_PLUGIN_ROOT/'*) rel="${p#\$CLAUDE_PLUGIN_ROOT/}" ;;
        "$PLUGIN_ROOT"/*) rel="${p#"$PLUGIN_ROOT"/}" ;;
        /*)
          case "$p" in
            */skills/tier/route.py) rel=skills/tier/route.py ;;
            */skills/visual/*.py) rel="skills/visual/${p##*/}" ;;
            *) return 1 ;;
          esac
          [ "$p" -ef "$PLUGIN_ROOT/$rel" ] || return 1
          ;;
        *) rel="$p" ;;
      esac
      [ "$rel" = skills/tier/route.py ] && return 0
      [[ $rel =~ ^skills/visual/[A-Za-z0-9_-]+\.py$ ]]
    }
    # The test runners, relative or absolute but never under temp or
    # ~/.claude (the session can write there) and never through `..`.
    is_runner() { # path
      local p="${1#./}"
      case "$p" in
        /*) target_class "$p"; [ "$tc" = tree ] || return 1 ;;
      esac
      case "$p" in *"$PH"* | *'$'* | */../* | ../*) return 1 ;; esac
      [[ $p =~ (^|/)tests/[A-Za-z0-9._-]+\.test\.sh$ || $p =~ (^|/)tests/run-all\.sh$ || $p =~ (^|/)tools/replay\.sh$ ]]
    }

    # git is split in two: git_read_check refuses the subcommands that dump a
    # file (show <rev>:<path>, cat-file, grep, diff --no-index, an unparsable global option or
    # a -c alias.* that can rename one of them); git_allowed then admits only
    # the bookkeeping subcommands. An alias cannot shadow a builtin, so `git
    # diff` (short of --no-index) stays allowed even behind a -c alias.* config.
    git_read_check() { # the words after `git` in one segment
      git_is_read "$@" || return 0
      case "$git_read_why" in
        option) refuse_read "may print a file's contents: git global option $git_sub is not one this guard can parse" "$bash_cmd" ;;
        show) refuse_read "prints a file's contents (not a diff) via git show <rev>:<path>" "$bash_cmd" ;;
        alias) refuse_read "may print a file's contents: a git -c alias.* config can rename any subcommand" "$bash_cmd" ;;
        no-index) refuse_read "prints arbitrary files' contents: git diff --no-index (or two paths, one outside the repo) compares any two paths" "$bash_cmd" ;;
        *) refuse_read "prints a file's contents (not a diff) via git $git_read_why" "$bash_cmd" ;;
      esac
    }
    git_allowed() { # the words after `git`
      local a prev="" key
      git_subcommand "$@"
      # A -c key that names a program runs it from inside an allowed subcommand.
      for a in "${@:1:$git_sub_at}"; do
        if [ "$prev" = "-c" ]; then
          key=$(printf '%s' "${a%%=*}" | tr '[:upper:]' '[:lower:]')
          case "$key" in
            core.pager | core.editor | core.sshcommand | core.fsmonitor | core.hookspath | core.askpass | core.gitproxy \
              | sequence.editor | diff.external | diff.*.command | diff.*.textconv | merge.*.driver | pager.* \
              | credential.* | gpg.* | filter.* | include.* | includeif.* | uploadpack.* | protocol.*)
              return 1 ;;
          esac
        fi
        prev="$a"
      done
      # --output=FILE on a diff-family subcommand writes FILE.
      prev=""
      for a in "${@:$((git_sub_at + 1))}"; do
        [ "$prev" = --output ] && cmd_targets+=("$a")
        case "$a" in --output=*) cmd_targets+=("${a#--output=}") ;; esac
        prev="$a"
      done
      case "$git_sub" in
        '' | status | log | diff | show | branch | blame | ls-files | add | commit | tag | stash | push | fetch | pull \
          | rev-parse | rev-list | describe | remote | version | help \
          | check-ignore | check-attr | merge-base | for-each-ref | name-rev)
          return 0 ;;
        switch | checkout)
          # Branch creation only (`switch -c`/`--create`, `checkout -b`):
          # never a bare switch to an existing branch, never overwrite one
          # (`-C`/`--force-create`/`-B`), never discard local changes
          # (`-f`/`--force`/`--discard-changes`/`-m`/`--merge`).
          local br_create=0 br_force=0
          for a in "${@:$((git_sub_at + 1))}"; do
            case "$a" in
              -c | --create | -b) br_create=1 ;;
              -C | --force-create | -B | -f | --force | --discard-changes | -m | --merge) br_force=1 ;;
            esac
          done
          [ "$br_create" = 1 ] && [ "$br_force" = 0 ]
          return
          ;;
        reset)
          # Bookkeeping only: --soft and --mixed (the default) touch HEAD
          # and the index, not the working tree; --hard, --merge and --keep
          # discard local changes and are refused as the write they are.
          for a in "${@:$((git_sub_at + 1))}"; do
            case "$a" in --hard | --merge | --keep) return 1 ;; esac
          done
          return 0
          ;;
        config)
          local get=0
          for a in "${@:$((git_sub_at + 1))}"; do
            case "$a" in
              --get | --get-all | --get-regexp | --get-urlmatch | --list | -l) get=1 ;;
              --unset | --unset-all | --add | --replace-all | --edit | -e | --rename-section | --remove-section) return 1 ;;
            esac
          done
          [ "$get" = 1 ]
          return
          ;;
      esac
      return 1
    }
    # sed without -i, and without a script that writes (w), reads a file in
    # (r) or runs a command (e): the letters are looked for where a command
    # can start, after s///, y/// and /address/ bodies are taken out.
    sed_allowed() { # the words after `sed`
      local a prev="" have_e=0 script_seen=0 sc
      local scripts=()
      local sed_cmd_re='(^|[;{}[:space:]0-9$!/,])[wWrRe]' sed_flag_re='s[gpIiMm0-9]*[ewW]'
      for a in "$@"; do
        if [ -n "$prev" ]; then scripts+=("$a"); prev=""; continue; fi
        case "$a" in
          -i* | --in-place*) return 1 ;;
          -f* | --file | --file=*) return 1 ;;
          -e | --expression) prev="$a"; have_e=1 ;;
          --expression=*) scripts+=("${a#*=}"); have_e=1 ;;
          --*) ;;
          -*)
            case "$a" in *i* | *f*) return 1 ;; esac
            case "$a" in *e) prev="$a"; have_e=1 ;; esac
            ;;
          *)
            if [ "$have_e" = 0 ] && [ "$script_seen" = 0 ]; then scripts+=("$a"); script_seen=1; fi
            ;;
        esac
      done
      for a in "${scripts[@]+"${scripts[@]}"}"; do
        sc=$(printf '%s' "$a" | sed -E -e 's#s/(\\.|[^\\/])*/(\\.|[^\\/])*/#s#g' -e 's#y/[^/]*/[^/]*/#y#g' -e 's#/(\\.|[^\\/])*/#//#g')
        [[ $sc =~ $sed_cmd_re || $sc =~ $sed_flag_re ]] && return 1
      done
      return 0
    }
    # awk without a program that runs commands (system(), a pipe), writes or
    # reads files (print >, getline <), or comes from a file or extension.
    awk_allowed() { # the words after `awk`
      local a prev="" prog="" have_prog=0
      for a in "$@"; do
        if [ -n "$prev" ]; then prev=""; continue; fi
        case "$a" in
          -f* | --file* | -i* | --include* | -l* | --load* | -E* | --exec*) return 1 ;;
          -v | -F) prev="$a" ;;
          -*) ;;
          *) [ "$have_prog" = 0 ] && { prog="$a"; have_prog=1; } ;;
        esac
      done
      local awk_bad_re='system[[:space:]]*\(|getline|(^|[^|])\|([^|]|$)|print[f]?[^;}]*>|@(load|include)'
      [[ $prog =~ $awk_bad_re ]] && return 1
      return 0
    }

    # Judges one segment; refuses on the spot. Sets cmd_targets as a side
    # channel for the write targets a command names itself (tee, sort -o).
    edit_labels=()
    judge_segment() { # record
      local sid piped nw nr k j i t cmd base lookup bad_var=0 reader="" nonflag=0 recursive=0 seg_text op tg
      local words=() args=() rops=() rtgs=() operands=() sep depth cd_arg new_dir
      cmd_targets=()
      tok_parse "$1"
      sid="$tok_sid"; piped="$tok_piped"; nw="$tok_nw"; nr="$tok_nr"
      sep="$tok_sep"; depth="$tok_depth"
      words=("${tok_words[@]+"${tok_words[@]}"}")
      rops=("${tok_rops[@]+"${tok_rops[@]}"}")
      rtgs=("${tok_rtgs[@]+"${tok_rtgs[@]}"}")
      seg_text="${words[*]+"${words[*]}"}"
      seg_text="${seg_text//$PH/\$(...)}"

      # The tokenizer has already skipped what runs the next word rather
      # than being the command (VAR=val assignments, the command/builtin/
      # exec/env prefixes with their flags, the shell keywords that
      # introduce a command) and a for/select/case header, which names no
      # command of its own: without that a loop variable like `f` in `for f
      # in docs/*.md` is mistaken for the command. The assignments among
      # the skipped words are noted here, in order.
      i="$tok_at"; lookup="$tok_lookup"
      for k in "${tok_assigns[@]+"${tok_assigns[@]}"}"; do
        t="${words[$k]}"
        is_exec_var "${t%%=*}" && bad_var=1
        note_assignment "${t%%=*}" "${t#*=}"
      done
      cmd=""
      [ "$i" -lt "$nw" ] && cmd="${words[$i]}"
      [ $((i + 1)) -lt "$nw" ] && args=("${words[@]:$((i + 1))}")
      base="${cmd##*/}"

      # A segment with no command word at all, but an input redirect, is
      # `$(< file)` (or the backtick/`x=$(< file)` equivalents): bash
      # expands that to the file's contents with no reader program in
      # sight. tok_input_redirects (hooks/lib/tokenize.sh) already skips
      # a `for`/`select`/`case` header (also cmd-less, but never carrying
      # a redirect of its own) and /dev/null/stdin; a scratch operand is
      # exempt here the same as it is for a reader like `cat`.
      if [ -z "$cmd" ]; then
        tok_input_redirects
        for tg in "${tok_inputs[@]+"${tok_inputs[@]}"}"; do
          is_scratch_operand "$tg" || refuse_read 'reads a file'"'"'s contents via $(< file)' "$bash_cmd"
        done
      fi

      if [ -n "$cmd" ] && [ "$lookup" = 0 ]; then
        # 1. Reads: git's file-dumping subcommands, then the generic readers.
        # cp and mv read their sources, not their destination (the last
        # operand, scratch or not).
        [ "$base" = git ] && git_read_check "${args[@]+"${args[@]}"}"
        local last_operand=-1
        case "$base" in
          cp | mv)
            for ((j = 0; j < ${#args[@]}; j++)); do [[ ${args[$j]} == -* ]] || last_operand=$j; done ;;
        esac
        for ((j = 0; j < ${#args[@]}; j++)); do
          t="${args[$j]}"
          [ "$j" = "$last_operand" ] && continue
          [ -z "$t" ] || [ "$t" = "-" ] && continue
          if [[ $t == -* ]]; then
            [[ $t =~ ^-[A-Za-z]*[rR] || $t == --recursive* ]] && recursive=1
            continue
          fi
          is_scratch_operand "$t" && continue
          operands+=("$t")
        done
        nonflag=${#operands[@]}
        # An input redirect from a repository file feeds it to the reader.
        for ((j = 0; j < nr; j++)); do
          op="${rops[$j]}"
          while [[ $op == [0-9]* ]]; do op="${op#?}"; done
          [ "$op" = "<" ] && ! is_scratch_operand "${rtgs[$j]}" && nonflag=$((nonflag + 1))
        done
        case "$base" in
          cat | head | tail | less | more | nl | od | xxd | strings | find | cp | mv)
            [ "$nonflag" -ge 1 ] && reader="$base" ;;
          rg | ag | ack)
            # These default to the working tree, so at the head of a
            # pipeline they dump the whole repo with no path operand at all.
            { [ "$piped" = 0 ] || [ "$nonflag" -ge 2 ]; } && reader="$base" ;;
          grep | egrep | fgrep)
            # -r/-R walks the tree from the working directory; without it, a
            # bare `grep pattern` only filters stdin.
            { [ "$recursive" = 1 ] || [ "$nonflag" -ge 2 ]; } && reader="$base" ;;
          jq | awk)
            [ "$nonflag" -ge 2 ] && reader="$base" ;;
          sed)
            # An in-place or writing sed is refused by the allowlist below
            # as the write it is, not as a read.
            [ "$nonflag" -ge 2 ] && sed_allowed "${args[@]}" && reader="$base" ;;
        esac
        # An inline interpreter that opens a file. A write-mode open is the
        # MODE ARGUMENT (`open(p, "w")`, `open(p, mode="a")`), so the
        # write-mode calls are stripped first; any `open(` still standing is
        # a read, as are pathlib's .read_text()/.read_bytes(). The plugin's
        # own scripts take data on stdin, not code, and are not scanned.
        if [ -z "$reader" ] && ! is_plugin_script "${args[0]:-}"; then
          local text="${words[*]:$i} ${bodies[$sid]:-}" py
          local mode_arg="[\"'][rwaxbt+]*[wax][rwaxbt+]*[\"']"
          case "$base" in
            python | python2 | python3)
              py=$(printf '%s\n' "$text" | sed -E \
                -e "s#open\([^)]*,[[:space:]]*(mode[[:space:]]*=[[:space:]]*)?$mode_arg##g" \
                -e "s#open\([[:space:]]*(mode[[:space:]]*=[[:space:]]*)?$mode_arg##g")
              [[ $py =~ open\(|\.read_text\(|\.read_bytes\( ]] && reader=python
              ;;
            perl) [[ $text =~ (^|[[:space:]])-[A-Za-z]*n[A-Za-z]*e ]] && reader=perl ;;
            ruby) [[ $text =~ (^|[[:space:]])-e([[:space:]]|$) && $text == *File.read* ]] && reader=ruby ;;
          esac
        fi
        [ -n "$reader" ] && refuse_read "reads a file's contents via $reader" "$bash_cmd"
      fi

      # 2. The allowlist, with the assignments in front of the command first.
      [ "$bad_var" = 1 ] && refuse_segment "$seg_text"
      if [ -n "$cmd" ] && [ "$lookup" = 0 ]; then
        case " ${CLAUDE_1337_BASH_ALLOW:-} " in
          *" $cmd "*) ;;
          *)
            case "$cmd" in
              *"$PH"*) refuse_segment "$seg_text" ;;
              */*) is_runner "$cmd" || is_plugin_script "$cmd" || refuse_segment "$seg_text" ;;
              ls | cat | head | tail | wc | grep | egrep | fgrep | jq | cut | tr | diff | stat | file | which | type \
                | echo | printf | true | false | test | '[' | cd | pwd | date | basename | dirname | realpath | sleep \
                | claude | tasqx | continue | break | ':') ;;
              tee)
                for t in "${args[@]+"${args[@]}"}"; do [[ $t == -* ]] || cmd_targets+=("$t"); done ;;
              mkdir)
                # A directory under temp or ~/.claude is the session's own
                # scratch, same as a file written there; elsewhere it is a
                # tree write. -m's mode argument is not a path.
                j=0
                for t in "${args[@]+"${args[@]}"}"; do
                  [ "$j" = 1 ] && { j=0; continue; }
                  case "$t" in
                    -m | --mode) j=1 ;;
                    -m?* | --mode=*) ;;
                    -*) ;;
                    *) cmd_targets+=("$t") ;;
                  esac
                done
                ;;
              sort)
                j=0
                for t in "${args[@]+"${args[@]}"}"; do
                  [ "$j" = 1 ] && { cmd_targets+=("$t"); j=0; continue; }
                  case "$t" in
                    -o | --output) j=1 ;;
                    --output=*) cmd_targets+=("${t#--output=}") ;;
                    -o?*) cmd_targets+=("${t#-o}") ;;
                  esac
                done
                ;;
              uniq)
                # uniq's second operand is its output file.
                j=0
                for t in "${args[@]+"${args[@]}"}"; do [[ $t == -* ]] || j=$((j + 1)); [ "$j" = 2 ] && { cmd_targets+=("$t"); break; }; done
                ;;
              mktemp)
                # The file lands in DIR/TEMPLATE: -p DIR or --tmpdir[=]DIR
                # names the directory (a word after a bare --tmpdir is taken
                # as one, which refuses more than mktemp would), -t puts it
                # under $TMPDIR, a template alone is relative to the working
                # directory, and nothing at all means $TMPDIR.
                local mk_dir="" mk_next=0 mk_tmp=0 mk_tpl=""
                for t in "${args[@]+"${args[@]}"}"; do
                  if [ "$mk_next" = 1 ]; then mk_dir="$t"; mk_next=0; continue; fi
                  case "$t" in
                    -p | --tmpdir) mk_next=1 ;;
                    -p?*) mk_dir="${t#-p}" ;;
                    --tmpdir=*) mk_dir="${t#--tmpdir=}" ;;
                    -t) mk_tmp=1 ;;
                    -*) ;;
                    *) mk_tpl="$t" ;;
                  esac
                done
                if [ -n "$mk_dir" ]; then
                  cmd_targets+=("$mk_dir/${mk_tpl:-tmp.XXXXXXXXXX}")
                elif [ "$mk_tmp" = 0 ] && [ "$mk_next" = 0 ] && [ -n "$mk_tpl" ]; then
                  cmd_targets+=("$mk_tpl")
                fi
                ;;
              find)
                for t in "${args[@]+"${args[@]}"}"; do
                  case "$t" in -delete | -exec | -execdir | -ok | -okdir | -fprint | -fprint0 | -fprintf | -fls) refuse_segment "$seg_text" ;; esac
                done
                ;;
              rg)
                for t in "${args[@]+"${args[@]}"}"; do case "$t" in --pre | --pre=*) refuse_segment "$seg_text" ;; esac; done ;;
              sed) sed_allowed "${args[@]+"${args[@]}"}" || refuse_segment "$seg_text" ;;
              awk) awk_allowed "${args[@]+"${args[@]}"}" || refuse_segment "$seg_text" ;;
              git) git_allowed "${args[@]+"${args[@]}"}" || refuse_segment "$seg_text" ;;
              python3) is_plugin_script "${args[0]:-}" || refuse_segment "$seg_text" ;;
              bash | sh)
                # `-n` parses the script for syntax errors and runs nothing
                # in it, so any path is fine, not just a test runner.
                [ "${args[0]:-}" = "-n" ] || is_runner "${args[0]:-}" || refuse_segment "$seg_text" ;;
              ripwire)
                local edit=0 edit_payload=0 plan=0 apply=0
                for t in "${args[@]+"${args[@]}"}"; do
                  case "$t" in
                    --replace-symbol-body | --replace-symbol-body=* | --insert-before-symbol | --insert-before-symbol=* \
                      | --insert-after-symbol | --insert-after-symbol=*) edit=1 ;;
                    --edit-payload | --edit-payload=*) edit_payload=1 ;;
                    --edit-plan | --edit-plan=*) plan=1 ;;
                    --apply) apply=1 ;;
                  esac
                done
                if [ "$edit" = 1 ] && [ "$edit_payload" = 1 ]; then
                  edit_labels+=("Bash ripwire-symbol-edit")
                elif [ "$plan" = 1 ] && [ "$apply" = 1 ]; then
                  edit_labels+=("Bash ripwire-edit-plan")
                fi
                ;;
              *) refuse_segment "$seg_text" ;;
            esac
            ;;
        esac
      fi

      # 3. Where the segment writes: redirects, and the targets a command
      # names itself.
      for ((j = 0; j < nr; j++)); do
        op="${rops[$j]}"; tg="${rtgs[$j]}"
        while [[ $op == [0-9]* ]]; do op="${op#?}"; done
        case "$op" in
          '>' | '>>' | '>|' | '&>' | '&>>' | '<>') judge_target "$tg" ;;
          '>&') [[ $tg =~ ^([0-9]+-?|-)$ ]] || judge_target "$tg" ;;
        esac
      done
      for tg in "${cmd_targets[@]+"${cmd_targets[@]}"}"; do judge_target "$tg"; done

      # 4. Track the effective directory later targets in this command
      # resolve relative to (#726). This runs after the segment's own
      # targets are judged, since bash opens a cd's redirects before the cd
      # runs. Only a plain cd/pushd at top level, not in a pipeline, with
      # exactly one literal argument, updates it; anything else (no
      # argument, `cd -`, an argument with $, a backtick or a glob, being
      # inside a group or substitution, or reading a pipe) makes it
      # unknown from here on, same as never having seen a cd. It carries to
      # the next segment only across && (hooks/lib/tokenize.sh's tok_sep):
      # after ; || | & or a newline the cd may have failed or run in a
      # subshell, so the shell may still be in the old directory. A
      # group's closing ) breaks it too, since the operator after the group
      # ends an empty segment the lexer does not report. A cd reached
      # through || (`a || cd x && ...` skips it when a succeeds) or negated
      # with ! (the rest runs only when it failed) is unknown as well.
      if [ -n "$cmd" ] && [ "$lookup" = 0 ]; then
        case "$base" in
          cd | pushd)
            if [ "$depth" != 0 ] || [ "$piped" = 1 ] || [ "$prev_top_sep" = '||' ] \
              || [ "${#args[@]}" -ne 1 ] || [[ " ${words[*]:0:$i} " == *" ! "* ]]; then
              eff_dir_known=0
            else
              cd_arg="${args[0]}"; new_dir=""
              case "$cd_arg" in
                '-' | *'$'* | *'`'* | *'*'* | *'?'* | *'['* | *"$PH"*) ;;
                /*) new_dir="$cd_arg" ;;
                '~') new_dir="${HOME:-}" ;;
                '~/'*) [ -n "${HOME:-}" ] && new_dir="$HOME/${cd_arg#\~/}" ;;
                *) [ "$eff_dir_known" = 1 ] && new_dir="$eff_dir/$cd_arg" ;;
              esac
              if [ -n "$new_dir" ] && [ "${new_dir:0:1}" = / ]; then
                eff_dir="$(normalize_path "$new_dir")"
                eff_dir_known=1
              else
                eff_dir_known=0
              fi
            fi
            ;;
        esac
      fi
      if [ "$depth" = 0 ]; then
        prev_top_sep="$sep"
        case "$sep" in '&&' | '') ;; *) eff_dir_known=0 ;; esac
      else
        [ "$sep" = ')' ] && eff_dir_known=0
      fi
    }

    for rec in "${segs[@]+"${segs[@]}"}"; do
      judge_segment "$rec"
    done
    # Every segment passed: only now does a ripwire edit spend its unit, so a
    # command refused for another segment costs nothing.
    for label in "${edit_labels[@]+"${edit_labels[@]}"}"; do
      count_edit "$label" || exit 2
    done
    exit 0
    ;;
  Edit)
    lines=$(printf '%s' "$payload" | jq -r 'def n: if . == "" then 0 else (split("\n") | length) - (if endswith("\n") then 1 else 0 end) end;
      [(.tool_input.old_string // "" | n), (.tool_input.new_string // "" | n)] | max' 2>/dev/null) || exit 0
    ;;
  MultiEdit)
    lines=$(printf '%s' "$payload" | jq -r 'def n: if . == "" then 0 else (split("\n") | length) - (if endswith("\n") then 1 else 0 end) end;
      [.tool_input.edits[]? | [(.old_string // "" | n), (.new_string // "" | n)] | max] | add // 0' 2>/dev/null) || exit 0
    ;;
  *)
    printf 'blocked (1337 orchestrator mode): %s on %s writes a whole file, which the main session may not do outside ~/.claude and temp directories. Dispatch it to 1337:builder with a self-contained brief.\n' \
      "$tool" "$file" >&2
    exit 2
    ;;
esac

if [ "${lines:-0}" -le "$MAX_LINES" ]; then
  count_edit "$tool $file" || exit 2
  exit 0
fi

printf 'blocked (1337 orchestrator mode): %s on %s is more than %d lines. Dispatch it to 1337:builder with a self-contained brief.\n' \
  "$tool" "$file" "$MAX_LINES" >&2
exit 2
