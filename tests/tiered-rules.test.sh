#!/usr/bin/env bash
# Tests for hooks/tiered-rules.sh: exercises the on/off env vars and checks
# the ${CLAUDE_PLUGIN_ROOT} placeholder gets substituted with the real root.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
HOOK="$ROOT/hooks/tiered-rules.sh"
fail=0

check() { # empty|nonempty description env-assignments...
  local want="$1" desc="$2"
  shift 2
  local out rc
  out=$(env "$@" "$HOOK" 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'FAIL %s (exit %d, want 0)\n' "$desc" "$rc"; fail=1; return
  fi
  if [ "$want" = empty ]; then
    [ -z "$out" ] && printf 'ok   %s\n' "$desc" || { printf 'FAIL %s (unexpected output)\n' "$desc"; fail=1; }
  else
    [ -n "$out" ] && printf 'ok   %s\n' "$desc" || { printf 'FAIL %s (no output)\n' "$desc"; fail=1; }
  fi
}

unset CLAUDE_PLUGIN_OPTION_TIERED CLAUDE_1337_TIERED

check empty "mode off: stdout empty" CLAUDE_PLUGIN_OPTION_TIERED=false CLAUDE_1337_TIERED=0

out=$(env CLAUDE_PLUGIN_OPTION_TIERED=true "$HOOK" 2>/dev/null)
case "$out" in
  '# Tiered mode'*) printf 'ok   %s\n' "plugin option on: starts with '# Tiered mode'" ;;
  *) printf 'FAIL %s\n' "plugin option on: starts with '# Tiered mode'"; fail=1 ;;
esac

if printf '%s' "$out" | grep -qF '${CLAUDE_PLUGIN_ROOT}'; then
  printf 'FAIL %s\n' "no literal \${CLAUDE_PLUGIN_ROOT} left"; fail=1
else
  printf 'ok   %s\n' "no literal \${CLAUDE_PLUGIN_ROOT} left"
fi
if printf '%s' "$out" | grep -qF "$ROOT/skills/tier/route.py"; then
  printf 'ok   %s\n' "contains absolute route.py path"
else
  printf 'FAIL %s\n' "contains absolute route.py path"; fail=1
fi

check nonempty "CLAUDE_1337_TIERED=1 with plugin option false: rules printed" \
  CLAUDE_PLUGIN_OPTION_TIERED=false CLAUDE_1337_TIERED=1

check nonempty "EVAL_1337_TIERED=1 alone: rules printed" \
  CLAUDE_PLUGIN_OPTION_TIERED=false CLAUDE_1337_TIERED=0 EVAL_1337_TIERED=1

exit $fail
