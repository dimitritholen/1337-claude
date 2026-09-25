# "on"/"true" (any case) is on (0), anything else off (1); true/false still
# accepted from configs saved before the on/off picker. Globs, no ${,,}/tr.
_opt_is_on() {
  case "$1" in
    [Oo][Nn] | [Tt][Rr][Uu][Ee]) return 0 ;;
    *) return 1 ;;
  esac
}

# Sourced by the orchestrator/tiered hooks. `mode_on orchestrator|tiered`
# returns 0 (on) when any of that mode's three switches is set, 1 (off)
# otherwise: the plugin option (on/true), CLAUDE_1337_*=1, or
# EVAL_CLAUDE_1337_*=1 (the switch eval cases use).
mode_on() {
  case "$1" in
    orchestrator)
      _opt_is_on "${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-}" ||
        [ "${CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ] ||
        [ "${EVAL_CLAUDE_1337_ORCHESTRATOR:-0}" = "1" ]
      ;;
    tiered)
      _opt_is_on "${CLAUDE_PLUGIN_OPTION_TIERED:-}" ||
        [ "${CLAUDE_1337_TIERED:-0}" = "1" ] ||
        [ "${EVAL_CLAUDE_1337_TIERED:-0}" = "1" ]
      ;;
    *)
      return 1
      ;;
  esac
}

# `opt_on ENV_VAR OPTION_VAR DEFAULT` resolves one boolean switch: env var
# (0/off/false off; 1/on/true on) wins, else plugin option (on/off, or
# true/false from a config saved before the picker switched to strings), else
# DEFAULT. Returns 0 (on) / 1 (off).
opt_on() { # env_var_name option_var_name default(true|false)
  local env_val opt_val
  eval "env_val=\${$1:-}"
  case "$env_val" in
    0 | [Oo][Ff][Ff] | [Ff][Aa][Ll][Ss][Ee]) return 1 ;;
    1 | [Oo][Nn] | [Tt][Rr][Uu][Ee]) return 0 ;;
  esac
  eval "opt_val=\${$2:-}"
  case "$opt_val" in
    [Oo][Nn] | [Tt][Rr][Uu][Ee]) return 0 ;;
    [Oo][Ff][Ff] | [Ff][Aa][Ll][Ss][Ee]) return 1 ;;
  esac
  [ "$3" = "true" ]
}
