---
name: seed-corpus
description: Turn this shell test suite into a replayable corpus, or seed a corpus from tests/<x>.test.sh with pending rows for the known gaps. Use when you need to capture and replay all the checks a suite exercises as data-driven test rows, so later changes can verify against exact payloads instead of reimplementing the original logic.
---

You are seeding a corpus of captured test data: one JSON row per check, with the exact payload, exit code, and error message each check produces. This becomes a data-driven test suite that can run in isolation without reimplementing the original test's logic.

Worked example: tests/fixtures/guard-corpus.jsonl and tests/guard-corpus.test.sh (sighting: task #657, commit ef0f163).

# Procedure

## 1. Measure the suite at runtime

Do not count checks by reading the test file. Checks in loops execute many times, and reading source code misses the total. Instrument or trace the `check()` helper (or equivalent) at runtime and count every execution.

- Example: orchestrator-guard.test.sh has 125 lines of checks, but they execute 158 times because some sit in loops.

## 2. Capture one row per check execution

For each executed check, capture the exact payload (as JSON), the exit code it produced, and a stderr fragment (the refusal message or error). Write one JSON object per line into tests/fixtures/<name>-corpus.jsonl, in the suite's original order.

Row schema: `{gap, tool, input, want, stderr, env, pending, note}`

- `gap`: empty string for rows captured from the suite; a ticket id for rows added later as known gaps.
- `tool`: the tool name (e.g., `Write`, `Edit`, `Bash`, `Agent`).
- `input`: the exact tool input JSON object (top-level keys: `tool_name`, `tool_input`, and optionally `agent_id` for subagent calls).
- `want`: the exit code the check expects (0 for pass, non-zero for fail).
- `stderr`: a substring from the rejection message; used to verify the error is the right one. For passes (want=0), use empty string.
- `env`: a dict of environment variables the row needs set; the runner will reset mode vars before applying these.
- `pending`: boolean; `true` for known gaps (captured gap tickets, or failures the runner cannot yet reproduce).
- `note`: a one-line human description of what the row tests (e.g., "small edit in main session").

## 3. Identify stateful checks

Some checks depend on earlier state in the same run (e.g., edit-cap rows share a scratch directory and accumulate state across calls). The runner must process rows in file order with one shared TMPDIR per run.

Mark these rows with a sentinel in `env`: `TMPDIR: "SCRATCH"` means the row uses the run's shared scratch directory, not a fresh per-row temp. The runner creates one scratch tmpdir at startup and resets it only between different corpus test runs.

- Example: rows 15-20 in guard-corpus.jsonl all have `TMPDIR: "SCRATCH"`, so the edit-cap counter persists across them.

## 4. Mark known gaps as pending

For gaps you know the suite cannot yet exercise (new features, missing infrastructure), add a row with `pending: true`, the wanted exit code, and a stderr fragment for what will happen when it is fixed.

If the wanted exit code is non-zero (a rejection), the stderr fragment is required; an empty fragment on a blocking row is a corpus error, because `grep -qF -- ""` matches any input and would hide the failure. Call this out in verification.

## 5. Write the runner

Create tests/<name>-corpus.test.sh to replay the corpus against the code under test. The runner:

- Reads lines from tests/fixtures/<name>-corpus.jsonl with jq.
- For each row, sets up the environment and row-specific overrides (reset mode vars first, then apply row env).
- Runs the hook or tool against the input.
- Captures exit code and stderr.
- Asserts exit code matches `want` and stderr contains `stderr` fragment (for want != 0).
- Prints ok/FAIL/todo with the note.
- Restores baseline PATH and env after each row.

Guard corpus runner template: look at tests/guard-corpus.test.sh for the jq loop, TMPDIR/PATH sentinel handling, and the frag_empty corpus-error check. Each row's stderr output must end with a newline when printed.

## 6. Verify with a checker

Before declaring the corpus complete:

- Seeded row count equals the measured execution count. Off-by-one errors hide missing rows.
- Spot-check 8+ rows: pick rows from the start, middle, and end; verify the captured payload is identical to the original test's input.
- Mutation tests: flip `want` 2→0 and 0→2 in a copy and verify both FAIL (the runner catches regressions).
- Rows baking in a literal `$HOME` or user-specific paths are rewritten to use `~` or env vars, or marked in the note.
- Empty stderr fragments on blocking (want != 0) rows are a corpus error.

Green means: runner passes, ok count matches execution count, pending rows print as `todo` (not FAIL), and no FAIL on non-pending rows.

## 7. Integrate

- Add tests/<name>-corpus.test.sh to the test suite (auto-discovered by tests/run-all.sh if named `*.test.sh`).
- Update CLAUDE.md under Layout: `.claude/skills/seed-corpus/`: repo-local skill for turning shell test suites into JSONL corpora.
- Check that `bash tests/run-all.sh` passes green.

# Why this is not obvious

- **Wrong execution count:** A test file with 125 lines of checks may execute 158 times because of loops. Reading the source misses this and seeding incomplete corpora.
- **Shared-state discovery:** Some checks are stateful and must run in order with one shared directory. Without spotting this, the corpus runner produces false passes when rows that should affect each other run in isolation.
- **Empty-fragment hole:** A blocking row (want != 0) with an empty stderr fragment will always pass because `grep -qF -- ""` matches any input. Only a checker that explicitly rejects empty fragments on failures finds this.
- **PATH row that cannot run:** A row that overrides PATH to hide a command (e.g., `PATH=/nonexistent` to disable jq) may prevent the test hook's shebang from resolving. The runner must use absolute bash paths or a PATH sentinel like `PATH: NOJQ` (a directory with bash but nothing else).
