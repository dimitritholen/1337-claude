# Sourced by hooks/orchestrator-guard.sh and hooks/read-cap.sh: the one Bash
# tokenizer both hooks judge a command with, so they cannot split the same
# command two different ways (#682, #691, #693 all came from that).
#
# tokenize reads a whole command on stdin (portable awk, no gawk extensions)
# and prints one record per segment. A segment is what | ; & && || |& and
# newlines separate, a ( ) group's contents, and the inside of every $( ),
# backtick, <( ) and >( ), each as a segment of its own. Quoted text and
# heredoc bodies are data, not commands: a quoted span stays inside its word
# with the quotes removed the way the shell removes them, and a heredoc body
# is dropped from the segments. $(( )) is arithmetic and is skipped whole.
# Comments (# at the start of a word) are dropped.
#
# Records, fields separated by \037 (TOK_US):
#   S sid piped at lookup na a... nw word... nr op target ... E
#     sid     segment id, unique within the command
#     piped   1 when the segment reads the previous one's stdout (after |)
#     at      0-based index into word... of the command word, after the
#             prefixes: VAR=val assignments, command/builtin with their
#             flags, exec/env with their flags (and the values of exec -a,
#             env -u/-C/--unset/--chdir), and the keywords ! { } if then
#             else elif do while until time fi done esac. A segment opening
#             with for, select or case is a header that names no command:
#             at = nw. at = nw whenever there is no command word at all.
#     lookup  1 when a command/builtin prefix carried -v or -V (a lookup,
#             not a run)
#     na a... how many of the prefix words are VAR=val assignments, and
#             their 0-based indices into word...
#     nw word...  every word of the segment, prefixes included
#     nr op target ...  the redirects: op as written (> >> < << <<- <<<
#             &> &>> >& <& <> >|, with a leading fd number such as 2>),
#             target the word after it (for << and <<-, the heredoc marker)
#   B sid body   the heredoc bodies segment sid opened, concatenated
#   X reason     a construct the lexer does not judge (an unquoted heredoc
#                body or arithmetic holding a command substitution, a
#                redirect with no target)
# A $( ), backtick or <( ) inside a word leaves \002 (TOK_PH) in its place.
# Newlines and tabs inside a quoted word, and any \037, turn into spaces.
#
# tok_parse REC splits one S record into tok_sid, tok_piped, tok_at,
# tok_lookup, tok_nw, tok_nr and the arrays tok_assigns, tok_words, tok_rops,
# tok_rtgs. Bash 3.2 safe: indexed arrays only, and words come out of `read
# -a`, never an unquoted expansion, so a glob in a word stays literal.
# Tests: tests/orchestrator-guard.test.sh, tests/read-cap.test.sh.

TOK_US=$(printf '\037')
TOK_PH=$(printf '\002')

_tok_awk='
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
# Sets pat (0-based index of the command word), plook and pna/pa[]: the
# prefix words that run the next word rather than being the command.
function prefix(c,   i, t, k, n1) {
  pat = 0; plook = 0; pna = 0; n1 = nw[c]
  i = 1
  if (n1 > 0) { t = clean(w[c, 1]); if (t == "for" || t == "select" || t == "case") i = n1 + 1 }
  while (i <= n1) {
    t = clean(w[c, i])
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { pa[++pna] = i - 1; i++; continue }
    if (t == "command" || t == "builtin") {
      i++
      while (i <= n1 && clean(w[c, i]) ~ /^-/) { if (clean(w[c, i]) ~ /[vV]/) plook = 1; i++ }
      continue
    }
    if (t == "exec" || t == "env") {
      i++
      while (i <= n1 && clean(w[c, i]) ~ /^-/) {
        k = t " " clean(w[c, i])
        if (k == "exec -a" || k == "env -u" || k == "env -C" || k == "env --unset" || k == "env --chdir") i++
        i++
      }
      continue
    }
    if (t in KW) { i++; continue }
    break
  }
  pat = (i > n1 ? n1 : i - 1)
}
function endseg(c, sep,   k, out) {
  flushword(c)
  if (pend[c] != "") { err = "a redirect with no target"; pend[c] = "" }
  if (nw[c] > 0 || nr[c] > 0) {
    prefix(c)
    out = "S" US cur[c] US pip[c] US pat US plook US pna
    for (k = 1; k <= pna; k++) out = out US pa[k]
    out = out US nw[c]
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
BEGIN {
  US = sprintf("%c", 31); PH = sprintf("%c", 2); SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); s = ""
  split("! { } if then else elif do while until time fi done esac", kwl, " ")
  for (k in kwl) KW[kwl[k]] = 1
}
{ s = (NR > 1) ? s "\n" $0 : $0 }
END { lex() }
'

tokenize() {
  awk "$_tok_awk"
}

tok_parse() { # one S record
  local f k j
  IFS="$TOK_US" read -r -a f <<<"$1"
  tok_sid="${f[1]}"; tok_piped="${f[2]}"; tok_at="${f[3]}"; tok_lookup="${f[4]}"
  k=5
  tok_assigns=()
  [ "${f[$k]}" -gt 0 ] && tok_assigns=("${f[@]:$((k + 1)):${f[$k]}}")
  k=$((k + 1 + ${f[$k]}))
  tok_nw="${f[$k]}"
  tok_words=()
  [ "$tok_nw" -gt 0 ] && tok_words=("${f[@]:$((k + 1)):$tok_nw}")
  k=$((k + 1 + tok_nw))
  tok_nr="${f[$k]}"
  tok_rops=(); tok_rtgs=()
  for ((j = 0; j < tok_nr; j++)); do
    tok_rops+=("${f[$((k + 1 + 2 * j))]}")
    tok_rtgs+=("${f[$((k + 2 + 2 * j))]}")
  done
  return 0
}

# tok_input_redirects: sets tok_inputs to the `<` targets of the segment
# tok_parse last split (fd digits stripped from the operand, e.g. `3<`),
# skipping /dev/null and /dev/stdin, and only when the segment has no
# command word (tok_at >= tok_nw) — a `for`/`select`/`case` header is also
# command-less but never carries a redirect of its own, so this cannot
# mistake one for a read. That shape is `$(< file)` (or the backtick/
# `x=$(< file)` equivalents): bash expands it to the file's contents with
# no reader program in sight, so hooks/orchestrator-guard.sh's judge_segment
# and hooks/read-cap.sh's bash_is_read both need to catch it even though
# neither sees a command word to dispatch on. Each caller applies its own
# path policy on top of tok_inputs (orchestrator-guard.sh exempts a scratch
# operand the same as it does for `cat`; read-cap.sh does not, since it
# already counts `cat /tmp/x` as a read with no such exemption — keeping
# `$(< /tmp/x)` on the same footing there, not a new carve-out).
tok_input_redirects() {
  local j op
  tok_inputs=()
  [ "$tok_at" -ge "$tok_nw" ] || return 0
  for ((j = 0; j < tok_nr; j++)); do
    op="${tok_rops[$j]}"
    while [[ $op == [0-9]* ]]; do op="${op#?}"; done
    [ "$op" = "<" ] || continue
    case "${tok_rtgs[$j]}" in
      /dev/null | /dev/stdin) ;;
      *) tok_inputs+=("${tok_rtgs[$j]}") ;;
    esac
  done
  return 0
}
