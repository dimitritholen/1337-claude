# Report format

The report is one file, `findings.md`, in the run folder. Use this template exactly, so reports from different runs can be compared and triaged the same way.

## Enumerations

**Severity**
- `blocker`: a core journey cannot be completed, data is lost or corrupted, or the app crashes or hangs.
- `major`: a feature works wrongly or is unreachable from where users need it; a workaround exists but most users will not find it; a surface is unusable in a supported mode, theme or size.
- `minor`: wrong but with an obvious workaround, or a noticeable inconsistency that makes the product feel unfinished.
- `polish`: small visual or copy issues a careful user or designer will notice.

**Type**
- `function`: the product does the wrong thing, or nothing.
- `interaction`: the right thing is hard to reach or behaves unexpectedly (focus, selection, shortcuts, menus, drag).
- `layout`: spacing, alignment, overlap, clipping, behaviour at sizes.
- `visual`: colour, contrast, type, theme, decoration, craft.
- `copy`: wrong, unclear, inconsistent or missing text.
- `accessibility`: a failure against an accessibility standard.
- `product question`: intended but questionable; a design decision for the product owner, not a defect.

**Confidence**
- `high`: reproduced reliably; the oracle is a direct claim, a standard, or product consistency shown in two screenshots.
- `medium`: reproduced; the oracle is a category convention or user expectation.
- `low`: intermittent, or the oracle rests mostly on judgement. Give the reproduction rate.

## Template

```markdown
# Exploratory test report: <app name>

- Date: <YYYY-MM-DD>
- Build / version: <as shown in the app or repo>
- Driver: <what was used; primitives missing>
- Data: <which copy, where>
- Time spent: <total; per phase>
- Run folder: <path>

## Summary

<Three to five sentences: overall state, the most important findings by id, the biggest coverage gap.>

| Severity | Count |
| --- | --- |
| blocker | |
| major | |
| minor | |
| polish | |
| product questions | |

## Findings

### F-001 <Short title naming the symptom, not the cause>

- **Surface:** <screen, panel or dialog; all surfaces if several>
- **Severity:** <blocker | major | minor | polish>
- **Type:** <function | interaction | layout | visual | copy | accessibility | product question>
- **Start state:** <exact state to begin from: data copy, mode, theme, window size, what is open and selected>
- **Steps:**
  1. <one action per step>
  2. ...
- **Expected:** <one line; what should happen, and no fix proposal>
- **Actual:** <what happens>
- **Oracle:** <HICCUPPS(F) oracle(s), with the specific claim, convention, standard or comparison>
- **Evidence:** `shots/<file>.png`, `shots/<file>.png`
- **Reproduced:** <n of n from the start state>
- **Confidence:** <high | medium | low>

(Repeat per finding. Order by severity, then by user reach. Product questions go last within their severity band, or in their own section if there are many.)

## Coverage map

### Tours

| Tour | Surfaces covered | Time | Findings | Not covered within the tour |
| --- | --- | --- | --- | --- |
| Journey | | | | |
| What can I do with this? | | | | |
| Claims | | | | |
| Consistency | | | | |
| Back-and-forth | | | | |
| Interruption | | | | |
| Data | | | | |
| Theme | | | | |
| Resize and device | | | | |
| Keyboard-only | | | | |

### Expectations

<Counts from expectations.md: verified, failed (with finding ids), not covered.>

### Modes

| Surface | <theme / mode / size 1> | <2> | <3> |
| --- | --- | --- | --- |
| | covered / not covered | | |

### SFDIPOT

| Dimension | Covered by | Gaps |
| --- | --- | --- |
| Structure | | |
| Function | | |
| Data | | |
| Interfaces | | |
| Platform | | |
| Operations | | |
| Time | | |

### Not covered and why

- <area>: <reason: time box, missing driver primitive, external side effect, credentials needed, out of scope>

## Session notes

<Observations that did not qualify as findings: unreproduced oddities, low-signal hunches, suggested follow-up charters.>
```

## Worked finding (generic)

```markdown
### F-004 Context menu on a board card lacks rename and duplicate offered in the list view

- **Surface:** board view, item cards
- **Severity:** major
- **Type:** interaction
- **Start state:** fresh data copy with 3 items; light theme; window 1440x900; board view open, nothing selected
- **Steps:**
  1. Right-click the first item card.
  2. Observe the menu.
  3. Switch to list view, right-click the same item.
- **Expected:** the same item actions are reachable from the card as from the list row.
- **Actual:** the card menu shows only "Open" and "Delete"; the list row menu shows "Open", "Rename", "Duplicate", "Move", "Delete". The inspector on the board view has no rename or duplicate either.
- **Oracle:** Product consistency (same object type, two surfaces); Purpose (renaming is a core task on the board).
- **Evidence:** `shots/whatcan-012-board-card-menu.png`, `shots/whatcan-013-list-row-menu.png`
- **Reproduced:** 3 of 3 from the start state
- **Confidence:** high
```

## Writing rules

- Titles name the symptom a user sees, not a guessed cause.
- One action per step; the steps must work for someone who has never seen the app.
- Expected is one line. No fix proposals, no code guesses.
- Every finding has at least one screenshot path that exists in the run folder.
- One root symptom on several surfaces is one finding with all surfaces listed.
