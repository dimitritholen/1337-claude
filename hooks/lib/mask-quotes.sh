# Sourced by hooks/read-cap.sh (hooks/orchestrator-guard.sh has its own
# lexer and no longer uses it). Masks the
# characters a segment/first-word split keys on -- whitespace, `;`, `|`,
# `&`, `<`, `>` -- while inside a single- or double-quoted span, so text
# like `git commit -m "x; head first"` or `echo "run; cat file"` is not
# mistaken for several commands joined by a real `;`/`|`/`&&`/`||`. `$( )`
# and backticks inside a double-quoted string ARE executed by the shell, so
# they stay live and unmasked. Runs one line at a time with no state carried
# across lines: an unterminated quote (a lone apostrophe, or a quoted span
# that continues onto another line) leaves that line unmasked entirely,
# which refuses more than it should rather than less. Everything outside
# quotes, and the quote characters themselves, pass through unchanged, so a
# masked line still parses (first word, git subcommand, colon in a `rev:path`
# operand) exactly as the unmasked one would.
#
# mask_quotes reads a command, one or more lines, on stdin and prints it
# back with quoted separators masked, one output line per input line.
mask_quotes() {
  awk '
    function mask_char(c) { return (c ~ /[ \t;|&<>]/) ? "x" : c }
    function mask_quotes(s,   out, i, n, c, d, sp, top) {
      out = ""; n = length(s); sp = 0; i = 1
      while (i <= n) {
        c = substr(s, i, 1)
        d = substr(s, i + 1, 1)
        top = (sp > 0) ? st[sp] : "N"
        if (top == "Q") {                      # no escapes inside '"'"'...'"'"'
          if (c == SQ) { sp--; out = out c } else out = out mask_char(c)
          i++
          continue
        }
        if (top == "D") {
          if (c == "\\") { out = out c mask_char(d); i += 2; continue }
          if (c == DQ) { sp--; out = out c; i++; continue }
          if (c == "$" && d == "(") { st[++sp] = "S"; out = out "$("; i += 2; continue }
          if (c == "`") { st[++sp] = "B"; out = out c; i++; continue }
          out = out mask_char(c); i++
          continue
        }
        # Unquoted, or inside a substitution: this text is executed.
        if (c == "\\") { out = out substr(s, i, 2); i += 2; continue }
        if (c == SQ) { st[++sp] = "Q"; out = out c; i++; continue }
        if (c == DQ) { st[++sp] = "D"; out = out c; i++; continue }
        if (c == "$" && d == "(") { st[++sp] = "S"; out = out "$("; i += 2; continue }
        if (c == ")" && top == "S") { sp--; out = out c; i++; continue }
        if (c == "`") { if (top == "B") sp--; else st[++sp] = "B"; out = out c; i++; continue }
        out = out c; i++
      }
      for (i = 1; i <= sp; i++) if (st[i] == "Q" || st[i] == "D") return s
      return out
    }
    BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34) }
    { print mask_quotes($0) }
  '
}
