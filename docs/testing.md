# Testing

How to run the plugin's own test suite.

```bash
tests/run-all.sh
```

All of them run against local stand-ins: no key, no network, no browser. A
line starting with `todo` is a pinned gap that a later task will flip, and
never fails the run.

The session rules (evaluate, assumptions, proactive teammate) are checked by
an eval suite in `evals/`, run with and without the plugin so each case shows
whether the rule changes behaviour. It spends real tokens (about $1.20 for
one run per case):

```bash
claude plugin eval . --runs 1
```

[Back to README](../README.md)
