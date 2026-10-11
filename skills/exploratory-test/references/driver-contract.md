# Driver contract

The tester drives the application through whatever automation the project offers: a browser automation library, a desktop accessibility-tree driver, a remote-debugging protocol, an in-repo test harness. The skill is written against the primitives below, not against any one tool, so it works on any application that can be driven at all.

## Required primitives

| Primitive | What it must do | Why the method needs it |
| --- | --- | --- |
| Launch on a data copy | Start the app pointed at a disposable copy of data or a fresh temp profile, and return when it is ready for input | Safety rule; also the only way to get a known start state for reproduction |
| Restart / reset | Close and relaunch, or reset to the known start state | Every finding is reproduced twice from a known state |
| Screenshot | Capture the full window (and ideally a region) to a named file | Every step is judged visually |
| List visible elements | Return the visible interactive elements with role, accessible name, text, state (enabled, checked, expanded, focused) and bounding box | Choosing targets, checking state, measuring alignment and overlap |
| Click, double-click | By selector or by coordinates | Basic interaction; double-click often opens editing or detail views |
| Right-click | By selector or coordinates, and **report whether the app handled it**: an app-drawn context menu appeared, versus the event fell through to the native browser or OS menu, versus nothing happened | The "what can I do with this?" tour depends on knowing whether a context menu exists for an object |
| Hover | Move the pointer over a target and hold | Tooltips, hover states, hover-revealed actions |
| Wheel | Scroll or zoom by a given delta at a position, with optional modifier keys | Lists, canvases, zoom behaviour |
| Drag | Press, move along a path, release; with optional modifier keys | Drag and drop, reordering, resizing splits, selecting regions on a canvas |
| Key combinations | Send single keys and chords (modifier + key), including Tab, Shift+Tab, Escape, Enter, arrows, platform shortcuts | Keyboard-only tour, shortcuts, focus behaviour |
| Type | Type text into the focused element, including unicode, long strings and pasted content | Data tour, input validation |
| Enter / leave embedded frames | Switch the driving context into an embedded frame, web view or child window and back | Many apps host content in frames or child windows the top-level driver cannot see |
| Resize the window | Set the window or viewport to a given size, and ideally the device pixel ratio | Resize and device tour |
| Read-only eval | Read state: focused element, computed styles, scroll position, console errors, current route, storage contents | Confirming what the screen suggests; catching silent errors |

Nice to have: console and error log capture, network log (read-only), emulated colour scheme and reduced motion, emulated slow network or offline, clipboard read.

Read-only eval means reading. Do not call app functions, mutate stores, or patch the DOM to get past an obstacle. If you need to change state to test something, do it through the UI or through the data copy before launch.

## Finding the project's driver

Look before you build. In order:

1. The repo's e2e or test folder: a documented exploratory, manual or "interactive" driver, a REPL harness, a script that launches the app with a test profile.
2. Contributor docs, README sections on running the app under automation, dev scripts in the package manifest or build file.
3. Existing e2e configuration: it already knows how to launch the app on a fixture, which you can reuse with a copied data directory.
4. Tools available in this session (a browser or desktop automation tool, a computer-use capability).

If you find a driver, read its usage notes, then confirm each primitive with a tiny check (screenshot, list elements, one click, one key) and record in `log.md` which primitives work.

If no driver exists and you cannot assemble the primitives from available tools, stop and ask the user for one. Tell them which primitives you need, which ones are optional, and what you can still test without the missing ones.

## When a primitive is missing

Never fake a primitive or describe a check you could not run. Instead:

- Record it in `log.md` at setup.
- Skip or narrow the tours that depend on it.
- Add a row to the coverage map's "not covered" section naming the missing primitive and what it blocked.

Typical consequences:

| Missing | Affects |
| --- | --- |
| Right-click handling report | "What can I do with this?" tour: context-menu reachability is unverified |
| Resize | Resize and device tour entirely |
| Frames | Any surface inside an embedded frame or child window |
| Coordinates | Canvases, drag, precise overlap checks |
| Theme / colour-scheme control | Theme tour, unless the app has its own theme switch |

## Driver pitfalls that create false positives

- Acting before the app is ready (still loading, still animating). Wait for a stable screenshot or a ready signal before the action and before the screenshot.
- Coordinates captured at one window size reused at another.
- A screenshot taken mid-transition showing a half-drawn state. Retake after a short settle before calling it a visual bug.
- A key sent while focus is in the driver's own surface or another window.
- A synthetic right-click that never reaches the app's handler. Cross-check with the keyboard context-menu key or Shift+F10 where the platform supports it.
