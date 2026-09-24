# Sourced by the orchestrator/tiered hooks. `mode_on orchestrator|tiered`
# returns 0 (on) when any of that mode's three switches is set, 1 (off)
# otherwise: the plugin option ("true"), CLAUDE_1337_*=1, or
# EVAL_CLAUDE_1337_*=1 (the switch eval cases use).
mode_on() {
  case "$1" in
    orchestrator)
      [ "${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-false}" = "true" ] ||
        [ "${CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] ||
        [ "${EVAL_CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ]
      ;;
    tiered)
      [ "${CLAUDE_PLUGIN_OPTION_TIERED:-false}" = "true" ] ||
        [ "${CLAUDE_1337_TIERED:-0}" = "1" ] ||
        [ "${EVAL_CLAUDE_1337_TIERED:-0}" = "1" ]
      ;;
    *)
      return 1
      ;;
  esac
}
