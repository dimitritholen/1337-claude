#!/usr/bin/env bash
# Tests for hooks/terse-rules.sh: off is silent, on/hard print the right
# blocks of hooks/terse.md, the /config option (CLAUDE_PLUGIN_OPTION_TERSE)
# sets the mode, and the env var overrides the option.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
HOOK="$ROOT/hooks/terse-rules.sh"
fail=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

common_marker="No filler, pleasantries, hedging or preamble."
hard_marker="Sentence fragments are fine; drop articles."

unset CLAUDE_1337_TERSE CLAUDE_PLUGIN_OPTION_TERSE

export CLAUDE_PLUGIN_OPTION_TERSE=off
out=$("$HOOK" 2>/dev/null)
[ -z "$out" ] && printf 'ok   mode off: silent\n' || { printf 'FAIL mode off: silent (got output)\n'; fail=1; }

export CLAUDE_PLUGIN_OPTION_TERSE=on
out=$("$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -qF "$common_marker"; then
  printf 'ok   mode on: contains common rule\n'
else
  printf 'FAIL mode on: contains common rule\n'; fail=1
fi
if printf '%s' "$out" | grep -qF "$hard_marker"; then
  printf 'FAIL mode on: does not contain hard-only rule (found it)\n'; fail=1
else
  printf 'ok   mode on: does not contain hard-only rule\n'
fi

export CLAUDE_PLUGIN_OPTION_TERSE=hard
out=$("$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -qF "$common_marker" && printf '%s' "$out" | grep -qF "$hard_marker"; then
  printf 'ok   mode hard: contains common and hard rules\n'
else
  printf 'FAIL mode hard: contains common and hard rules\n'; fail=1
fi

# Env overrides the option.
export CLAUDE_PLUGIN_OPTION_TERSE=off
out=$(CLAUDE_1337_TERSE=on "$HOOK" 2>/dev/null)
if [ -n "$out" ]; then
  printf 'ok   env on overrides option off\n'
else
  printf 'FAIL env on overrides option off\n'; fail=1
fi

# No env, no option: the default is on.
unset CLAUDE_PLUGIN_OPTION_TERSE
out=$("$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -qF "$common_marker"; then
  printf 'ok   unset: defaults to on\n'
else
  printf 'FAIL unset: defaults to on\n'; fail=1
fi

exit $fail
