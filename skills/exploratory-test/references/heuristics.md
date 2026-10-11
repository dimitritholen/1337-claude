# Heuristics: oracles, coverage and tours

## Contents

1. HICCUPPS(F) oracles
2. SFDIPOT coverage grid
3. Charter format
4. Tour catalogue
   - Journey tour
   - "What can I do with this?" tour
   - Claims tour
   - Consistency tour
   - Back-and-forth tour
   - Interruption tour
   - Data tour
   - Theme tour
   - Resize and device tour
   - Keyboard-only tour
5. Familiar problems to probe for

## 1. HICCUPPS(F) oracles

An oracle is how you recognise a problem. Each finding cites at least one. When two oracles agree, confidence goes up; when the only oracle is your taste, file it as a `product question` or label confidence low.

| Oracle | The question to ask | Typical evidence |
| --- | --- | --- |
| **History** | Did this behave differently in an earlier version, or earlier in this same session? | Changelog, older screenshots, a step in `log.md` where it worked |
| **Image** | Would this embarrass the product or its makers in front of a customer? | Typos, broken layout on the first screen, debug text, placeholder copy |
| **Comparable products** | Do products in the same category handle this differently, so users will arrive expecting otherwise? | The category conventions in the product model |
| **Claims** | Does any UI text, doc, spec, tooltip, toast or label promise otherwise? | A row in the claims list |
| **User expectations** | Would a reasonable user, with this goal, expect something else? | The journey; the user's words |
| **Product consistency** | Does the product do this differently on another surface, for another object type, or in another mode or theme? | Two screenshots side by side |
| **Purpose** | Does this get in the way of what the feature is for? | The user goal it blocks or slows |
| **Statutes and standards** | Does it break an accessibility standard (WCAG), a platform guideline, or a legal requirement? | The rule and how it is broken |
| **Familiar problems** | Does it match a known class of bug? | The pattern from section 5 |

## 2. SFDIPOT coverage grid

Use it twice: when planning charters (where have I not looked yet?) and at the end, in the coverage map (every row has a tour or a reason).

| Dimension | What to cover | Tours that usually cover it |
| --- | --- | --- |
| **Structure** | What the product is made of: windows, panes, frames, routes, dialogs, embedded content | Consistency, resize, "what can I do with this?" |
| **Function** | What it does: every action in the capability inventory | Journey, "what can I do with this?", claims |
| **Data** | What it processes: inputs, stored objects, imports, exports, sizes, encodings | Data, back-and-forth |
| **Interfaces** | How users and other systems reach it: pointer, keyboard, menus, shortcuts, clipboard, drag and drop, files, frames | Keyboard-only, "what can I do with this?", control checklists |
| **Platform** | What it depends on: OS, window manager, display scaling, fonts, themes, browser engine | Theme, resize and device |
| **Operations** | How it is used in practice: real goals, interruptions, long sessions, power users, first-time users | Journey, interruption, back-and-forth |
| **Time** | Timing and sequence: fast repeated clicks, slow responses, timeouts, autosave intervals, restart, concurrency | Back-and-forth, interruption, data (slow or large loads) |

## 3. Charter format

Write this line into `log.md` at the start of each tour:

```
CHARTER <tour> | mission: <one sentence> | surfaces: <list> | vary: <what you will change> | box: <minutes> or <n actions>
```

And at the end:

```
DEBRIEF <tour> | found: <ids or none> | covered: <surfaces/rows> | not covered: <what and why> | next: <follow-up charter idea>
```

## 4. Tour catalogue

Each tour lists its mission, how to run it, and what to vary. Take a screenshot after every step and judge it for function and for eyes.

### Journey tour

**Mission:** complete each real user goal from the product model, start to finish, as that user would.

- Start from a realistic state, not the cleanest one: a returning user with some data, then a first-time user with none.
- Follow the goal, not the menu structure. If you have to hunt for the next step, that is evidence (Purpose, User expectations).
- At each step ask: does the screen tell me where I am, what just happened and what to do next?
- At the end, verify the outcome really exists: reopen it, find it, restart and look again.

**Vary:** first run versus returning; the shortest route versus the one most users would take; doing it twice in a row.

### "What can I do with this?" tour

**Mission:** for every object type on every surface where it appears, verify that its actions are reachable there, and that nothing belonging to another type shows up.

Run it row by row against the reachability matrix in `expectations.md`. For each object on each surface:

1. Hover it: is there a hover state, tooltip or hover-revealed action?
2. Click it: does it look selected? What changes in toolbars, inspectors and menus?
3. Double-click it: does it open, edit or do nothing, and does that match the category convention and the other surfaces?
4. Right-click it: did the app handle it (an app-drawn menu) or did it fall through to the native menu? Is the menu complete for this type, and free of other types' actions?
5. Try the keyboard routes: the shortcuts from the inventory, the context-menu key, Enter, Delete, F2 or the platform equivalent for rename.
6. Look at the inspector or properties panel: are the controls for this type, and only this type?
7. Repeat with a multi-selection of the same type, then a mixed selection.

**Vary:** surface; selection size; selection mixed with other types; state of the object (new, edited, locked, empty).

### Claims tour

**Mission:** verify every claim in the product model is visibly true.

- For each claim, perform the check it implies and screenshot the evidence.
- Empty states: the promised action is reachable from the empty state itself.
- Toasts: the thing announced has actually happened, and the toast names the same action the button did.
- Shortcut hints next to menu items: the shortcut works, from the places where it should.
- Docs and help: every "you can" is something you can do.

**Vary:** reach each claim's surface by more than one route; check it in each theme.

### Consistency tour

**Mission:** the same object, action or pattern must look and behave the same wherever it appears.

- The same object type shown on two surfaces: same name, same icon, same actions, same terminology.
- The same action from two routes (toolbar and context menu, shortcut and button): same result, same confirmation, same undo behaviour.
- Sibling surfaces (two dialogs, two side panels, two list views): same padding, header style, close control position, button order, radii.
- Terminology: one name per thing across labels, toasts, docs and errors.

**Vary:** surfaces; routes; modes.

### Back-and-forth tour

**Mission:** break the assumption that every task starts fresh.

- Do something, navigate away, come back: is the state, selection, scroll and unsaved input where you left it, or clearly reset?
- Undo, redo, undo again; undo across a navigation; undo after a save.
- Repeat the same action many times quickly; repeat it slowly.
- Open, close, reopen a dialog or panel: does it remember what it should and forget what it should?
- Create, delete, create again with the same name.
- Restart the app mid-task: what survives?
- Use the browser or app back and forward controls, if any, through a multi-step flow.

**Vary:** speed; number of repeats; whether you save in between.

### Interruption tour

**Mission:** change the context in the middle of a task and see whether the task survives.

In the middle of an edit, a drag, an open dialog, a multi-step flow or a selection:

- Switch theme.
- Switch view mode.
- Open, close or resize a pane or split.
- Change the selection, or clear it.
- Resize the window across a layout breakpoint.
- Switch to another window and back; minimise and restore.
- Trigger another action from a shortcut.

Then check: is the task's state intact, is the UI consistent with the new context, are there controls left over from the old context, does focus land somewhere sensible?

**Vary:** the moment of interruption (just started, half-way, at the confirmation step).

### Data tour

**Mission:** replace clean fixture data with the data real users have.

For every list, table, input and object property:

- **0**: empty collection, empty string, no selection. Is there a real empty state, or a blank region?
- **1**: one item. Do plural labels, separators, layouts and "select all" still make sense?
- **Many**: hundreds or thousands. Scrolling, performance, virtualisation glitches, counts, pagination.
- **Long**: very long names and values, long words with no break opportunity, many lines. Truncation, wrapping, tooltips revealing the full value.
- **Odd**: unicode, right-to-left text, emoji, combining characters, leading and trailing spaces, only spaces, special characters, markup-like text, very large and very small numbers, negative numbers, zero, dates at boundaries, duplicate names, pasted rich text.

**Vary:** where the data enters (typed, pasted, imported, created by drag); where it is later shown.

### Theme tour

**Mission:** every surface correct in every theme.

- Visit every surface from the product model in each theme, including high-contrast or system themes if offered.
- Look for hard-coded colours that do not switch, text that becomes unreadable, icons that disappear against the background, borders and dividers that vanish, images or illustrations designed for one theme only, focus rings with no contrast.
- Switch theme with transient surfaces open (menus, dialogs, tooltips, toasts) and while something is selected.

**Vary:** theme switched in-app versus via the OS setting; switched before launch versus during a session.

### Resize and device tour

**Mission:** every surface usable and composed at every size the product supports.

- Small (narrow phone or narrow window), medium, large, very large; extreme aspect ratios (very wide and short, very tall and narrow).
- Cross every layout breakpoint while something is open or selected.
- Check: nothing important is clipped or unreachable, toolbars collapse sensibly, dialogs fit and scroll, split panes respect minimums, canvases keep their view sensibly, touch targets are big enough at small sizes.
- Display scaling or zoom levels, if the driver supports it.

**Vary:** resize slowly versus jump straight to a size; resize with a dialog open.

### Keyboard-only tour

**Mission:** complete the main journeys without the pointer.

- Tab order follows visual order; nothing is skipped; nothing traps focus except modal surfaces, which must trap it and release it on close.
- Focus is always visible, in every theme.
- Every action in the capability inventory has a keyboard route, or its absence is noted.
- Escape closes the topmost transient surface and returns focus to where it came from.
- Enter and Space activate the focused control; arrow keys move inside composite controls (menus, lists, tabs, grids).
- Shortcuts do not fire while typing in an input, unless that is the convention.

**Vary:** start from different focus positions; after a mode change; inside embedded frames.

## 5. Familiar problems to probe for

Known bug classes worth trying on purpose:

- Stale state after navigation or after a mode switch (old selection, old inspector contents).
- Controls from a previous selection or mode left behind.
- Double submit on fast double-click or Enter held down.
- Off-by-one in counts, pagination, "n selected".
- Lost focus after a dialog closes, after delete, after a list re-renders.
- Undo stack that skips, merges or loses steps; redo cleared unexpectedly.
- Unsaved changes lost on navigation without a warning.
- Toast or confirmation claiming success when the action failed.
- Layout jump when content loads, scrollbars appear or fonts swap.
- Truncation hiding the part of a value that distinguishes it from its neighbours.
- Z-index fights: popovers under panels, tooltips under dialogs, sticky headers covering content.
- Things that work on first use but not on second (event handlers bound once, state not reset).
- Silent console errors during an action that otherwise looks fine (check via read-only eval).
