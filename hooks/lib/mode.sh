# "on"/"true" (any case) is on (0), anything else off (1); true/false still
# accepted from configs saved before the on/off picker. Globs, no ${,,}/tr.
_opt_is_on() {
  case "$1" in
    [Oo][Nn] | [Tt][Rr][Uu][Ee]) return 0 ;;
    *) return 1 ;;
  esac
}

# `session_headless` returns 0 when this Claude Code session has no human at
# the terminal: `claude -p`, the Agent SDK, or a tool driving the CLI. Claude
# Code sets CLAUDE_CODE_SESSION_ATTENDED=0 there (1 in the TUI), and
# CLAUDE_CODE_ENTRYPOINT to sdk-* (cli in the TUI); both are undocumented, so
# a session where neither is set counts as attended. CLAUDE_1337_HEADLESS=on
# keeps the interactive-only behaviour in a headless session anyway.
session_headless() {
  _opt_is_on "${CLAUDE_1337_HEADLESS:-}" && return 1
  case "${CLAUDE_CODE_SESSION_ATTENDED:-}" in
    0) return 0 ;;
    1) return 1 ;;
  esac
  case "${CLAUDE_CODE_ENTRYPOINT:-}" in
    sdk-*) return 0 ;;
  esac
  return 1
}

# Sourced by the orchestrator/tiered hooks. `mode_on orchestrator|tiered`
# returns 0 (on) or 1 (off), first match wins: EVAL_CLAUDE_1337_*=1 (the
# switch eval cases use, which run headless) is on; CLAUDE_1337_* set to
# 1/on/true is on and 0/off/false is off; a headless session
# (session_headless) is off, so a tool driving `claude -p` or the SDK never
# meets the gates; else the plugin option (on/true).
mode_on() {
  local eval_val env_val opt_val
  case "$1" in
    orchestrator)
      eval_val="${EVAL_CLAUDE_1337_ORCHESTRATOR:-}"
      env_val="${CLAUDE_1337_ORCHESTRATOR:-}"
      opt_val="${CLAUDE_PLUGIN_OPTION_ORCHESTRATOR:-}"
      ;;
    tiered)
      eval_val="${EVAL_CLAUDE_1337_TIERED:-}"
      env_val="${CLAUDE_1337_TIERED:-}"
      opt_val="${CLAUDE_PLUGIN_OPTION_TIERED:-}"
      ;;
    *)
      return 1
      ;;
  esac
  [ "$eval_val" = "1" ] && return 0
  case "$env_val" in
    1 | [Oo][Nn] | [Tt][Rr][Uu][Ee]) return 0 ;;
    0 | [Oo][Ff][Ff] | [Ff][Aa][Ll][Ss][Ee]) return 1 ;;
  esac
  session_headless && return 1
  _opt_is_on "$opt_val"
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
