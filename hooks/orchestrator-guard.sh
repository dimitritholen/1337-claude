#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit|Bash, active only in
# orchestrator mode (plugin option `orchestrator`, or CLAUDE_1337_ORCHESTRATOR=1).
# Keeps the main session an orchestrator: subagent calls (payload carries
# agent_id) always pass; the main session may make edits of <= MAX_LINES new
# lines and write under ~/.claude or a temp dir. Bash commands that write
# files (redirects, tee, sed -i) are refused the same way — the default
# "create a file" path is a Bash redirect, not Write. A bare heredoc only
# feeds stdin and passes; `cat <<EOF > file` is caught by its redirect.
# Heredoc bodies fed to anything but an interpreter are data, not commands:
# they are stripped from the text before the write-pattern greps run, so a
# commit message body mentioning `sed -i` or `> file.py` is not mistaken for
# one. Everything else is refused with a pointer to 1337:builder.
#
# Bash commands that DUMP a file's contents into context (cat, head, tail,
# sed -n/awk/grep/jq over a path, find, cp/mv out of the tree, an inline
# interpreter that opens a file) are refused too, for the same reason the
# read-cap hook watches Read|Grep|Glob: the main session must not pour whole
# files into its own expensive context. A tree scanner needs no path operand
# to dump one: rg/ag/ack at the head of a pipeline, and grep -r, read the
# working tree by default and are refused with or without a path. ripwire,
# git inspection commands, ls, tasqx, and the test/build runners stay
# allowlisted; a pipeline stage that only filters another command's stdout
# (no file operand of its own, e.g. `ps aux | grep x`, `git log | grep fix`)
# is not a reader either, and neither is a bare `grep pattern` on stdin.
# The check walks every segment of the command, so the separators have to be
# real ones: text inside single or double quotes is data, and its contents are
# masked before the split, or a commit message or an echo that merely NAMES a
# refused command parses as one. `$( )` and backticks are executed even inside
# double quotes, so they stay live; an unterminated quote is parsed as commands
# rather than masked away.
# Operands under a temp dir or ~/.claude are the session's own scratch, not
# repository payload, and do not count — the same carve-out read-cap.sh
# makes. The refusal names the two ways forward in the same words as
# hooks/read-cap.sh; tests/rule-copies.test.sh keeps the copies aligned.
#
# One Bash write route stays open: ripwire's own symbol edit
# (--replace-symbol-body / --insert-before-symbol / --insert-after-symbol with
# --edit-payload), and its transactional twin --edit-plan=FILE with --apply.
# Both resolve the definition(s) themselves and answer with a receipt — region,
# blob_sha, edit_check — so they are the only way to change code without the
# session having read the file first. They write into the repository, and each
# draws on the same per-session edit budget as a small Edit, so the allowance
# stays honest. A ripwire run without --edit-payload is a map query: it neither
# writes nor counts. Likewise --edit-plan with --dry-run only preflights the
# plan; it does not write and does not count.
#
# That scratch carve-out is about where output LANDS, not about the command
# mentioning a scratch path somewhere: `cat src/lib.rs > /tmp/out.txt` reads
# repository payload whatever its target, and copying payload into temp to
# read it back from there is a two-step bypass of the whole rule. So the
# write exemption tests the redirect/tee/sed -i target only, and the
# read-dump check runs on the source operands either way.
#
# With --rules it prints hooks/orchestrator.md instead (SessionStart), under the same
# on/off condition.
#
# EVAL_CLAUDE_1337_ORCHESTRATOR=1 is the switch eval cases use, since `claude plugin
# eval` cases may only set EVAL_* variables.
#
# Exit 2 + stderr refuses; exit 0 allows. Every failure path exits 0.
# 1337: later: Bash rm/mkdir from the main session still write the tree; add
# those to the write-patterns if that loophole gets used in practice. cp/mv
# are caught by the read-dump check, on their source operand.
set -u

MAX_LINES=20

[ "${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-false}" = "true" ] || [ "${CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || [ "${EVAL_CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] || exit 0

if [ "${1:-}" = "--rules" ]; then
  cat "$(dirname "$0")/orchestrator.md"
  exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0

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

payload="$(cat)"

agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
[ -n "$agent_id" ] && exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || exit 0

case "$file" in
  "$HOME"/.claude/*|/tmp/*|/private/tmp/*|/var/folders/*) exit 0 ;;
esac

case "$tool" in
  Bash)
    bash_cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    [ -n "$bash_cmd" ] || exit 0
    first_word=$(printf '%s\n' "$bash_cmd" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]* )*//' | awk '{print $1}')
    # ripwire's symbol edit and its --edit-plan twin: the sanctioned ways to
    # change code the session has not read, so they write where every other
    # Bash write is refused, and each spends one unit of the same edit
    # budget. A payload arriving on stdin through a heredoc is part of the
    # edit, not an inline script, so this runs before the checks below.
    # --edit-plan only writes with --apply; --dry-run preflights and must
    # stay uncounted, so it falls through to the ripwire allowlist below.
    if [ "$first_word" = "ripwire" ]; then
      if printf '%s\n' "$bash_cmd" | grep -qE -- '--(replace-symbol-body|insert-(before|after)-symbol)([=[:space:]]|$)' \
        && printf '%s\n' "$bash_cmd" | grep -qE -- '--edit-payload([=[:space:]]|$)'; then
        count_edit "Bash ripwire-symbol-edit" || exit 2
        exit 0
      fi
      if printf '%s\n' "$bash_cmd" | grep -qE -- '--edit-plan([=[:space:]]|$)' \
        && printf '%s\n' "$bash_cmd" | grep -qE -- '(^|[[:space:]])--apply([[:space:]]|$)'; then
        count_edit "Bash ripwire-edit-plan" || exit 2
        exit 0
      fi
    fi
    # One awk walk over the raw command does two things: it reports the
    # first interpreter-fed heredoc body longer than CLAUDE_1337_INLINE_LINES
    # (default 20, 0 disables) on its first output line, and prints the
    # command with every non-interpreter heredoc body stripped after it.
    # A body is interpreter-fed when the text before `<<` ends on one of the
    # is_interp tokens with nothing after it but flags or a bare `-`; a
    # filename argument (`python3 script.py <<EOF`) is left alone. Other
    # bodies are data (a commit message, a `cat > file` payload), so their
    # mentions of `sed -i` or `> foo.py` must not trip the write greps
    # below; the opener line stays so `cat <<EOF > out.py` still does.
    inline_limit="${CLAUDE_1337_INLINE_LINES:-20}"
    scan_out=$(printf '%s\n' "$bash_cmd" | awk -v limit="$inline_limit" '
      function is_interp(t) {
        return (t=="python"||t=="python3"||t=="python2"||t=="node"||t=="bash"||t=="sh"||t=="zsh"||t=="dash"||t=="ruby"||t=="perl"||t=="php"||t=="deno"||t=="bun"||t=="osascript")
      }
      BEGIN { in_body=0; found=0; hit_count=0; hit_interp="" }
      {
        line=$0
        if (!in_body) {
          out[++n] = line
          if (match(line, /<<-?[ \t]*"?'"'"'?[A-Za-z_][A-Za-z0-9_]*"?'"'"'?/)) {
            seg = substr(line, RSTART, RLENGTH)
            dash = (seg ~ /^<<-/) ? 1 : 0
            marker = seg
            sub(/^<<-?[ \t]*/, "", marker)
            gsub(/["'"'"']/, "", marker)
            prefix = substr(line, 1, RSTART - 1)
            ntoks = split(prefix, toks, /[ \t]+/)
            interp = ""
            interp_idx = 0
            for (i = 1; i <= ntoks; i++) { if (toks[i] != "" && is_interp(toks[i])) { interp = toks[i]; interp_idx = i } }
            if (interp != "") {
              has_file = 0
              for (i = interp_idx + 1; i <= ntoks; i++) { if (toks[i] != "" && toks[i] != "-" && substr(toks[i], 1, 1) != "-") has_file = 1 }
              if (has_file) interp = ""
            }
            cur_marker = marker; cur_dash = dash; cur_interp = interp
            body_count = 0
            in_body = 1
          }
        } else {
          test_line = line
          if (cur_dash) sub(/^\t+/, "", test_line)
          if (test_line == cur_marker) {
            in_body = 0
            out[++n] = line
            if (!found && cur_interp != "" && body_count > limit) { hit_count = body_count; hit_interp = cur_interp; found = 1 }
            next
          }
          body_count++
          if (cur_interp != "") out[++n] = line
        }
      }
      END {
        print hit_count " " hit_interp
        for (i = 1; i <= n; i++) print out[i]
      }
    ')
    read -r body_lines interp <<<"${scan_out%%$'\n'*}"
    clean=$(printf '%s\n' "$scan_out" | sed -e '1d' -e 's#[0-9]*&\?>[[:space:]]*/dev/null##g' -e 's#[0-9]*>&1##g')
    if [ "$inline_limit" != "0" ] && [ "${body_lines:-0}" != "0" ]; then
      printf 'blocked (1337 orchestrator mode): inline %s-line script piped into %s; scripts over %s lines are builder work. Dispatch it to 1337:builder with a self-contained brief.\n' \
        "$body_lines" "$interp" "$inline_limit" >&2
      exit 2
    fi
    # Code files are builder work regardless of directory: refuse them even
    # under the temp-dir exemption below. Data files under temp stay allowed.
    code_ext='py|sh|bash|js|mjs|cjs|ts|rb|go|rs|php|pl|lua|html|htm|css'
    # The target may be quoted ("f.py", 'f.py'); sed takes its expression
    # between the -i flag and the file, so skip anything up to the last token.
    if printf '%s\n' "$clean" | grep -qiE "(^|[[:space:];&(])[0-9]*>+[[:space:]]*[\"']?[^[:space:];&|<>]+\\.($code_ext)[\"']?([[:space:];&|]|\$)" \
      || printf '%s\n' "$clean" | grep -qiE "(^|[[:space:];&(])tee([[:space:]]+-[A-Za-z]+)*[[:space:]]+[\"']?[^[:space:];&|<>]+\\.($code_ext)[\"']?([[:space:];&|]|\$)" \
      || printf '%s\n' "$clean" | grep -qiE "sed[[:space:]]+([^;&|]*[[:space:]])?-[A-Za-z]*i[^;&|]*[[:space:]][\"']?[^[:space:];&|<>]+\\.($code_ext)[\"']?([[:space:];&|]|\$)"; then
      printf 'blocked (1337 orchestrator mode): Bash command writes a code file (%.80s). Scripts are builder work even under temp directories; dispatch it to 1337:builder with a self-contained brief.\n' "$bash_cmd" >&2
      exit 2
    fi
    # The scratch carve-out applies to the WRITE TARGET, not to the command
    # string: strip the writes that land under a temp dir or ~/.claude, then
    # the write patterns below see only real targets, and a command that
    # reads repository payload into a scratch file still reaches the
    # read-dump check. `S=/tmp/scratch; ... > $S/f.txt` names its target
    # through a variable, so resolve a literal assignment to a scratch path
    # first; an unresolvable target is treated as a real one.
    wclean="$clean"
    for v in $(printf '%s\n' "$clean" | grep -oE '[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*' \
      | grep -E '=["'"'"']?(\$\{?TMPDIR\}?|(/private)?/tmp|/var/folders)' | sed -E 's/=.*//'); do
      wclean=$(printf '%s\n' "$wclean" | sed -E "s#\\\$\{?$v\}?#/tmp/scratch#g")
    done
    scratch_target="[\"']?[^[:space:];&|<>\"']*((/private)?/tmp/|/var/folders/|\\.claude/)[^[:space:];&|<>\"']*[\"']?"
    wclean=$(printf '%s\n' "$wclean" | sed -E \
      -e "s#[0-9]*>+[[:space:]]*$scratch_target##g" \
      -e "s#(^|[[:space:];&(])tee([[:space:]]+-[A-Za-z]+)*[[:space:]]+$scratch_target#\\1#g" \
      -e "s#(^|[[:space:];&(])sed[[:space:]]+([^;&|]*[[:space:]])?-[A-Za-z]*i[^;&|]*[[:space:]]$scratch_target#\\1#g")
    if printf '%s\n' "$wclean" | grep -qE '(^|[[:space:];&(])tee([[:space:]]|$)|sed[[:space:]]+(-[a-zA-Z]+ )*-i|(^|[[:space:];&(])[0-9]*>+[[:space:]]*[^&>[:space:]]'; then
      printf 'blocked (1337 orchestrator mode): Bash command writes files (%.80s). Dispatch it to 1337:builder with a self-contained brief; the main session may only write under ~/.claude and temp directories.\n' "$bash_cmd" >&2
      exit 2
    fi
    # Read-dumping commands: a whole file poured into context via cat, head,
    # tail, less, more, nl, od, xxd, strings, find, cp/mv, a path-scoped
    # jq/awk/sed/grep, a tree scanner (rg/ag/ack, grep -r) that needs no path
    # at all, or an inline interpreter that opens a file. ripwire, git
    # inspection, ls, tasqx and the test/build runners are never readers
    # themselves; a pipeline stage with no file operand of its own (a bare
    # filter on another command's stdout) is not a reader either. Both the
    # reader check and the git check below run on EVERY segment, never only on
    # the first word: `git status; cat src/x.py` and `cd /repo && git show
    # HEAD:f` hide the read behind an allowed first command otherwise.
    #
    # git is allowed, but four subcommand forms dump a whole file's contents
    # rather than a diff/map: `git show <rev>:<path>`, `git cat-file` in any
    # form, and `git grep` (which searches tracked file contents). Everything
    # else under git, including every `git diff` and `git show HEAD`/`git show
    # --stat HEAD` (no colon operand), stays allowed. Global options in front
    # (`git -C /repo show ...`) are skipped by hooks/lib/git-subcommand.sh; one
    # it cannot parse is refused as a possible read, and so is a `-c alias.*`
    # config, which can rename any of the four (`git -c alias.s='cat-file -p'
    # s X`). An alias cannot shadow a builtin, so `git diff` stays allowed even
    # behind one.
    . "$(dirname "$0")/lib/git-subcommand.sh"
    . "$(dirname "$0")/lib/mask-quotes.sh"
    git_read_check() { # the words after `git` in one segment
      local git_reader="" git_arg prev="" alias_cfg=0
      git_subcommand "$@"
      for git_arg in "${@:1:$git_sub_at}"; do
        if [ "$prev" = "-c" ]; then
          case "$(printf '%s' "$git_arg" | tr '[:upper:]' '[:lower:]')" in
            alias.*|\'alias.*|\"alias.*) alias_cfg=1 ;;
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
    # The inline-interpreter check further down greps the whole command, so a
    # commit message or a ripwire query that mentions `python ... open(` would
    # trip it; for the commands that used to be allowlisted wholesale it only
    # runs when a segment really starts with an interpreter.
    interp_whole=1
    case "$first_word" in
      git|ripwire|ls|tasqx|cargo|npm|pnpm|pytest|make|command) interp_whole=0 ;;
      bash)
        printf '%s\n' "$bash_cmd" | grep -qE '^bash[[:space:]]+tests/.*\.test\.sh' && interp_whole=0
        ;;
    esac
    scan=$(printf '%s\n' "$clean" | mask_quotes | awk '
      function base(s,   n, a) { n = split(s, a, "/"); return a[n] }
      # A scratch operand is output the session produced itself, not
      # repository payload: temp dirs and ~/.claude, as read-cap.sh exempts.
      function is_scratch(t) {
        gsub(/["'"'"']/, "", t)
        return (t ~ /^\$\{?TMPDIR\}?(\/|$)/ || t ~ /^(\/private)?\/tmp(\/|$)/ \
          || t ~ /^\/var\/folders(\/|$)/ || t ~ /\.claude\//)
      }
      # Quoted text is data, not a command: the `cat` in
      # `git commit -m "... cd src && cat lib.rs ..."` runs nothing, yet the
      # split below turns it into a segment of its own. The characters the
      # split and the token walk key on -- whitespace, `;`, `|`, `&`, `<`,
      # `>` -- are already blunted inside quoted spans by hooks/lib/mask-
      # quotes.sh, which this input has been piped through before reaching
      # this awk; the rest of each quoted span survives (a quoted "/tmp/f"
      # is still scratch to is_scratch), and everything outside quotes
      # parses exactly as it did before.
      BEGIN { SEP = sprintf("%c", 1) }
      {
        # Split on the separators but keep which one it was: a segment fed
        # by `|` filters another command'"'"'s stdout, a segment after `;`,
        # `&&` or `||` starts its own command with its own operands.
        line = $0
        gsub(/\|\|/, " " SEP "SEQ" SEP " ", line)
        gsub(/&&/, " " SEP "SEQ" SEP " ", line)
        gsub(/;/, " " SEP "SEQ" SEP " ", line)
        gsub(/\|/, " " SEP "PIPE" SEP " ", line)
        nseg = split(line, segs, SEP)
        for (s = 1; s <= nseg; s += 2) {
          seg = segs[s]
          piped = (s > 1 && segs[s - 1] == "PIPE")
          gsub(/^[ \t]+|[ \t]+$/, "", seg)
          if (seg == "") continue
          m = split(seg, w, /[ \t]+/)
          # Skip what runs the next word rather than being the command:
          # VAR=val assignments, and the command/builtin/exec/env prefixes
          # with their flags (and env'"'"'s VAR=val arguments), so
          # `command git cat-file -p X` is seen as git.
          i = 1
          while (i <= m) {
            if (w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
            p = base(w[i])
            if (p == "command" || p == "builtin") {
              i++
              while (i <= m && w[i] ~ /^-/) i++
              continue
            }
            if (p == "exec" || p == "env") {
              i++
              while (i <= m && w[i] ~ /^-/) {
                if ((p == "exec" && w[i] == "-a") || (p == "env" && (w[i] == "-u" || w[i] == "-C" || w[i] == "--unset" || w[i] == "--chdir"))) i++
                i++
              }
              continue
            }
            break
          }
          if (i > m) continue
          cmd = base(w[i])
          # git goes back to the shell whole, for hooks/lib/git-subcommand.sh.
          if (cmd == "git") {
            g = "G"
            for (j = i + 1; j <= m; j++) g = g " " w[j]
            print g
            continue
          }
          if (cmd ~ /^(python[23]?|perl|ruby)$/) print "I " cmd
          nonflag = 0
          recursive = 0
          for (j = i + 1; j <= m; j++) {
            tok = w[j]
            if (tok == "" || tok == "-") continue
            if (substr(tok, 1, 1) == "-") {
              if (tok ~ /^-[A-Za-z]*[rR]/ || tok ~ /^--recursive/) recursive = 1
              continue
            }
            # A redirect or heredoc opener (<, <<, <<-, >, >>) ends the
            # argument list; what follows is a target/marker, not a file
            # being read as a command argument (`cat <<EOF` reads stdin).
            if (substr(tok, 1, 1) == "<" || substr(tok, 1, 1) == ">") break
            if (is_scratch(tok)) continue
            nonflag++
          }
          if (cmd == "cat" || cmd == "head" || cmd == "tail" || cmd == "less" || cmd == "more" || cmd == "nl" || cmd == "od" || cmd == "xxd" || cmd == "strings" || cmd == "find" || cmd == "cp" || cmd == "mv") {
            if (nonflag >= 1) { print "R " cmd; exit }
          } else if (cmd == "rg" || cmd == "ag" || cmd == "ack") {
            # These default to the working tree, so at the head of a
            # pipeline they dump the whole repo with no path operand at all.
            if (!piped || nonflag >= 2) { print "R " cmd; exit }
          } else if (cmd == "grep" || cmd == "egrep" || cmd == "fgrep") {
            # -r/-R walks the tree from the working directory; without it, a
            # bare `grep pattern` only filters stdin.
            if (recursive || nonflag >= 2) { print "R " cmd; exit }
          } else if (cmd == "jq" || cmd == "awk" || cmd == "sed") {
            if (nonflag >= 2) { print "R " cmd; exit }
          }
        }
      }
    ')
    reader=""
    interp_seg=0
    while IFS= read -r scan_line; do
      case "$scan_line" in
        "R "*) reader="${scan_line#R }"; break ;;
        "I "*) interp_seg=1 ;;
        G|"G "*)
          read -r -a git_words <<<"${scan_line#G}"
          git_read_check "${git_words[@]}"
          ;;
      esac
    done <<<"$scan"
    if [ -z "$reader" ] && { [ "$interp_whole" = 1 ] || [ "$interp_seg" = 1 ]; }; then
      # A write-mode open is the MODE ARGUMENT, not any quoted string in the
      # call: `open(p, "w")`, `open(p,'wb')`, `open(p, mode="a")`, and the
      # first argument of `Path(p).open("w")`. Matching a quoted string
      # anywhere would read `open("web.txt")` as a write. Strip the
      # write-mode calls, then any `open(` still standing is a read, as are
      # pathlib's .read_text()/.read_bytes() and a single-argument open().
      mode_arg="[\"'][rwaxbt+]*[wax][rwaxbt+]*[\"']"
      py=$(printf '%s\n' "$clean" | sed -E \
        -e "s#open\([^)]*,[[:space:]]*(mode[[:space:]]*=[[:space:]]*)?$mode_arg##g" \
        -e "s#open\([[:space:]]*(mode[[:space:]]*=[[:space:]]*)?$mode_arg##g")
      if printf '%s\n' "$clean" | grep -qE '(^|[[:space:];&(]|\|\|)[[:space:]]*python[23]?\b' \
        && printf '%s\n' "$py" | grep -qE 'open\(|\.read_text\(|\.read_bytes\('; then
        reader=python
      elif printf '%s\n' "$clean" | grep -qE '(^|[[:space:];&(]|\|\|)[[:space:]]*perl\b.*-ne\b'; then
        reader=perl
      elif printf '%s\n' "$clean" | grep -qE '(^|[[:space:];&(]|\|\|)[[:space:]]*ruby\b.*-e\b' \
        && printf '%s\n' "$clean" | grep -q 'File\.read'; then
        reader=ruby
      fi
    fi
    if [ -n "$reader" ]; then
      refuse_read "reads a file's contents via $reader" "$bash_cmd"
    fi
    exit 0
    ;;
  Edit)
    lines=$(printf '%s' "$payload" | jq -r '.tool_input.new_string // ""' | awk 'END { print NR }')
    ;;
  MultiEdit)
    lines=$(printf '%s' "$payload" | jq -r '[.tool_input.edits[]?.new_string] | join("\n")' | awk 'END { print NR }')
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
