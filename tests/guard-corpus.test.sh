#!/usr/bin/env bash
# Replays tests/fixtures/guard-corpus.jsonl against hooks/orchestrator-guard.sh.
# Each row is a captured (or gap-seeded) PreToolUse payload plus the exit code
# and stderr fragment it must produce. This is the corpus companion to
# tests/orchestrator-guard.test.sh: same hook, same rules, data-driven replay.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
HOOK="$ROOT/hooks/orchestrator-guard.sh"
CORPUS="$ROOT/tests/fixtures/guard-corpus.jsonl"

command -v jq >/dev/null 2>&1 || { echo "FAIL jq is required"; exit 1; }

ok=0
fail=0
todo=0

# A single scratch TMPDIR, shared by every row in the run, mirrors the
# original test: edit-cap rows reuse the same session ids in file order, so
# the cap state accumulates across rows exactly as it did in the source test.
scratch_tmpdir=$(mktemp -d)
trap 'rm -rf "$scratch_tmpdir"' EXIT

# A row may override PATH (the jq-missing row does); the runner itself needs
# jq and grep, so the original PATH comes back as soon as the hook returns.
base_path="$PATH"

mode_vars="CLAUDE_PLUGIN_OPTION_ORCHESTRATOR CLAUDE_1337_ORCHESTRATOR EVAL_CLAUDE_1337_ORCHESTRATOR CLAUDE_1337_EDIT_CAP CLAUDE_1337_INLINE_LINES TMPDIR"

n=0
while IFS= read -r line; do
  n=$((n + 1))
  [ -z "$line" ] && continue

  if ! echo "$line" | jq -e 'has("gap") and has("tool") and has("input") and has("want") and has("stderr") and has("env") and has("pending") and has("note")' >/dev/null 2>&1; then
    printf 'FAIL row %d: unparsable or missing key\n' "$n"
    fail=$((fail + 1))
    continue
  fi

  gap=$(echo "$line" | jq -r '.gap')
  input=$(echo "$line" | jq -c '.input' 2>/dev/null)
  want=$(echo "$line" | jq -r '.want' 2>/dev/null)
  stderr_frag=$(echo "$line" | jq -r '.stderr' 2>/dev/null)
  pending=$(echo "$line" | jq -r '.pending' 2>/dev/null)
  note=$(echo "$line" | jq -r '.note' 2>/dev/null)

  if [ -z "$input" ] || [ -z "$want" ] || ! [ "$want" -eq "$want" ] 2>/dev/null; then
    printf 'FAIL row %d: unparsable or missing key\n' "$n"
    fail=$((fail + 1))
    continue
  fi

  # Reset the mode/cap/tmp env to nothing, then reapply the baseline mode env
  # the corpus rows were captured under, then the row's own overrides.
  for v in $mode_vars; do unset "$v"; done
  export CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=true

  while IFS= read -r kv; do
    [ -z "$kv" ] && continue
    key="${kv%%=*}"
    val="${kv#*=}"
    case "$key" in
      CLAUDE_PLUGIN_OPTION_ORCHESTRATOR)
        if [ "$val" = "false" ]; then unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR; else export CLAUDE_PLUGIN_OPTION_ORCHESTRATOR="$val"; fi
        ;;
      TMPDIR)
        if [ "$val" = "SCRATCH" ]; then export TMPDIR="$scratch_tmpdir"; else export TMPDIR="$val"; fi
        ;;
      *)
        export "$key=$val"
        ;;
    esac
  done < <(echo "$line" | jq -r '.env | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null)

  got_stderr=$(printf '%s' "$input" | "$HOOK" 2>&1 >/dev/null)
  got_exit=$?
  export PATH="$base_path"

  # A blocking row must name what it expects on stderr: grep -F with an empty
  # pattern matches anything, so an empty fragment is a corpus error.
  frag_empty=0
  if [ "$want" -ne 0 ] && [ -z "$stderr_frag" ]; then
    frag_empty=1
  fi

  pass=0
  if [ "$frag_empty" -eq 0 ] && [ "$got_exit" -eq "$want" ]; then
    if [ "$want" -eq 0 ] || printf '%s' "$got_stderr" | grep -qF -- "$stderr_frag"; then
      pass=1
    fi
  fi

  label="$gap"
  [ -z "$label" ] && label="seed"

  if [ "$pending" = "true" ]; then
    if [ "$frag_empty" -eq 1 ]; then
      printf 'todo %s %s (fragment empty)\n' "$label" "$note"
    elif [ "$pass" -eq 1 ]; then
      printf 'todo %s %s (passes now)\n' "$label" "$note"
    else
      printf 'todo %s %s\n' "$label" "$note"
    fi
    todo=$((todo + 1))
    continue
  fi

  if [ "$frag_empty" -eq 1 ]; then
    printf 'FAIL %s %s: want %s but stderr fragment is empty\n' "$label" "$note" "$want"
    fail=$((fail + 1))
  elif [ "$pass" -eq 1 ]; then
    printf 'ok   %s %s\n' "$label" "$note"
    ok=$((ok + 1))
  else
    printf 'FAIL %s %s (got %s, want %s)\n' "$label" "$note" "$got_exit" "$want"
    printf '%s\n' "$got_stderr" | head -2
    fail=$((fail + 1))
  fi
done < "$CORPUS"

printf '%d ok, %d FAIL, %d todo\n' "$ok" "$fail" "$todo"
[ "$fail" -eq 0 ] && exit 0 || exit 1
