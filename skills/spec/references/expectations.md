# Deriving the Expectations block

The Expectations block turns the user stories and the touched surfaces into rows that can be checked by a test. Work out once, at spec time, what the feature must do, its edge cases and its visual rules, so the build gets fast automated tests instead of a slow exploratory QA run. Nothing here is specific to a product kind: read "surface" as a screen, pane, dialog, route, TUI view or CLI command.

## Row format

Table columns: `ID | Expectation | Check | Seam`.

- **ID**: `E-01`, `E-02`, ... in one run across all kinds. Plan and implement refer to rows by ID.
- **Expectation**: one statement, observable, with a concrete value where there is one.
- **Check**: one of
  - `e2e`: behaviour through the UI or CLI.
  - `unit`: logic at a seam below the UI.
  - `metric`: a measured style value (box, spacing, colour, contrast).
  - `visual`: screenshot comparison per theme and size class.
  - `judgement`: needs a human or `1337:qa` eyes (design quality, quality of generated output).
- **Seam**: the agreed seam the test runs at (from the spec's seams step).

Prefer `e2e` and `metric` over `visual`, and `visual` over `judgement`. A row is `judgement` only when no measurement or comparison can decide it.

Collect the touched surfaces first: from the stories, the implementation decisions and a look at the code. Every section below generates rows from those two inputs. Skip a kind that does not apply and say so in one line; never drop one silently.

## Acceptance

What it is: the user stories, restated as checks.

Generate: one Given/When/Then row per user story, more for a story with several outcomes. Use the glossary's nouns.

Example: `E-01 | Given a list with 3 items, when the user deletes the second, then 2 items remain and the first and third keep their order | e2e | UI`

## Claims

What it is: every promise the product makes in words.

Generate: list the feature's on-screen copy, hints, placeholders, empty states, tooltips, toasts, help text and docs. Each promise is a row: what the text says will happen, does happen. An empty state offers the action it names, and the action works from there.

Example: `E-02 | The empty list says "Add your first item"; an Add control is visible on that state and creates an item | e2e | UI`

## Context map

What it is: the context a user keeps while they leave and come back.

Generate: place × excursion × return. Places are what the user can be "in" (a view, pane, mode, object) with the context that belongs to it (scroll, selection, focus, half-typed input, active tool). Excursions are what they can do in between: another pane, mode, theme, dialog, presentation mode, another object, a resize, a background job. Returns are close, Escape, back, toggle off, undo. Every plausible combination on the touched surfaces is a row: context is kept, or visibly and deliberately reset.

Example: `E-03 | Scroll to row 40, open the detail dialog, press Escape: the list is still at row 40 and the row stays selected | e2e | UI`

## Transitions

What it is: the control set after the selection changes type.

Generate: for each pair of selectable object types on the touched surfaces, the controls shown (toolbar, inspector, hints) after switching from one to the other. No leftovers from the previous type; a mixed selection shows only what applies to all.

Example: `E-04 | Select a text item, then an image item: the inspector shows image controls only, no font controls | e2e | UI`

## Parity

What it is: the same information and function everywhere the object appears.

Generate: for every theme, size class (minimum window, default, wide; each breakpoint) and representation (modes or views of the same object), what is shown and what works. What appears in one must not silently vanish in another.

Example: `E-05 | The status badge is visible and its label readable in the light theme, the dark theme and at the minimum window size | metric | UI`

## Conventions

What it is: what users of this product category expect without being told.

Generate: take the category's conventions that apply to the touched surfaces: right-click or context menu, double-click to open or edit, Escape closes the topmost transient surface, Enter confirms the default action, undo for destructive actions, a keyboard route to every action, focus visible. TUI and CLI: q or Escape backs out, `?` shows help, `--help` matches behaviour, failures exit non-zero.

Example: `E-06 | Double-clicking a row opens it for editing; Escape cancels and restores the old value | e2e | UI`

## Inputs and controls

What it is: how each control type behaves.

Generate: per control type on the surface, one row. Selects do not accept free text; fields validate and say why on rejection; numeric fields reject letters and clamp or refuse out-of-range values; disabled controls say why; toggles show their state; buttons give feedback while their action runs.

Example: `E-07 | The "Quantity" field rejects "abc" and shows an inline message; the value stays unchanged | e2e | UI`

## Styling

What it is: measurable visual rules, nothing else.

Generate: read the project's design system, tokens and design references (docs, mockups, prototypes) if present. Each rule becomes a row with a number: spacing and alignment values, radii, type scale, colour tokens per theme, contrast at least 4.5:1 for text and 3:1 for UI components and focus rings, no overflow or clipping at the minimum size. Cite the token or reference. No design system: derive the values from the sibling surface the feature sits next to and say so. Vague taste ("feels balanced") is not a row; it goes to `judgement`.

Example: `E-08 | Card padding is 16px, radius 8px, in both themes (tokens space-4, radius-md) | metric | UI computed style`

## Edge cases

What it is: the cases an ad hoc pass would find late, generated up front.

Generate, per main surface, at least ~10 rows:

- Sequences: A then B, A twice, A, undo, B, B before A.
- State × event: each state (empty, one, many, loading, error, editing) crossed with each event (click, key, resize, theme switch, a background job finishing).
- Boundaries: 0, 1, many; first and last; longest realistic text; odd characters.
- Timing: double activation, an action during loading or a running job.
- Persistence: leave and return, reload, restart.

Rank by how likely the user is to hit it. Rows you will not cover go under Out of Scope with their reason, never dropped silently.

Example: `E-09 | A name of 200 characters is truncated with an ellipsis in the list, shown in full in the detail view, and does not widen the layout | e2e | UI`

## House rules

Rules that hold for every surface of the product (no native context menu in a desktop app, AA contrast in every theme, no overflow at the minimum size, Escape closes the topmost surface, focus visible) belong in one project-wide suite that sweeps all surfaces, not in each feature's spec.

The spec lists only the house rules the feature is subject to, by name, as a line under the block. When the feature introduces a new kind of surface (a first dialog, a first side panel, a first full-screen mode), it adds the house rule for that kind and extends the sweep.
