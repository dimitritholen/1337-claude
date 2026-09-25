#!/usr/bin/env bash
# Tests for hooks/terse-rules.sh: off is silent, on/hard print the right
# blocks of hooks/terse.md, and the env var overrides the mode file.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
HOOK="$ROOT/hooks/terse-rules.sh"
fail=0
work="$(mktemp -d)"
mode_file="$work/mode"
trap 'rm -rf "$work"' EXIT

common_marker="No filler, pleasantries, hedging or preamble."
hard_marker="Sentence fragments are fine; drop articles."

unset CLAUDE_1337_TERSE

printf 'off\n' > "$mode_file"
out=$(CLAUDE_1337_TERSE_FILE="$mode_file" "$HOOK" 2>/dev/null)
[ -z "$out" ] && printf 'ok   mode off: silent\n' || { printf 'FAIL mode off: silent (got output)\n'; fail=1; }

printf 'on\n' > "$mode_file"
out=$(CLAUDE_1337_TERSE_FILE="$mode_file" "$HOOK" 2>/dev/null)
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

printf 'hard\n' > "$mode_file"
out=$(CLAUDE_1337_TERSE_FILE="$mode_file" "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -qF "$common_marker" && printf '%s' "$out" | grep -qF "$hard_marker"; then
  printf 'ok   mode hard: contains common and hard rules\n'
else
  printf 'FAIL mode hard: contains common and hard rules\n'; fail=1
fi

# Env overrides the mode file.
printf 'off\n' > "$mode_file"
out=$(CLAUDE_1337_TERSE=on CLAUDE_1337_TERSE_FILE="$mode_file" "$HOOK" 2>/dev/null)
if [ -n "$out" ]; then
  printf 'ok   env on overrides file off\n'
else
  printf 'FAIL env on overrides file off\n'; fail=1
fi

exit $fail
