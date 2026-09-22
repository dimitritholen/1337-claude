#!/usr/bin/env bash
# SessionStart hook: prints the tiered-mode rules (hooks/tiered.md) into the
# main session, active only in tiered mode (plugin option `tiered`, or
# CLAUDE_1337_TIERED=1). Silent otherwise. Every failure path exits 0.
#
# Plain stdout: SessionStart accepts plain text as additionalContext, no JSON
# wrapper needed.
#
# EVAL_1337_TIERED=1 is the switch eval cases use, since `claude plugin eval`
# cases may only set EVAL_* variables.
set -u

[ "${CLAUDE_PLUGIN_OPTION_TIERED:-false}" = "true" ] || [ "${CLAUDE_1337_TIERED:-0}" = "1" ] || [ "${EVAL_1337_TIERED:-0}" = "1" ] || exit 0

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
digest_file="$root/hooks/tiered.md"
[ -f "$digest_file" ] || exit 0

sed "s#\${CLAUDE_PLUGIN_ROOT}#$root#g" "$digest_file"
exit 0
