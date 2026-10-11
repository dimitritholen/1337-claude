# Visual rubric

Judge every screenshot the way a senior product designer reviewing a build would: is this composed, legible and consistent, or does it merely render? DOM assertions cannot see any of this, which is why scripted suites miss it and why it is your job.

## How to look

1. **Squint first.** Look at the whole screenshot at reduced attention. What draws the eye first, second, third? Does that match what matters most on this screen? Is anything visually loud for no reason?
2. **Then scan by region.** Header, toolbars, main content, side panels, footer, transient surfaces. Zoom into each region when the driver allows a region screenshot.
3. **Compare in pairs.** Put the screenshot next to its sibling: the same surface in another theme, a sibling dialog, the same list with one item versus many. Inconsistency is much easier to see in pairs.
4. **Measure when in doubt.** Use the element list's bounding boxes to confirm a suspected misalignment or uneven gap before reporting it. A 1–2 px difference is polish at most; a visible step in an edge that should be straight is a real finding.

Report a visual finding only when you can point at it in the screenshot and say which rubric item it breaks and why it matters to the user. "Looks off" is not a finding; "the second column's text starts 6 px left of the header above it, so the column reads as misaligned" is.

## The rubric

### Spacing rhythm and margins
- **Right:** spacing follows a consistent scale; related things are close, unrelated things further apart; margins to window edges are equal on comparable sides.
- **Wrong:** cramped groups where elements nearly touch; uneven gaps between items in the same list or toolbar; content flush against a panel edge while siblings have padding; one section with noticeably tighter or looser rhythm than its neighbours.

### Alignment and baselines
- **Right:** elements share edges and centre lines on purpose; text in a row sits on a common baseline; icons are optically centred with their labels.
- **Wrong:** ragged left edges in a column of fields; labels and values on different baselines; an icon sitting a few pixels high or low against its text; a button row whose buttons have different heights.

### Hierarchy
- **Right:** the primary action and the primary content are the most prominent things; secondary information recedes; one clear focal point per area.
- **Wrong:** everything at the same weight so nothing leads; a secondary control louder than the primary; a heading that looks like body text; two competing focal points.

### Type scale
- **Right:** a small number of sizes and weights used consistently for the same roles; comfortable line height; line length that reads easily (roughly under 80 characters for running text).
- **Wrong:** many near-identical sizes; the same role (section title, label) styled differently on different surfaces; cramped line height; long lines of running text across a wide panel; all-caps or tracking used inconsistently.

### Contrast and legibility
- **Right:** text and essential icons readable against their background in every theme; meets WCAG contrast (4.5:1 for body text, 3:1 for large text and essential non-text elements such as focus indicators and input borders).
- **Wrong:** grey-on-grey secondary text that disappears; placeholder text mistaken for a value; text over images or gradients without enough contrast; disabled and enabled states that are hard to tell apart; focus ring invisible on some backgrounds.

### Colour and theme consistency
- **Right:** colours come from one coherent palette; semantic colours (error, warning, success, selection) mean the same thing everywhere; every surface switches cleanly with the theme.
- **Wrong:** a hard-coded light colour stuck in a dark theme (or the reverse); two different "selected" colours on two surfaces; an error colour used decoratively; an illustration or icon that only works on one background.

### Overlap and covering
- **Right:** nothing the user needs is hidden behind something else; transient surfaces sit above what they belong to and never cover the thing being edited.
- **Wrong:** a sticky header or toolbar covering the top row; a popover rendering under a panel; a toast covering the primary button; a floating control covering content at small sizes; text overlapping an icon.

### Clipped or overflowing text
- **Right:** long text truncates or wraps deliberately, with the full value reachable (tooltip, expand, detail view); nothing spills outside its frame.
- **Wrong:** text cut mid-glyph at a container edge; truncation that hides the part that distinguishes items ("Project report fi…" for every row); text running out of a button or badge; a label pushed onto two lines that breaks the layout.

### Sibling consistency: radii, padding, framing
- **Right:** sibling surfaces (dialogs, cards, panels, inputs, menus) share corner radii, padding, border and shadow treatment, header style and close-control placement. Differences encode real differences in role.
- **Wrong:** two dialogs with different padding and button order; one panel with a border and its sibling without; radii that differ between inputs and the buttons next to them; one menu with a shadow and another flat.

### Decoration without purpose
- **Right:** every border, divider, badge, colour accent and animation tells the user something.
- **Wrong:** dividers between every element so structure drowns in lines; badges with no meaning; gradients and shadows used as filler; motion on elements the user did not touch, repeating for no reason.

### Empty space without reason
- **Right:** white space groups and separates on purpose, and scales sensibly with the window.
- **Wrong:** a large blank region where content clearly failed to render or a layout failed to stretch; a narrow content column floating in a huge window; an empty panel with no empty-state message; a gap where a removed element used to be.

### Crafted or generic
- **Right:** the screen looks designed for this product and this task. Choices of type, spacing and colour are deliberate and consistent; details such as icon weight, cursor changes and state transitions are finished.
- **Wrong:** it looks like unadjusted framework defaults or a template: default focus outlines on custom-styled controls, mismatched icon sets, generic placeholder copy ("Lorem ipsum", "Item 1", "Untitled") left in, the same rounded card and soft shadow applied to everything regardless of role.

## Severity for visual findings

- **major**: content or controls the user needs are unreadable, covered or unreachable; a theme makes a surface unusable.
- **minor**: noticeable inconsistency or misalignment a user will see and that makes the product feel unfinished; legibility reduced but still readable.
- **polish**: small rhythm, alignment or radius differences a designer will notice and most users will not.

A visual issue only becomes a blocker if it blocks a journey (for example, the only confirm button is permanently covered at the default window size).

## Type for visual findings

- `visual`: colour, contrast, type, decoration, crafted versus generic.
- `layout`: spacing, alignment, overlap, clipping, overflow, behaviour at sizes.
- `accessibility`: when the oracle is a standard (contrast ratio, focus visibility, target size).
