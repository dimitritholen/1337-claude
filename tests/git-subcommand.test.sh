#!/usr/bin/env bash
# Tests for hooks/lib/git-subcommand.sh: feeds the words after `git` to
# git_subcommand and asserts the subcommand and its position it reports.
set -u

LIB="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/lib/git-subcommand.sh"
fail=0

# shellcheck source=../hooks/lib/git-subcommand.sh
. "$LIB" || { echo "FAIL cannot source $LIB"; exit 1; }

check() { # want-sub want-at description words...
  local want_sub="$1" want_at="$2" desc="$3"
  shift 3
  git_sub="unset" git_sub_at="unset"
  git_subcommand "$@"
  if [ "$git_sub" = "$want_sub" ] && [ "$git_sub_at" = "$want_at" ]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s (got sub=%s at=%s, want sub=%s at=%s)\n' "$desc" "$git_sub" "$git_sub_at" "$want_sub" "$want_at"
    fail=1
  fi
}

check show 1 "plain subcommand" show HEAD:a.py
check diff 1 "plain diff" diff
check "" 0 "bare git has no subcommand"
check show 3 "-C <path> skipped" -C /repo show HEAD:a.py
check grep 2 "--no-pager skipped" --no-pager grep foo
check cat-file 3 "-C . skipped" -C . cat-file -p X
check log 3 "-c <k=v> skipped" -c core.pager=cat log
check show 2 "-p skipped" -p show
check show 2 "--paginate skipped" --paginate show
check show 2 "--git-dir=<v> skipped" --git-dir=/r/.git show
check show 3 "--git-dir <v> skipped" --git-dir /r/.git show
check show 2 "--work-tree=<v> skipped" --work-tree=/r show
check show 3 "--work-tree <v> skipped" --work-tree /r show
check show 4 "--no-optional-locks --bare --literal-pathspecs skipped" --no-optional-locks --bare --literal-pathspecs show
check show 2 "--namespace=<v> skipped" --namespace=ns show
check show 3 "--namespace <v> skipped" --namespace ns show
check show 7 "a run of global options skipped" --no-pager -C /r -c a=b -p show

# Quoted values arrive split on whitespace; the quote span is one value.
check show 3 "-C with a single-quoted value" -C "'/repo'" show
check show 4 "-C with a single-quoted value holding a space" -C "'/my" "repo'" show
check show 5 "-c with a double-quoted value holding two spaces" -c '"user.name=A' 'B' 'C"' show
check show 3 "--git-dir= with a quoted value holding a space" "--git-dir='/a" "b/.git'" show
check -C 1 "an unterminated quote is a parse failure" -C "'/my" repo show

# The parse-failure rule: an unknown option in the global-option position
# is reported as the subcommand itself (it starts with -), never skipped.
check --frobnicate 1 "an unknown long option is a parse failure" --frobnicate show HEAD:a.py
check --exec-path=/x 2 "an unknown option after a known one is a parse failure" -p --exec-path=/x show
check -C 1 "a value option at the end is a parse failure" -C
check -Cfoo 1 "an attached -C value is a parse failure (git takes it separately)" -Cfoo show

# git rewrites these into a subcommand of their own.
check version 1 "--version is the version subcommand" --version
check version 1 "-v is the version subcommand" -v
check help 1 "--help is the help subcommand" --help show
check help 1 "-h is the help subcommand" -h


# git_is_read: 0 and the shape in git_read_why for a file-content read.
check_read() { # want-why ("" = not a read) description words...
  local want="$1" desc="$2" got
  shift 2
  if git_is_read "$@"; then got="$git_read_why"; else got=""; fi
  if [ "$got" = "$want" ]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s (got why=%s, want why=%s)\n' "$desc" "$got" "$want"
    fail=1
  fi
}

check_read show "show <rev>:<path> is a read" -C /repo show HEAD:a.py
check_read "" "show <rev> is metadata" show --stat HEAD
check_read "" "an option holding a colon after show is not a path" show --format=%h:%s HEAD
check_read cat-file "cat-file is a read" cat-file -p X
check_read grep "grep is a read" --no-pager grep foo
check_read option "an unparsable global option is a read" --frobnicate log
check_read alias "a -c alias.* config is a read" -c ALIAS.x=show log
check_read "" "diff stays a non-read behind -c alias.*" -c alias.x=show diff
check_read "" "log is not a read" log --oneline

exit $fail
