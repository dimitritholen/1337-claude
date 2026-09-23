# Testing

How to run the plugin's own test suite.

```bash
tests/run-all.sh
```

All of them run against local stand-ins: no key, no network, no browser. A
line starting with `todo` is a pinned gap that a later task will flip, and
never fails the run.

## Test suites

- `tests/builder-dispatches.test.sh`
- `tests/catalogue.test.sh`
- `tests/dispatch-nudge.test.sh`
- `tests/generate.test.sh`
- `tests/git-subcommand.test.sh`
- `tests/guard-corpus.test.sh`
- `tests/lib.test.sh`
- `tests/orchestrator-guard.test.sh`
- `tests/png.test.sh`
- `tests/preview.test.sh`
- `tests/read-cap.test.sh`
- `tests/replay.test.sh`
- `tests/review-gate.test.sh`
- `tests/route-guard.test.sh`
- `tests/rule-copies.test.sh`
- `tests/setup-key.test.sh`
- `tests/stop-review.test.sh`
- `tests/subagent-rules.test.sh`
- `tests/terse-governor.test.sh`
- `tests/tier-route.test.sh`
- `tests/tiered-rules.test.sh`
- `tests/visual-route.test.sh`

The session rules (evaluate, assumptions, proactive teammate) are checked by
an eval suite in `evals/`, run with and without the plugin so each case shows
whether the rule changes behaviour. It spends real tokens (about $1.20 for
one run per case):

```bash
claude plugin eval . --runs 1
```

[Back to README](../README.md)
