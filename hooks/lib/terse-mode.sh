# Sourced by the terse hooks. `terse_mode` echoes the resolved mode
# (off|on|hard): CLAUDE_1337_TERSE env, else the mode file
# (${CLAUDE_1337_TERSE_FILE:-$HOME/.claude/.1337-terse}, set by
# /1337:terse), else "on". A truncated or empty file means the default,
# never a silent off.
terse_mode() {
  local mode
  mode="${CLAUDE_1337_TERSE:-}"
  if [ -z "$mode" ]; then
    mode=$(cat "${CLAUDE_1337_TERSE_FILE:-$HOME/.claude/.1337-terse}" 2>/dev/null || printf 'on')
  fi
  mode=$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')
  [ "$mode" = "0" ] && mode="off"
  [ -n "$mode" ] || mode="on"
  printf '%s' "$mode"
}
