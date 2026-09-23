#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit|Bash, active only in
# orchestrator mode (plugin option `orchestrator`, CLAUDE_1337_ORCHESTRATOR=1,
# or EVAL_CLAUDE_1337_ORCHESTRATOR=1, the switch eval cases use since `claude
# plugin eval` cases may only set EVAL_* variables).
# Keeps the main session an orchestrator: subagent calls (payload carries
# agent_id) always pass; the main session may make edits of <= MAX_LINES
# lines (CLAUDE_1337_MAX_LINES, default 20; an edit counts the larger of its
# old and new text, a MultiEdit the sum over its edits) and write under
# ~/.claude or a temp dir, where a code file is still refused.
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
# Quoted text and heredoc bodies are data, not commands: the lexer below keeps
# a quoted span inside its word and drops a heredoc body before any segment is
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
# the same on/off condition.
#
# Exit 2 + stderr refuses; exit 0 allows. jq missing in orchestrator mode
# refuses (the guard cannot read the call, so it fails closed); a payload jq
# cannot parse passes.
set -u

MAX_LINES="${CLAUDE_1337_MAX_LINES:-20}"
case "$MAX_LINES" in ''|*[!0-9]*) MAX_LINES=20 ;; esac

[ "${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-false}" = "true" ] || [ "${CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || [ "${EVAL_CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || exit 0

if [ "${1:-}" = "--rules" ]; then
  cat "$(dirname "$0")/orchestrator.md"
  exit 0
fi

command -v jq >/dev/null 2>&1 || {
  echo 'blocked (1337 orchestrator mode): jq is missing from PATH, so the guard cannot read this tool call and refuses it; install jq or turn orchestrator mode off.' >&2
  exit 2
}

PLUGIN_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
# Code files are builder work regardless of directory: refused even under the
# temp-dir exemption. Data files under temp stay allowed. dispatch-nudge.sh
# carries the same line; tests/dispatch-nudge.test.sh keeps them equal.
code_ext='py|sh|bash|js|mjs|cjs|ts|rb|go|rs|php|pl|lua|html|htm|css'

is_code() { # path
  local lc
  lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [[ $lc =~ \.($code_ext)$ ]]
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
# hooks/read-cap.sh: ripwire maps code, but says nothing useful about a JSON
# config, a lockfile, a transcript or a prose doc, so those go to 1337:scout,
# which reads in its own context. tests/rule-copies.test.sh keeps the copies
# in the two files aligned.
read_route() {
  if command -v ripwire >/dev/null 2>&1; then
    printf '%s' 'For code: `ripwire <dir> --for="<what you are after>" --legend=compact`, then `--expand=SYM`, `--callers=SYM`, `--impact=SYM`, `--uses=SYM`, `--grep=STR` as follow-ups.
For anything else (config, lockfile, transcript, prose), or when the file contents themselves are wanted: dispatch 1337:scout with the question; it reads in its own context.'
  else
    printf '%s' 'Dispatch 1337:scout with the question; it reads in its own context.'
  fi
}

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
  printf 'blocked (1337 orchestrator mode): Bash command writes files (%.80s). Dispatch it to 1337:builder with a self-contained brief; the main session may only write under ~/.claude and temp directories.\n' "$1" >&2
  exit 2
}

payload="$(cat)"

agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
[ -n "$agent_id" ] && exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || exit 0

# ~/.claude and temp dirs are the session's own scratch. A `..` step never
# counts as inside one, and a code file written under temp is still a script.
tmp_real="${TMPDIR:-}"
case "$tmp_real" in /?*) tmp_real="${tmp_real%/}" ;; *) tmp_real="" ;; esac
case "$file" in
  */../*|*/..) ;;
  "${HOME:-/nonexistent}"/.claude/*) exit 0 ;;
  /tmp/*|/private/tmp/*|/var/folders/*|"${tmp_real:-/nonexistent}"/*)
    if [ "$tool" = Write ] && is_code "$file"; then
      printf 'blocked (1337 orchestrator mode): Write on %s writes a code file. Scripts are builder work even under temp directories; dispatch it to 1337:builder with a self-contained brief.\n' "$file" >&2
      exit 2
    fi
    exit 0
    ;;
esac

# The Bash lexer: a small shell tokenizer in awk that reads the whole command
# and prints one record per segment, fields separated by \037:
#   S id piped nwords word... nredirects op target ... E
# plus `B id body` for the heredoc bodies a segment opened (only the inline-
# interpreter read check looks at them) and `X reason` for a construct the
# guard refuses to judge. Quotes are removed from words the way the shell
# removes them; a $( ), backtick or <( ) in a word leaves \002 in its place
# and its contents come out as segments of their own. Newlines inside a
# quoted word, and tabs, turn into spaces.
lexer='
function newctx(   id) { id = ++NC; nw[id] = 0; nr[id] = 0; cw[id] = ""; inw[id] = 0; cq[id] = 0; pend[id] = ""; pip[id] = 0; cur[id] = ++SID; return id }
function addc(c, ch) { cw[c] = cw[c] ch; inw[c] = 1 }
function clean(x) { gsub(/[\n\r\t]/, " ", x); gsub(US, " ", x); return x }
function flushword(c) {
  if (!inw[c]) return
  if (pend[c] != "") {
    nr[c]++; rop[c, nr[c]] = pend[c]; rtg[c, nr[c]] = cw[c]
    if (pend[c] ~ /^[0-9]*<<-?$/) { nh++; hmark[nh] = cw[c]; hdash[nh] = (pend[c] ~ /-$/); hquoted[nh] = cq[c]; hseg[nh] = cur[c] }
    pend[c] = ""
  } else { nw[c]++; w[c, nw[c]] = cw[c] }
  cw[c] = ""; inw[c] = 0; cq[c] = 0
}
function endseg(c, sep,   k, out) {
  flushword(c)
  if (pend[c] != "") { err = "a redirect with no target"; pend[c] = "" }
  if (nw[c] > 0 || nr[c] > 0) {
    out = "S" US cur[c] US pip[c] US nw[c]
    for (k = 1; k <= nw[c]; k++) out = out US clean(w[c, k])
    out = out US nr[c]
    for (k = 1; k <= nr[c]; k++) out = out US rop[c, k] US clean(rtg[c, k])
    print out US "E"
  }
  nw[c] = 0; nr[c] = 0; cur[c] = ++SID
  pip[c] = (sep == "PIPE")
}
# $( ... ), <( ... ), >( ... ): a new command context. $(( )) is arithmetic,
# not a command, and is skipped whole.
function opensub(i, c,   j, depth, ch) {
  if (substr(s, i, 3) == "$((") {
    j = i + 3; depth = 2
    while (j <= n && depth > 0) { ch = substr(s, j, 1); if (ch == "(") depth++; else if (ch == ")") depth--; j++ }
    if (substr(s, i + 3, j - i - 3) ~ /\$\(|`/) err = "a command substitution inside arithmetic"
    addc(c, PH)
    return j
  }
  addc(c, PH)
  sp++; st[sp] = "S"; cx[sp] = newctx()
  return i + 2
}
function heredocs(i,   j, k, e, line, t, body) {
  j = i + 1
  for (k = hdone + 1; k <= nh; k++) {
    body = ""
    while (j <= n) {
      e = index(substr(s, j), "\n")
      if (e == 0) { line = substr(s, j); j = n + 1 } else { line = substr(s, j, e - 1); j = j + e }
      t = line
      if (hdash[k]) sub(/^\t+/, "", t)
      if (t == hmark[k]) break
      body = body line "\n"
    }
    if (!hquoted[k] && (body ~ /\$\(/ || index(body, "`") > 0)) err = "a command substitution inside an unquoted heredoc body"
    bodies[hseg[k]] = bodies[hseg[k]] body
  }
  hdone = nh
  return j
}
function lex(   i, c, d, top, C, op, k) {
  n = length(s); sp = 0; st[0] = "N"; cx[0] = newctx()
  i = 1
  while (i <= n) {
    c = substr(s, i, 1); d = substr(s, i + 1, 1); top = st[sp]; C = cx[sp]
    if (top == "Q") { if (c == SQ) sp--; else addc(C, c); i++; continue }
    if (top == "A") {
      if (c == "\\") { addc(C, d); i += 2; continue }
      if (c == SQ) sp--; else addc(C, c)
      i++; continue
    }
    if (top == "D") {
      if (c == "\\") {
        if (d == DQ || d == "\\" || d == "$" || d == "`") { addc(C, d); i += 2 }
        else if (d == "\n") i += 2
        else { addc(C, c); i++ }
        continue
      }
      if (c == DQ) { sp--; i++; continue }
      if (c == "$" && d == "(") { i = opensub(i, C); continue }
      if (c == "`") { addc(C, PH); sp++; st[sp] = "B"; cx[sp] = newctx(); i++; continue }
      addc(C, c); i++; continue
    }
    # Command context: top level, inside $( ), backticks, or a ( ) group.
    if (c == "\\") { if (d == "\n") { i += 2; continue } addc(C, d); cq[C] = 1; i += 2; continue }
    if (c == SQ) { sp++; st[sp] = "Q"; cx[sp] = C; inw[C] = 1; cq[C] = 1; i++; continue }
    if (c == "$" && d == SQ) { sp++; st[sp] = "A"; cx[sp] = C; inw[C] = 1; cq[C] = 1; i += 2; continue }
    if (c == DQ) { sp++; st[sp] = "D"; cx[sp] = C; inw[C] = 1; cq[C] = 1; i++; continue }
    if (c == "$" && d == "(") { i = opensub(i, C); continue }
    if ((c == "<" || c == ">") && d == "(") { i = opensub(i, C); continue }
    if (c == "`") {
      if (top == "B") { endseg(C, "END"); sp--; i++; continue }
      addc(C, PH); sp++; st[sp] = "B"; cx[sp] = newctx(); i++; continue
    }
    if (c == ")") {
      if (top == "S") { endseg(C, "END"); sp--; i++; continue }
      endseg(C, "SEQ")
      if (top == "P") sp--
      i++; continue
    }
    if (c == "(") { endseg(C, "SEQ"); sp++; st[sp] = "P"; cx[sp] = C; i++; continue }
    if (c == "#" && !inw[C]) { while (i <= n && substr(s, i, 1) != "\n") i++; continue }
    if (c == "\n") {
      flushword(C)
      if (nh > hdone) i = heredocs(i); else i++
      endseg(C, "SEQ"); continue
    }
    if (c == ";") { endseg(C, "SEQ"); i++; if (d == ";") i++; continue }
    if (c == "|") {
      if (d == "|") { endseg(C, "SEQ"); i += 2; continue }
      endseg(C, "PIPE"); i++; if (d == "&") i++
      continue
    }
    if (c == "&") {
      if (d == "&") { endseg(C, "SEQ"); i += 2; continue }
      if (d == ">") {
        flushword(C); op = "&>"; i += 2
        if (substr(s, i, 1) == ">") { op = "&>>"; i++ }
        if (pend[C] != "") err = "a redirect with no target"
        pend[C] = op; continue
      }
      endseg(C, "SEQ"); i++; continue
    }
    if (c == "<" || c == ">") {
      op = ""
      if (inw[C] && !cq[C] && cw[C] ~ /^[0-9]+$/) { op = cw[C]; cw[C] = ""; inw[C] = 0 } else flushword(C)
      op = op c; i++
      if (c == "<") {
        if (substr(s, i, 2) == "<<") { op = op "<<"; i += 2 }
        else if (substr(s, i, 1) == "<") { op = op "<"; i++; if (substr(s, i, 1) == "-") { op = op "-"; i++ } }
        else if (substr(s, i, 1) == ">" || substr(s, i, 1) == "&") { op = op substr(s, i, 1); i++ }
      } else if (substr(s, i, 1) == ">" || substr(s, i, 1) == "|" || substr(s, i, 1) == "&") { op = op substr(s, i, 1); i++ }
      if (pend[C] != "") err = "a redirect with no target"
      pend[C] = op; continue
    }
    if (c == " " || c == "\t" || c == "\r") { flushword(C); i++; continue }
    addc(C, c); i++
  }
  for (k = sp; k >= 0; k--) if (st[k] == "N" || st[k] == "S" || st[k] == "B") endseg(cx[k], "END")
  for (k in bodies) print "B" US k US clean(bodies[k])
  if (err != "") print "X" US err
}
BEGIN { US = sprintf("%c", 31); PH = sprintf("%c", 2); SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); s = "" }
{ s = (NR > 1) ? s "\n" $0 : $0 }
END { lex() }
'

case "$tool" in
  Bash)
    bash_cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    [ -n "$bash_cmd" ] || exit 0
    . "$(dirname "$0")/lib/git-subcommand.sh"
    US=$(printf '\037')
    PH=$(printf '\002')
    lex_out=$(printf '%s\n' "$bash_cmd" | awk "$lexer") || {
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

    # Sets rt: the target with assigned variables, $HOME, ~ and $TMPDIR put
    # in, as far as they can be.
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
      rt="$t"
    }
    # Sets tc: dev (/dev/null and friends), claude (~/.claude), temp, or
    # tree for everything else, including anything still dynamic.
    target_class() { # resolved target
      case "$1" in
        *"$PH"* | *'$'* | *'`'* | */../* | */.. | ../* | ..) tc=tree ;;
        /dev/null | /dev/stdout | /dev/stderr | /dev/tty | /dev/fd/*) tc=dev ;;
        "${HOME:-/nonexistent}"/.claude/*) tc=claude ;;
        /tmp | /tmp/* | /private/tmp | /private/tmp/* | /var/folders | /var/folders/* \
          | "${tmp_real:-/nonexistent}" | "${tmp_real:-/nonexistent}"/*) tc=temp ;;
        *) tc=tree ;;
      esac
    }
    judge_target() { # target, [nocode]
      resolve_target "$1"
      target_class "$rt"
      case "$tc" in dev | claude) return 0 ;; esac
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
      [ "$tc" != tree ]
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
    # file (show <rev>:<path>, cat-file, grep, an unparsable global option or
    # a -c alias.* that can rename one of them); git_allowed then admits only
    # the bookkeeping subcommands. An alias cannot shadow a builtin, so `git
    # diff` stays allowed even behind a -c alias.* config.
    git_read_check() { # the words after `git` in one segment
      local git_reader="" git_arg prev="" alias_cfg=0
      git_subcommand "$@"
      for git_arg in "${@:1:$git_sub_at}"; do
        if [ "$prev" = "-c" ]; then
          case "$(printf '%s' "$git_arg" | tr '[:upper:]' '[:lower:]')" in
            alias.*) alias_cfg=1 ;;
          esac
        fi
        prev="$git_arg"
      done
      case "$git_sub" in
        show)
          for git_arg in "${@:$((git_sub_at + 1))}"; do
            case "$git_arg" in
              -*) ;;
              *:*) git_reader='git show <rev>:<path>'; break ;;
            esac
          done
          ;;
        cat-file) git_reader='git cat-file' ;;
        grep) git_reader='git grep' ;;
        diff) alias_cfg=0 ;;
        -*)
          refuse_read "may print a file's contents: git global option $git_sub is not one this guard can parse" "$bash_cmd"
          ;;
      esac
      if [ -n "$git_reader" ]; then
        refuse_read "prints a file's contents (not a diff) via $git_reader" "$bash_cmd"
      fi
      if [ "$alias_cfg" = 1 ]; then
        refuse_read "may print a file's contents: a git -c alias.* config can rename any subcommand" "$bash_cmd"
      fi
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
          | rev-parse | remote | version | help)
          return 0 ;;
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
      local f sid piped nw nr k j i t cmd base lookup=0 bad_var=0 reader="" nonflag=0 recursive=0 seg_text op tg
      local words=() args=() rops=() rtgs=() operands=()
      cmd_targets=()
      IFS="$US" read -r -a f <<<"$1"
      sid="${f[1]}"; piped="${f[2]}"; nw="${f[3]}"
      [ "$nw" -gt 0 ] && words=("${f[@]:4:$nw}")
      k=$((4 + nw)); nr="${f[$k]}"
      for ((j = 0; j < nr; j++)); do
        rops+=("${f[$((k + 1 + 2 * j))]}")
        rtgs+=("${f[$((k + 2 + 2 * j))]}")
      done
      seg_text="${words[*]+"${words[*]}"}"
      seg_text="${seg_text//$PH/\$(...)}"

      # Skip what runs the next word rather than being the command:
      # VAR=val assignments, the command/builtin/exec/env prefixes with their
      # flags, and the shell keywords that introduce a command.
      i=0
      while [ "$i" -lt "$nw" ]; do
        t="${words[$i]}"
        if [[ $t =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
          is_exec_var "${BASH_REMATCH[1]}" && bad_var=1
          note_assignment "${BASH_REMATCH[1]}" "${t#*=}"
          i=$((i + 1)); continue
        fi
        case "$t" in
          command | builtin)
            i=$((i + 1))
            while [ "$i" -lt "$nw" ] && [[ ${words[$i]} == -* ]]; do
              case "${words[$i]}" in *v* | *V*) lookup=1 ;; esac
              i=$((i + 1))
            done
            continue
            ;;
          exec | env)
            i=$((i + 1))
            while [ "$i" -lt "$nw" ] && [[ ${words[$i]} == -* ]]; do
              case "$t ${words[$i]}" in
                "exec -a" | "env -u" | "env -C" | "env --unset" | "env --chdir") i=$((i + 1)) ;;
              esac
              i=$((i + 1))
            done
            continue
            ;;
          '!' | '{' | '}' | if | then | else | elif | do | while | until | time | fi | done | esac)
            i=$((i + 1)); continue ;;
        esac
        break
      done
      cmd=""
      [ "$i" -lt "$nw" ] && cmd="${words[$i]}"
      [ $((i + 1)) -lt "$nw" ] && args=("${words[@]:$((i + 1))}")
      base="${cmd##*/}"

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
                | claude | tasqx) ;;
              tee)
                for t in "${args[@]+"${args[@]}"}"; do [[ $t == -* ]] || cmd_targets+=("$t"); done ;;
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
              bash | sh) is_runner "${args[0]:-}" || refuse_segment "$seg_text" ;;
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
