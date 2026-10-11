# Project contract: docs/agents/qa.md

A project adds `docs/agents/qa.md` so the exploratory-test skill, and the `1337:qa` agent that runs it, can test the app unattended. The file is short and concrete: commands, paths, limits. Without it the tester only runs when it can find a driver and a safe data copy on its own; otherwise it reports SKIP.

Use these sections, in this order. Omit **Surfaces** if you have no mapping.

## Start

How to build and start the app (and any dev server), how to know it is ready, how to stop it.

```
- Build: `npm run build`; start: `npm run dev` (serves http://localhost:5173)
- Ready when `curl -sf http://localhost:5173/health` returns 200
- Stop: kill the process group; remove nothing else
```
Desktop: `make run-debug`, ready when the main window title appears in the driver's element list. TUI: `tmux new -d -s qa './app'`, ready when the prompt string shows in `capture-pane`; stop with `tmux kill-session -t qa`.

## Driver

Which driver, and how it is called. It must satisfy `references/driver-contract.md`.

```
- Web: Playwright, `npx playwright test --config qa/playwright.config.ts` or the helper `qa/drive.mjs <action> <args>`
- Desktop: the project's own driver, `scripts/qa-drive.sh <launch|shot|click|key|eval>`
- TUI: `tmux send-keys -t qa ...` to type, `tmux capture-pane -p -t qa` to read the screen
```

## Data

How to make a disposable copy of realistic data, and where it goes. Never test on the user's real data.

```
- Copy: `cp -r ~/.app/data "$RUN/data"`; start the app with `APP_DATA_DIR="$RUN/data"`
- Or seed: `npm run seed -- --out "$RUN/data"` (invented records only)
```

## Budget

Costly jobs allowed per run, such as agent runs or paid API calls. Past the budget, log the flow as not covered.

```
- At most 3 LLM-backed actions per run; 0 image or video generations
- No calls to paid APIs outside the sandbox key in `.env.qa`
```

## Surfaces

Optional. Maps source paths to surfaces so change mode can pick what a diff touches.

```
- src/billing/**   -> Billing (invoice list, invoice detail)
- src/ui/editor/** -> Editor (canvas, toolbar, inspector)
- internal/tui/**  -> Main list, Detail pane, Help overlay
```

## Out of bounds

Things never to do, on top of the skill's own safety rules (no push, publish, payment or external send).

```
- No git push, no deploys, no emails or webhooks
- Never touch the production or staging backend; use the local one from Start
- Do not delete or rename files outside $RUN
```
