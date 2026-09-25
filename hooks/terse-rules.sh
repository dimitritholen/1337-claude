#!/usr/bin/env bash
# SessionStart hook: prints the terse-mode rules (hooks/terse.md) so the
# budget in hooks/terse-governor.sh is met up front instead of only policed
# after the fact, and so terse mode works with no output style selected.
# Silent when the mode is off. "on" prints the common + exemptions blocks,
# "hard" also the hard-only block. Every failure path exits 0.
set -u

. "${0%/*}/lib/terse-mode.sh"
mode=$(terse_mode)
[ "$mode" != "off" ] || exit 0

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
digest_file="$root/hooks/terse.md"
[ -f "$digest_file" ] || exit 0

block() { # name -> section content, marker lines stripped
  sed -n "/<!-- $1 -->/,/<!-- \/$1 -->/p" "$digest_file" | sed '1d;$d'
}

printf '# Terse mode\n\n'
block common
[ "$mode" = "hard" ] && block hard
block exemptions
exit 0
