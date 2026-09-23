# Eval cases

Each case is a folder with `prompt.md` (YAML frontmatter: `max_turns`,
`allowed_tools`, optional `env`) and `graders/*.md`, plus `case.yaml` and
`scaffold.sh` when the case seeds its workspace. Run one case with:

    claude plugin eval . --case <name> --json

That runs a with-plugin arm and a no-plugin baseline (3 runs each by
default, `--runs N` to change) and reports the delta. `-j 3` runs them in
parallel. Results land in `evals/results/<timestamp>/`.

`allowed_tools` in the frontmatter is not enough for gated tools (Bash,
Write, Edit): the operator has to grant them with `--allow-tools`, and a
case that writes its workspace from `scaffold.sh` needs `--scaffold`.
Without them the case fails for the wrong reason: a missing tool or an
empty workspace, not the behaviour under test.

| Case | Flags it needs |
| --- | --- |
| `assumptions-library`, `evaluate-flaw`, `evaluate-sound`, `review-cuts-goldplating`, `teammate-fires`, `teammate-quiet` | none |
| `style-voice-carries` | `--scaffold` (copies `output-styles/unc.md` into the temp workspace) |
| `plan-file` | `--allow-tools Write` |
| `orchestrator-dispatch`, `orchestrator-locate`, `orchestrator-lookup` | `--scaffold --allow-tools Bash,Edit,Write` |
| `tier-route-before-dispatch` | `--scaffold --allow-tools Bash,Edit,Write` |

The orchestrator command, as in CLAUDE.md:

    claude plugin eval . --scaffold --allow-tools Bash,Edit,Write --case 'orchestrator-*'

`--case` takes one glob; a second `--case` flag silently overrides the first.
A Bash grant needs the sandbox backend (`bubblewrap`, `socat`) and fails on a
machine whose `~/.docker` holds symlinks (WSL Docker Desktop); see CLAUDE.md.
Cases that need no Bash avoid that sandbox entirely.

An `llm` grader sees only the final reply by default (`focus: last_message`).
To judge a file the run wrote, give the grader
`focus: {source: file, path: <path>}`; `focus: files` shows only the list of
changed paths, and `focus: trace` opens with pages of injected hook output, which
drowned the Write call in the `plan-file` judge's view.
