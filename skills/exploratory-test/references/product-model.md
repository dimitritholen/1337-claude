# Product model and expectations templates

Two files in the run folder: `product-model.md` describes what the product is; `expectations.md` states what must therefore be true. Write both before the first tour. Keep them as working documents: when exploration reveals a new object type, action or claim, add it and derive the new expectations.

## Contents

1. `product-model.md` template
2. How to fill the capability inventory
3. How to harvest claims
4. Category conventions
5. `expectations.md` template
6. Worked example (generic)

## 1. `product-model.md` template

```markdown
# Product model: <app name as it calls itself>

## Sources read
- <path or screen>: <one line on what it told you>

## What it is
<Two or three sentences: category, who uses it, the core job it does.>

## Capability inventory
| Object type | Action | Reachable from (all routes) | Notes |
| --- | --- | --- | --- |
| <type> | <action> | toolbar; context menu; shortcut <keys>; inspector; drag | |

## Surfaces
| Surface | Shows which object types | Selection model (none / one / many / mixed) |
| --- | --- | --- |

## Claims
| # | Where | Exact text or behaviour promised | Implied check |
| --- | --- | --- | --- |

## Mode and state matrix
| Axis | Values |
| --- | --- |
| Theme | |
| View mode | |
| Window / device size | small, medium, large, extreme aspect |
| Panes / splits | |
| Selection state | none, one, many, mixed types |
| Data volume | 0, 1, many, long values, odd values |
| Session state | first run, returning, after restart |
| Connectivity | online, offline, slow (if relevant) |

## Category conventions
- <convention a user of this category expects>

## User goals and journeys
| Goal (user's words) | Start | Key steps | Done when |
| --- | --- | --- | --- |
```

## 2. Filling the capability inventory

The inventory is the backbone of context reasoning, so make it complete rather than tidy.

- List object types as the user sees them, not as the code names them: whatever the user selects, creates, opens, moves, renames or deletes.
- For each object type, collect actions from every source: menus (app menu, context menu, overflow menus), toolbars, inspector or properties panels, keyboard shortcuts (check the help or shortcut list), drag gestures, double-click, command palette, docs.
- For each action, record every route. An action reachable only from one obscure place is itself a candidate finding later.
- Note actions that exist for one type but are conspicuously absent for a sibling type (for example two kinds of item that both can be renamed, but only one can be duplicated). These become product questions or consistency findings.

## 3. Harvesting claims

A claim is anything that tells the user how the product behaves. Walk every surface once, read-only, and copy the exact text:

- Hints and placeholders ("type to search", "drop files here").
- Empty states and their calls to action.
- Tooltips, including on disabled controls.
- Toasts, banners and confirmation messages ("saved", "copied", "3 items moved").
- Onboarding, tours, release notes, "what's new".
- Labels that imply behaviour ("auto-save", "sync", "undo").
- Keyboard shortcut hints shown next to menu items.
- Docs and specs: every "you can", "will", "always", "never".

Each claim gets an implied check. "Saved" implies: leave, return, restart, and the change is still there.

## 4. Category conventions

Decide what category the product belongs to and write down what users bring from other products in it. Describe conventions, never other products by name. Useful prompts:

- Selection: click selects, modifier-click extends, Escape clears, a selected item looks selected.
- Editing: double-click or Enter edits, Escape cancels, Enter or blur commits, undo covers the last edit.
- Destructive actions: confirmed or undoable, never silent.
- Navigation: back returns to where you were, with scroll and selection preserved.
- Persistence: what the category usually saves automatically, and what it asks about.
- Keyboard: standard shortcuts for copy, paste, undo, redo, select all, find, close.
- Canvas-like surfaces: wheel scrolls or zooms per category norm, there is a way to fit or reset the view.

## 5. `expectations.md` template

```markdown
# Expectations

## Reachability matrix
| Object type | Surface | Action | Expected route(s) | Oracle | Verified? | Shot |
| --- | --- | --- | --- | --- | --- | --- |

## Exclusivity rules
| When selected | Must not show / must disable | Oracle | Verified? | Shot |
| --- | --- | --- | --- | --- |

## Claim assertions
| Claim # | Assertion | Oracle | Verified? | Shot |
| --- | --- | --- | --- | --- |

## Mode parity
| Surface | Modes / themes / sizes to check | Verified per mode | Shots |
| --- | --- | --- | --- |

## Round trips
| Object type | Create, edit, find, undo, redo, delete, survive leave/return/restart | Verified? |
| --- | --- | --- |

## Convention expectations
| Expectation | Oracle | Verified? |
| --- | --- | --- |
```

Fill "Verified?" with `yes`, `no -> F-<id>`, or `not covered: <reason>`. Every unverified row ends up in the coverage map.

## 6. Worked example (generic)

The model says object type "item" has the actions rename, duplicate, delete and move, reachable from a list's context menu and from an inspector panel. Items also appear as cards on a board view and as rows in a search result.

The expectations that follow:

- On the board view, selecting an item card makes rename, duplicate, delete and move reachable (context menu, inspector or shortcut). If the board has no context menu while the list does, check whether the inspector covers it. If neither does, that is a Product consistency finding.
- In search results, at least "open" and ideally the same actions are reachable, or the result clearly takes you to where they are.
- When an item is selected, the inspector must not show controls that belong to a different object type, such as a "group" layout control. If it does, that is a Product consistency or Purpose finding.
- With an item and a group selected together, only actions valid for both are offered, or the UI says why some are missing.
- The empty board says "add your first item"; therefore an add control is visible and works from the empty board itself (Claims).
- The list looks right in the light theme; therefore it must look right in the dark theme too (Product consistency).
