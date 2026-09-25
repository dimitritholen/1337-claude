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

# `opt_on ENV_VAR OPTION_VAR DEFAULT` resolves one boolean switch: env var
# (0/off/false off; 1/on/true on) wins, else plugin option, else DEFAULT. Returns 0 (on) / 1 (off).
opt_on() { # env_var_name option_var_name default(true|false)
  local env_val opt_val
  eval "env_val=\${$1:-}"
  env_val=$(printf '%s' "$env_val" | tr '[:upper:]' '[:lower:]')
  case "$env_val" in
    0 | off | false) return 1 ;;
    1 | on | true) return 0 ;;
  esac
  eval "opt_val=\${$2:-}"
  case "$opt_val" in
    true) return 0 ;;
    false) return 1 ;;
  esac
  [ "$3" = "true" ]
}
