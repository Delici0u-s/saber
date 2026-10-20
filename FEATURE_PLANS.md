# Feature plans (draft, 2026-10-19)

Plans for the features picked from the comparison with other note apps. Nothing here is built
yet, except search (see 1). Each plan says how other apps do it, how it would fit into Saber, the
effort (S = an hour or two, M = a session, L = several sessions) and what needs deciding.

> [!NOTE]
> Answer the questions marked **Q** (inline is fine) and I'll refine the plan before building.

## 1. Search (S, built before the "plan first" request)

**Built:** a search button in the app bar of *Recent notes* and *Browse*. It lists every note and
filters by name and folder as you type (every word must match, any order, ignoring case); tapping
a result opens the note. Code: `lib/components/home/search_notes_button.dart`, test
`test/search_notes_test.dart`.

**Not included:** searching inside notes (typed text). Every note would have to be opened and
decoded on each search, which is slow with many notes. It would need a search index kept up to
date on save and sync (M).

- **Decided:** keep it.

## 2. PDF text tools

**Decided:** dropped.

## 3. More lasso actions (M)

**Elsewhere (GoodNotes, Notability, OneNote):** a selection gets a bounding box with handles:
drag a corner to resize, a rotate handle to rotate, plus menu actions.

**Saber today:** a selection can be moved (also to another page), duplicated, deleted and
recoloured (tap a colour while selected).

**Plan:**
- A box around the selection with corner handles (resize, keeping proportions, or freely with
  side handles) and a rotate handle above it, which snaps to 15° like the ruler.
- Strokes are transformed point by point; line widths scale with the resize (like the others).
  Rectangles and circles turn into normal strokes when rotated or stretched unevenly. Images
  resize with the box (rotating images isn't supported by Saber's image format, so a selection
  with images only resizes).
- A *thickness* slider in the selection bar to change the stroke size of everything selected.
- One undo step per action (new history item types, like the existing move).

- **Decided:** corner handles resize proportionally, side handles freely. Thickness is a slider;
  pressure-sensitive strokes keep their varying width (the slider scales the stroke's size, which
  their pressure widths are relative to).

### 3a. Detailed design (for confirmation)

- **Box:** after selecting (lasso or box), a dashed rectangle around everything selected, with
  8 handles: 4 corners (resize keeping proportions), 4 side midpoints (stretch one way), and a
  rotate handle on a short stem above the top. Handles stay the same size on screen at any zoom
  and are big enough for a finger. Dragging inside the box still moves it (also to another page,
  as now).
- **While dragging a handle:** the selection follows live; rotation shows the angle and catches on
  15° like the ruler; resizing from a corner keeps the opposite corner fixed.
- **Strokes:** points are transformed, and each stroke's width scales with the resize (by the
  average of the two scale factors), so pressure-sensitive strokes keep their varying width.
  Rectangles and circles stay shapes when resized proportionally; stretched or rotated, they turn
  into normal strokes along their outline (like the dashed shapes from hold to shape).
- **Images:** move and resize with the box. Saber's images can't be rotated, so the rotate handle
  is hidden when the selection contains an image.
- **Thickness:** a slider in the selection bar that scales every selected stroke's width relative
  to its own (e.g. ×0.5 to ×3, shown as "×1.5"), so strokes of different sizes keep their
  differences and pressure widths stay proportional. Setting one absolute size for all would flatten
  them; say if you'd rather have that.
- **Undo:** one step per handle drag or slider change: the strokes are swapped for their
  transformed copies (the way the area eraser already swaps strokes), so undo and redo swap back.

## 4. Zoom window (L)

**Elsewhere (GoodNotes, Noteshelf):** a panel at the bottom shows a magnified strip of the page;
a box on the page shows which part. You write big in the panel and it appears small on the page.
When the writing reaches the panel's right edge, the box moves on (and wraps to the next line).

**Plan:**
- A toggle in the toolbar opens the panel (about a third of the screen); the page box can be
  dragged and resized; the magnification is set by the box's size.
- The panel shows the same page with a transform, and pen input in the panel is mapped to page
  coordinates and fed into the normal drawing code, so all pens, the eraser, hold to shape and line
  styles work in it.
- Buttons in the panel: move left/right, new line (box to the start of the next line, using the
  background's line height), and auto-advance near the right edge.

- **Decided (my choice, for usability):** auto-advance on by default with a toggle in the panel,
  plus the manual buttons; the ruler stays out of the panel at first.

### 4a. Detailed design (for confirmation)

- **Turning it on:** a *Zoom window* button in the toolbar (next to the ruler). It opens a panel
  along the bottom of the canvas, a third of its height by default; dragging the panel's top edge
  resizes it (remembered).
- **The box on the page:** a rectangle on the page shows what the panel magnifies. It has the
  panel's proportions; drag it to move it, drag its corner to make it bigger or smaller (smaller =
  more magnification). It starts at the top left of the page on screen, one line high.
- **Writing in the panel:** pens, pencil, highlighter and eraser work in the panel; what you write
  appears on the page, small. The panel shows the page as it is (a second, read-only view of it,
  like the export preview), including the stroke being drawn. Selecting, text and the ruler stay
  in the main view. Finger drawing, the stylus button and palm rejection follow the same settings
  as the main view.
- **Moving on:**
  - Buttons at the panel's side: back, forward (by the box's width, less a small overlap) and
    new line (back to the left margin and one line down, using the page's line height).
  - **Auto-advance** (on by default, toggle in the panel): a margin strip at the right of the panel
    (shaded); when a stroke ends in it, the box moves forward. Past the page's right edge, it goes
    to the next line.
  - The main view scrolls to keep the box on screen.
- **Not in the first version:** the ruler in the panel, selecting in the panel, and the box moving
  to the next page (it stops at the page's bottom).

## 5. Two notes (or note and PDF) side by side (M–L)

**Elsewhere:** Notability and GoodNotes split the screen into two notes; OneNote opens a second
window.

**Saber:** the editor keeps some state in static (shared) fields, e.g. the current stroke, the
selection and the shape being recognised, so two full editors side by side would get in each
other's way. Options:
- **a) Reference pane (M):** the second pane shows another note or a PDF **read-only**, scrollable
  and zoomable; you write in the main one. Covers "note and PDF" and "notes from last week next to
  today's".
- **b) Two editable notes (L):** both panes are full editors. Needs the shared state moved into
  each editor first, which touches a lot of code.
- On Android, the system's split screen already works with another app (e.g. a PDF reader next to
  Saber), just not with two Saber notes.

- **Decided:** a second note should be writable too (b), with toggles in the second pane to lock its
  position (no scrolling/zooming) and to enable writing (off = read-only reference). A PDF in the
  second pane is read-only. Needs its own detailed plan first (the shared editor state).

### 5a. Detailed design (for confirmation)

- **Opening:** *Open side by side* in the editor's menu (⋮) opens a picker with your notes and
  imported PDFs (the same list as *Browse*, plus *PDF from file…*). The second pane opens on the
  right, or at the bottom when the screen is taller than wide; the divider between them can be
  dragged (remembered).
- **The second pane's bar:** its name, *Lock position* (no scrolling or zooming in it), *Write*
  (off by default, so it starts as a reference), undo/redo while writing is on, and close.
- **One toolbar:** the main toolbar's pen, colour and size are used in both panes; you write in
  whichever pane you touch. The ruler and zoom window stay in the main pane.
- **A note in the second pane** is a second editor with its own undo history and autosave; its
  changes sync like any note. Keyboard shortcuts (undo, etc.) go to the pane last written in.
- **A PDF in the second pane** is shown with the PDF viewer Saber already uses (read-only; no
  writing on it, since a PDF isn't a note: import it first to annotate it).
- **Groundwork first** (no visible change): the stroke being drawn, the lasso/box selection, the
  shape preview and the keyboard shortcuts are shared by all editors today. They get tied to the
  editor (or page) they belong to, so two editors can't draw into each other.
- **Not in the first version:** opening the same note in both panes (refused, as two editors
  saving one file would overwrite each other), dragging strokes from one pane to the other.

## 6. Scribble to erase (S–M)

**Elsewhere (Samsung Notes, OneNote, Nebo):** scribbling back and forth over something deletes it;
the scribble itself isn't kept.

**Plan:** when a pen stroke ends, it counts as a scribble if it turns back on itself often (many
direction reversals for its size) and covers existing strokes. Then the strokes it touches are
deleted (one undo step, like the eraser) and the scribble isn't added. While the stroke is still
being drawn it looks normal; it only disappears on lifting the pen.
- A setting *Scribble to erase* (on/off), and probably how many reversals it takes.
- Risk: real shading or zig-zag drawings could be taken as scribbles. Mitigation: only when it
  covers other strokes, and only strokes it mostly covers are deleted.

- **Decided:** off by default; only strokes are erased.

## 7. Tape (optional, S–M)

**Elsewhere (GoodNotes):** draw a strip of tape over text to hide it; tap it to reveal and tap
again to hide, for learning.

**Plan:** a tape is a stroke with a flag (`tape: true` in the note), drawn as an opaque strip in a
tape colour with a subtle pattern. Tapping it (with any tool, or with a finger) toggles it between
hidden and see-through. Other Saber versions ignore the flag and show it as a thick stroke, so the
note still opens. Drawing tape: a *Tape* mode in the highlighter tab, or its own toolbar button.

- **Decided:** tape hides again when the note reopens (the revealed state isn't saved).

### 7a. Detailed design (for confirmation)

- **Drawing tape:** a *Tape* tool in the highlighter tab (next to the highlighter, like the eraser's
  two modes). Tape is drawn as a straight strip from where you start to where you lift (like a
  straight highlighter line), as wide as the highlighter's size, in a tape colour (the highlighter's
  colour, opaque, with a faint diagonal stripe so it reads as tape).
- **Hiding and revealing:** tape hides what's under it. Tapping it (with the pen, a finger or the
  mouse, whatever tool is active) makes it see-through (an outline with a light tint); tapping
  again hides it. A pen tap on tape only toggles it and doesn't leave a dot. Reopening the note
  hides all tape again.
- **Editing:** tape is erased, selected, moved, resized and undone like any stroke.
- **Exports:** PDF and image exports show tape hidden (as on paper); other Saber versions see it as
  a thick opaque stroke (it's saved as a stroke with a tape flag), so the note still opens there.

## 8. Opacity (optional, S)

**Plan:** an opacity slider in the pen tab (fountain pen, ballpoint, pencil), remembered per pen.
It sets the colour's alpha, which strokes already save, so other Saber versions show it too. The
highlighter keeps its fixed transparency. The pencil shader ignores alpha, so the pencil needs a
small shader change.

## 9. Double tap to erase (optional)

- **Decided:** double-tapping the screen switches to the eraser (and back). A setting picks which
  input does it: finger (default), pen, or both. Needs a detailed plan for what the two taps draw
  (with finger drawing on, they'd otherwise leave two dots).

### 9a. Detailed design (for confirmation)

- **Setting:** *Double-tap to switch to the eraser*: off, finger (default), pen, or both.
- **What it does:** two quick taps at the same spot switch to the eraser; two more switch back to
  the tool used before (like the stylus button, but toggling).
- **Finger, with finger drawing off (the usual case):** a finger tap draws nothing today, so the
  double tap only switches the tool.
- **Pen, or finger with finger drawing on:** each tap draws a dot. On the second tap, both dots are
  removed again (and not kept in undo), then the tool switches. Risk: two dots written quickly at
  the same spot (e.g. an umlaut at low zoom) could count as a double tap. To keep that rare, the
  second tap must land within a few pixels of the first and follow it quickly (the system's
  double-tap time).

## 10. Toolbar clean-up (plan, revised)

**Problem:** 16 buttons in one toolbar; on a phone it wraps onto three rows, and option bars only fit
by scrolling. Your feedback on the first plan: don't over-group; putting most things under ⋯ makes
everyday use slower and you have to guess where things are.

**Principles:**
1. One tap for everything used while writing.
2. Groups only for things that belong together, with names you can predict, opening in place with
   labelled buttons (icon and name), never a hidden menu.
3. Show more inline when there's room, collapse only when there isn't.
4. Choices show what they look like (samples), not just names.

**Proposal:**
- **Always one tap (the writing set):** pen, pencil, highlighter/tape, eraser, select, colour,
  undo, redo. The finger-drawing toggle stays too, but follows its existing setting
  (*Hide the finger drawing toggle*), so desktop users can hide it.
- **Insert** (+): image, text, PDF (the import now in ⋮), later shapes. Opens a row of labelled
  buttons in the place where the pen options open.
- **Helpers:** ruler, zoom window, laser pointer. These stay on while you work, so the group button
  shows a dot when one of them is on, and each shows as on inside the row. The laser pointer goes
  here because it's for presenting, not writing.
- **Out of the toolbar:**
  - Export/share moves to the app bar as a share button, where apps usually put it (next to pages
    and ⋮).
  - Fullscreen moves into ⋮ and keeps its F11 shortcut; the button to leave fullscreen stays.
- **Wide screens:** when everything fits in one row, groups are shown inline with a thin divider
  between them (no extra tap); they collapse into their group button only when space runs out,
  Helpers first, then Insert.
- **Option bars:**
  - Same order everywhere: *variant · size · style · opacity · extras*.
  - Multi-choice settings (line style, pen variant, units) become one button showing the current
    choice as a sample, opening a small menu of samples.
  - On a phone, a bar that still doesn't fit scrolls, as now.
- **Engineering:**
  - Toolbar items become data (`ToolbarItem`: icon, name for tooltip and label, shortcut, group,
    selected, enabled, action), declared in one list.
  - One layout widget measures what fits and collapses groups. Option bars get a shared section
    component.
  - Tests at phone, tablet and desktop widths: one row, no overflow, every action reachable within
    two taps.

**Questions:**
- Names: *Insert* and *Helpers*, or would *Tools* (your suggestion) read better for the second?
- Fullscreen in ⋮, or should it stay one tap?

### 10a. When groups grow (recommendation)

- **No folders inside groups:** a folder in a group is a third tap and a guess about where
  something is, the problem the clean-up just removed.
- **Split by purpose instead:** a group's row should fit a phone with names (about 3–4 items). When
  one outgrows that, split it into a new named group, e.g. Tools → *Measure* (ruler, compass,
  protractor), *Aids* (zoom window, grid snapping), *Present* (laser pointer). Every group stays
  one tap away; the toolbar already collapses groups when space runs out.
- **Later, once there are more groups:** *Customise toolbar* in the settings, to pin favourite tools
  inline, reorder groups and hide ones you never use. People use different subsets, so this scales
  better than any fixed grouping. It needs the buttons as data (`ToolbarItem`), which the groups
  are halfway to already.

## 11. Later: more tools (to research, not planned yet)

Research what kinds of tools other apps have, and what people ask for, before choosing; the
bucket is one idea of the kind meant. Categories to look through:
- **Filling and colour:** fill an area closed by strokes, or the inside of a shape; pick a colour
  from the page (eyedropper); gradients.
- **Measuring and constructing** (beyond the ruler): compass for circles and arcs, angle measuring,
  snapping to a grid, mirror/symmetry drawing.
- **Shapes and objects:** placing shapes (handoff section 6), arrows and connectors, sticky notes,
  tables or grids, stickers/elements.
- **Editing ink:** smoothing a stroke after drawing, joining or splitting strokes, converting
  handwriting to text.

## 12. Choosing pages when importing a PDF (plan, for confirmation)

- After picking a PDF (*⋮ → Import → PDF*, or opening a PDF with Saber), a dialog shows its pages as
  thumbnails in a grid, all selected; tap a page to deselect or select it.
- Above the grid: *All*, *None*, and a field for ranges like `1-3, 7`, which selects those pages.
- *Import* (showing how many pages, e.g. *Import 4 pages*) adds the selected pages in their order;
  *Cancel* imports nothing.
- A PDF with only one page skips the dialog.
- Engineering: the dialog returns the chosen page numbers; the import loop already goes page by page
  (`importPdfFromFilePath`), so it imports only those. Thumbnails come from the PDF library Saber
  uses (pdfrx), rendered small and only for pages on screen.

## Order

1. ~~Opacity, scribble to erase~~ (built)
2. ~~Lasso actions~~ (built)
3. ~~Zoom window, side by side~~ (built)
4. ~~Tape, double tap to erase~~ (built, fixed after feedback)
5. ~~Toolbar clean-up (section 10)~~ (built: *Tools*, fullscreen stays one tap)
6. ~~Choosing PDF pages (section 12)~~ (built)
7. Research for section 11
