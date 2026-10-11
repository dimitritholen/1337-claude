# Nightly QA

A slow, deep pass that blocks nobody. Once a night, a headless Claude runs
`1337:qa` in `full` mode on the main branch and files what it confirms as tasks
in the backlog. The per-PR gate is the 10-15 minute `smoke` run described in
[the pipeline](skills.md#pipeline); this is the rest of the product, which a
smoke run never reaches.

## Prerequisites

- `docs/agents/qa.md` in the project (start, driver, data, budget, out of
  bounds). Without it the run ends in `SKIP` and files nothing.
- A fresh checkout or worktree of main, so the run never touches your working
  tree and tests what was merged.
- The `1337` plugin installed for the user the job runs as.

## The prompt

Save as `nightly-prompt.md`:

```
Nightly QA run on a fresh checkout of main in the current directory.

1. Dispatch the 1337:qa agent with mode full. Budget: whatever
   docs/agents/qa.md says; if it names none, 90 minutes.
2. Read its report. For every confirmed finding (blocker, major, minor or
   polish) add one task to the backlog, titled with the finding, carrying the
   severity, the reproduction and the evidence path under .1337/qa/. File
   product questions as tasks tagged "question". Skip rewrites and false
   findings.
3. Where to file: tasqx (tasqx_add_task) when its tools are present, else the
   tracker named in docs/agents/issue-tracker.md, else a dated file
   plans/qa-YYYYMMDD.md in this checkout.
4. If qa returns SKIP, file nothing; print the reason and stop.
5. Never fix anything, never push, never merge.
```

## The command

```
git worktree add ../qa-nightly origin/main --detach
cd ../qa-nightly
claude -p --model opus \
  --allowedTools "Bash" "Read" "Write" "Edit" "Glob" "Grep" "Skill" "Agent" \
  < /path/to/nightly-prompt.md
cd - && git worktree remove --force ../qa-nightly
```

Add the tasqx tool names to `--allowedTools` when the project files there. Keep
the evidence folder you want to inspect: copy `.1337/qa/` out of the worktree
before removing it.

## Scheduling

Linux or macOS, `crontab -e`, every night at 02:00:

```
0 2 * * * cd /path/to/repo && ./scripts/nightly-qa.sh >> ~/nightly-qa.log 2>&1
```

Windows, Task Scheduler:

```
schtasks /create /tn "nightly-qa" /sc daily /st 02:00 /tr "C:\path\to\nightly-qa.cmd"
```

`nightly-qa.sh` and `nightly-qa.cmd` hold the command above.

## Where it can run

A desktop or TUI app needs a real display and the app's driver, so the job runs
on your own machine (logged in, screen unlocked, not asleep). A CI runner only
fits web apps that a headless browser can drive. Either way the data is the
disposable copy from the contract, never real data.
