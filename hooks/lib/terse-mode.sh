# Sourced by the terse hooks. `terse_mode` echoes the resolved mode
# (off|on|hard): CLAUDE_1337_TERSE env, else CLAUDE_PLUGIN_OPTION_TERSE
# (the "Terse mode" row in /config), else "on". Case-insensitive, "0"
# means off; an empty or unknown value means the default, never a silent
# off.
terse_mode() {
  local mode
  mode="${CLAUDE_1337_TERSE:-${CLAUDE_PLUGIN_OPTION_TERSE:-on}}"
  mode=$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')
  [ "$mode" = "0" ] && mode="off"
  case "$mode" in
    off|on|hard) ;;
    *) mode="on" ;;
  esac
  printf '%s' "$mode"
}
