# Per-control checklists

Open the relevant section the first time you meet a control type on a surface. Run the full checklist on the first instance per surface; for further instances, run the rows most likely to differ (states, overflow, use after a mode change).

## Contents

1. The common checklist (applies to every control)
2. Buttons
3. Links
4. Text inputs and text areas
5. Selects and dropdowns
6. Toggles, checkboxes and radios
7. Menus and context menus
8. Dialogs, popovers and toasts
9. Tabs
10. Lists and tables
11. Canvases
12. Split panes
13. Drag and drop
14. File inputs

## 1. The common checklist

Apply these rows to every control, then add the type-specific rows below.

| Area | Check |
| --- | --- |
| States | Default, hover, focus-visible, active/pressed, disabled, loading, error, empty. Each state is visibly distinct, and they are consistent with sibling controls of the same type. |
| Disabled | Looks disabled, cannot be activated by pointer or keyboard, and the reason is discoverable (tooltip or nearby text) when it is not obvious. |
| Keyboard | Reachable by Tab in visual order; activates with the conventional keys; focus ring visible in every theme. |
| Pointer variants | Right-click (app menu, native menu or nothing, and is that right?), double-click (no double action), wheel over it (does it hijack scroll?). |
| Repeated use | Works the second, fifth and tenth time; fast repeats do not double-fire or queue stale actions. |
| After a mode change | Still works and still looks right after a theme, view mode, pane or selection change. |
| Layout at sizes | At small and large window sizes it stays reachable, keeps a usable hit area, and does not overlap neighbours. |
| Text overflow | Long labels and values truncate or wrap deliberately; the full value is reachable; nothing spills out of its frame. |
| Accessible name | Has a name that matches its visible label (check in the element list). Icon-only controls have a tooltip and a name. |

## 2. Buttons

- The label says what happens ("Save changes", not "OK" where the action is not obvious).
- Primary versus secondary versus destructive styling is consistent across the product, and only one primary per area.
- Loading state prevents a second click and shows progress; the button returns to normal afterwards, including after an error.
- Destructive buttons confirm or offer undo.
- Icon buttons have tooltips; the tooltip matches the action name used elsewhere.
- Button order in groups (confirm/cancel) is consistent across dialogs.

## 3. Links

- Look like links, distinct from buttons and plain text, in every theme.
- Go where they say. External links are marked and do not replace the app window unexpectedly. (Do not follow links that publish, pay or send anything.)
- Visited and focus states, if styled, are consistent.
- Back after following a link returns to the same place with state intact.

## 4. Text inputs and text areas

- Label visible and associated; placeholder is not the only label.
- Validation: on blur, on submit, or as you type, consistently; the message says what is wrong and how to fix it; the error clears when fixed.
- Boundaries: empty, whitespace only, maximum length (is it enforced and is the limit shown?), one over the limit, pasted text longer than the limit, unicode, emoji, right-to-left, markup-like strings.
- Numbers: negative, zero, decimals with both separators, very large, non-numeric input, leading zeros.
- Enter submits or inserts a newline as the convention for that input says; Escape cancels editing where that is the convention.
- Undo inside the input (platform undo) works and does not trigger the app's global undo, or vice versa.
- Value survives a mode change and a pane resize while editing.
- Autofocus lands where expected when the surface opens.

## 5. Selects and dropdowns

- Opens by click, Enter, Space or Alt+Down per platform; closes by Escape and outside click; focus returns to the trigger.
- Arrow keys move, type-ahead jumps, Enter selects.
- Current value shown and highlighted in the open list.
- Long option lists scroll; long option labels truncate with full text reachable.
- The list positions itself inside the window at every size, including near screen edges, and is not clipped by a parent panel.
- Zero options and one option are handled (empty message, or not a dropdown at all).
- Selecting the already-selected value does not trigger a change.

## 6. Toggles, checkboxes and radios

- The visual state matches the real state after reload and after a mode change.
- The label is clickable and toggles the control.
- Space toggles; arrows move within a radio group.
- The effect of the toggle is immediate or clearly deferred to a save, and consistent with siblings.
- Indeterminate state, if used, is meaningful and visible.

## 7. Menus and context menus

- Right-click is handled by the app where the category expects it; the menu contains the actions valid for what was clicked, and only those.
- Items for the current selection only; disabled items explain themselves where it matters.
- Shortcut hints are correct and work.
- Keyboard: arrows, Enter, Escape, submenus with Right/Left; type-ahead if conventional.
- Menu positions inside the window near every edge, and flips rather than clipping.
- Opening a second menu closes the first; clicking outside closes it without triggering what is underneath.
- Separators and grouping make sense; no empty groups or trailing separators.
- The menu is the same for the same object on every surface, or the difference is justified.

## 8. Dialogs, popovers and toasts

**Dialogs**
- Title says what the dialog is for; primary action names the outcome.
- Focus moves into the dialog, is trapped while modal, and returns to the trigger on close.
- Escape and the close control cancel; clicking the backdrop does what the category expects (and never discards typed input silently).
- Fits at small sizes; content scrolls inside rather than the dialog overflowing the window.
- Consistent padding, header, footer and button order with sibling dialogs.
- Opening the dialog twice (double-click, repeated shortcut) does not stack two copies.

**Popovers and tooltips**
- Anchored to their trigger, stay inside the window, do not cover what the user is working on.
- Dismiss on Escape, outside click, or trigger loss as appropriate.
- Tooltips appear on keyboard focus too, not only hover.
- Do not linger after the trigger disappears (deleted object, closed panel).

**Toasts**
- The message matches the action ("Duplicated" after Duplicate).
- Stays long enough to read; can be dismissed; does not cover primary controls.
- Undo in a toast really undoes, and only that action.
- Many toasts in quick succession stack or queue sensibly.
- Error toasts say what failed and what to do.

## 9. Tabs

- Active tab clearly marked in every theme.
- Arrow keys move between tabs; Tab moves into the panel.
- Tab content state survives switching away and back, or resets consistently.
- Many tabs: overflow handled (scroll or menu), active tab stays visible.
- Long tab labels truncate with full text reachable.
- Closing tabs (if possible): focus moves to a sensible neighbour; closing the last tab leaves a real empty state.

## 10. Lists and tables

- Empty, one row, many rows (scrolling, virtualisation, performance), very long cell content.
- Selection: single, range, toggle, select all; selection visible and preserved across scroll, sort and filter as the category expects.
- Sorting and filtering: indicator visible, results correct, combined sort and filter correct, clearing works, empty result has its own message.
- Keyboard: arrows move, Home/End, Page Up/Down, Enter opens, Delete deletes with confirmation or undo.
- Column resize and reorder, if offered: minimum widths, persistence.
- Sticky headers do not cover the first row after scrolling to an item.
- Counts ("n items", "n selected") match what is shown.
- Inline editing: commit and cancel, validation, focus after commit.

## 11. Canvases

- Pan by drag, by wheel or by keys per category convention; zoom by wheel with modifier, pinch, buttons and shortcuts; the zoom level is shown and resettable; fit-to-content exists.
- Zoom centres on the pointer or the selection as the convention says, without jumps.
- Select by click, add to selection by modifier-click, marquee select by drag on empty space; Escape clears.
- Drag objects: snapping, guides, constraints with modifiers; dropping outside the visible area; dragging while zoomed far in and far out.
- Hit testing: small objects, overlapping objects, objects near edges, at extreme zoom.
- Rendering at extreme zoom: crisp, no seams, labels readable or hidden deliberately.
- Undo for move, resize, create, delete on the canvas.
- Context menu on objects versus on empty canvas: different and appropriate.
- Canvas state (view position, zoom) after a resize, mode change or return from another surface.

## 12. Split panes

- Drag the divider: minimum and maximum sizes respected; content reflows without clipping.
- Collapse and expand: by divider double-click, button or shortcut as offered; collapsed state is visibly recoverable.
- Sizes persist (or reset) consistently across restarts and mode changes.
- At small window sizes the split degrades sensibly (stacks, collapses, or scrolls).
- Divider has a visible affordance and a resize cursor; keyboard-resizable if the category expects it.

## 13. Drag and drop

- Drag affordance visible (handle, cursor).
- During drag: a preview, valid drop targets highlighted, invalid targets clearly refused.
- Drop at the first and last position, onto itself, onto its own child, outside any target, outside the window.
- Escape during drag cancels and restores the original state.
- Auto-scroll when dragging near the edge of a scrollable area.
- Undo after drop.
- Keyboard alternative for the same reordering or moving action, or its absence noted.

## 14. File inputs

Use only files you create in the run folder, never the user's real files.

- Picker opens; cancel leaves state unchanged.
- Drag a file onto the drop zone, if one is claimed.
- Wrong type, zero-byte file, very large file, file with unicode or very long name, many files at once.
- Progress shown; errors say what is wrong; retry works.
- The selected file name is shown, truncated sensibly.
- Uploading never leaves the machine during a test; if a flow sends files to an external service, stop at the confirmation and record it as not covered.
