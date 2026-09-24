# Sourced by hooks/orchestrator-guard.sh and hooks/read-cap.sh. Finds the
# subcommand of a git command line, skipping the git global options in front
# of it, so `git -C /repo show HEAD:x` is seen as `show` and not as `-C`.
#
# git_subcommand WORD...   the words after `git`, split on whitespace the
#                          way each hook already splits its commands.
# Sets git_sub to the subcommand and git_sub_at to its 1-based position in
# WORD..., so `shift "$git_sub_at"` leaves the subcommand's own arguments.
# No subcommand at all (`git`, `git -C x` with nothing after): git_sub is
# empty, git_sub_at 0.
#
# Skipped: -C <v>, -c <v>, --no-pager, -p, --paginate, --git-dir[= ]<v>,
# --work-tree[= ]<v>, --namespace[= ]<v>, --no-optional-locks, --bare,
# --literal-pathspecs; the set review-gate.sh's diff_re accepts, plus the
# rest. A value may be quoted ('..' or ".."); a quoted value holding
# whitespace arrives split over several words, and the quote span counts as
# one value. -v/--version and -h/--help are what git itself turns them into:
# the version and help subcommands.
#
# Parse failure: any other word starting with `-` in the global-option
# position (it may take a value that hides the real subcommand), a value
# option with no value left, or a quote that never closes. Then git_sub is
# that option word itself, which always starts with `-`, and callers must
# treat a git_sub starting with `-` as a possible read (refuse or count),
# never as allowed.
git_subcommand() {
  local i=0 w at val q
  git_sub="" git_sub_at=0
  while [ "$#" -gt 0 ]; do
    w="$1"; shift; i=$((i + 1)); at=$i
    val=""
    case "$w" in
      -C|-c|--git-dir|--work-tree|--namespace)
        [ "$#" -gt 0 ] || { git_sub="$w" git_sub_at=$at; return 0; }
        val="$1"; shift; i=$((i + 1))
        ;;
      --git-dir=*|--work-tree=*|--namespace=*) val="${w#*=}" ;;
      --no-pager|-p|--paginate|--no-optional-locks|--bare|--literal-pathspecs) continue ;;
      -v|--version) git_sub=version git_sub_at=$at; return 0 ;;
      -h|--help) git_sub=help git_sub_at=$at; return 0 ;;
      # The subcommand, or an unknown option: the parse failure above.
      *) git_sub="$w" git_sub_at=$at; return 0 ;;
    esac
    # A value opening a quote it does not close on the same word runs on
    # until the word that closes it.
    case "$val" in
      \'*|\"*) q="${val:0:1}" ;;
      *) continue ;;
    esac
    if [ "${#val}" -ge 2 ] && [ "${val: -1}" = "$q" ]; then continue; fi
    while :; do
      [ "$#" -gt 0 ] || { git_sub="$w" git_sub_at=$at; return 0; }
      val="$1"; shift; i=$((i + 1))
      [ "${val: -1}" = "$q" ] && break
    done
  done
  return 0
}

# git_is_read WORD...   the words after `git`, as for git_subcommand.
# Returns 0 when the command may print a file's contents rather than a diff,
# with git_read_why naming the shape, checked in this order: `option` (an
# unparsable global option, see above), `show` (git show <rev>:<path>: a
# non-option operand after show holding a colon), `cat-file`, `grep`, and
# `alias` (a -c alias.* config, which can rename any subcommand into a read;
# an alias cannot shadow a builtin, so `git diff` stays a non-read). Leaves
# git_sub and git_sub_at set by its git_subcommand call.
git_is_read() {
  local arg prev="" alias_cfg=0
  git_read_why=""
  git_subcommand "$@"
  for arg in "${@:1:$git_sub_at}"; do
    if [ "$prev" = "-c" ]; then
      case "$arg" in [aA][lL][iI][aA][sS].*) alias_cfg=1 ;; esac
    fi
    prev="$arg"
  done
  case "$git_sub" in
    -*) git_read_why=option ;;
    show)
      for arg in "${@:$((git_sub_at + 1))}"; do
        case "$arg" in
          -*) ;;
          *:*) git_read_why=show; break ;;
        esac
      done
      ;;
    cat-file|grep) git_read_why="$git_sub" ;;
    diff) alias_cfg=0 ;;
  esac
  [ -z "$git_read_why" ] && [ "$alias_cfg" = 1 ] && git_read_why=alias
  [ -n "$git_read_why" ]
}
