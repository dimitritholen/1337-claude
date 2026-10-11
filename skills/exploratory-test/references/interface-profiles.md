# Interface profiles

The method in SKILL.md is the same for every product. What changes per interface is how you drive it, what a "screenshot" is, and which rubric rows and checklists apply. Decide the profile in step 1 and write it at the top of `product-model.md`. A product can have more than one (a web app with a CLI, a desktop app with an embedded web view).

## Graphical: web and desktop apps

Covers browser apps, desktop apps built on a web view, and native desktop apps.

- **Driver:** browser automation or WebDriver against the real app (see `driver-contract.md`). Embedded frames and web views are separate documents: enter them before listing or clicking their elements.
- **Screenshot:** a window image, plus region zooms and computed metrics.
- **Applies fully:** visual rubric, all control checklists, right-click and context menus, pointer and keyboard routes, themes, window sizes and breakpoints.

### Data-heavy business apps (issue trackers, CRMs, admin consoles)

Extra rows for the product model and the edge-case generation:

- **Roles and permissions:** every role the product has; for each object type, which actions each role may take. Test at least the most and least privileged role. A control shown to a role that may not use it, or an action that fails only after submit, is a finding.
- **Workflows and states:** the states an object moves through (for example open, in progress, review, done) and the allowed transitions; try forbidden transitions, reopening, and transitions from list, detail and bulk views.
- **Lists at scale:** sort, filter, search, group, paginate or virtual scroll, saved views; combinations of them; empty results; a filter that hides the item you just edited; selection that survives (or deliberately resets on) paging and filtering.
- **Bulk actions:** select many, mixed states, partial failure, undo.
- **Forms:** required fields, validation timing, server-side errors after client-side success, unsaved-changes guard on leaving, autosave versus explicit save, conflicting edits.
- **Concurrency:** the same object open in two tabs, windows or sessions; edit in one, view or edit in the other; stale data on return; notifications and live updates arriving mid-task.
- **Links and history:** deep links to objects, back and forward through the app's own navigation, a link to a deleted or forbidden object.

## Terminal: TUI and CLI tools

Covers full-screen terminal UIs (curses-style, panes, lists, forms in the terminal) and line-oriented CLIs.

- **Driver:** run the tool inside a controllable terminal: a terminal multiplexer session (send keys, capture the pane, resize the window) or a pseudo-terminal harness with a terminal emulator library. Primitives: start the tool with a given size, send keys and key chords (including Escape, Tab, arrows, function keys, Ctrl-combinations, mouse events if the tool supports them), capture the screen as text with colour and style attributes, resize the terminal, read exit code, stdout and stderr, and the files the tool writes.
- **Screenshot:** the captured screen grid (text plus colour attributes), saved per step as a text file; also render it to an image if the harness can, so colour and contrast can be judged. Capture after the screen settles; terminals redraw incrementally.
- **Rubric, adapted:** alignment is in character cells, so columns and borders must line up exactly; box-drawing characters must join; nothing may wrap or tear at the terminal width; truncation must be deliberate (ellipsis) and keep the distinguishing part; colours must stay legible on both light and dark terminal backgrounds and the tool must still be usable without colour (check `NO_COLOR` and a monochrome terminal if supported); the cursor and focus must be visible; status and help lines must match the current mode.
- **Checklists, adapted:** keyboard is the primary route, so every action needs a key and the keys must be discoverable (help screen, footer hints) and consistent with the category's conventions (q or Escape to back out, `?` for help, `/` to search, j/k or arrows); modal states must be clear; Ctrl-C and Ctrl-Z must behave safely; terminal state must be restored on exit, crash and suspend (cursor, echo, alternate screen).
- **Edge cases, adapted:** tiny terminals (for example 40×10) and very wide ones; resize during a long operation; Unicode, wide characters and emoji in data; very long lines; piped input and output (not a TTY); missing or read-only config; interrupted runs and re-runs; exit codes and error messages for every failure (a failure must never exit 0).
- **CLI specifics:** `--help` accuracy against actual behaviour (claims oracle), flag combinations and conflicts, defaults, idempotence of re-running, output stable enough to script against, errors on stderr, helpful messages for typos.
