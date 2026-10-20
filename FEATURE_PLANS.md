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

## 13. Shapes (plan, for confirmation, 2026-10-20)

### What Saber does today

- **Recognising:** the shape pen (live preview) and hold to shape (any pen) use the $1 recogniser
  (`one_dollar_unistroke_recognizer`) for line, rectangle, circle, triangle and star.
- **Saved as real shapes:** only `RectangleStroke` (axis-aligned) and `CircleStroke`
  (`shape: 'rect'` / `'circle'` in the note). Lines, triangles, stars, and any shape with dashes,
  dots or tape are saved as ordinary strokes through their points, so they can't be edited as
  shapes afterwards.
- **No ellipses, rotated rectangles, other polygons or arrows.** A rotated rectangle or stretched
  circle turns into an ordinary stroke (`SelectionTransform`).
- **Old versions:** a note with an unknown `shape` value logs it and loads the stroke from its
  points (`Stroke.fromJson`, since 2023). So a new shape that also saves its outline points still
  opens as a plain outline in the Flathub/Play Store Saber.

### Elsewhere

- **GoodNotes:** a Shapes tool (draw and pause → refined; keep the pen down to adjust it), with
  circles, ellipses, rectangles, triangles, polygons, lines and newer arrows. Fill colour (a
  transparent version of the colour) is set in the tool. Shapes are edited with the lasso
  (resize/rotate box). Most-requested on its feedback board: editing a shape's points, reliable
  regular polygons (hexagons for chemistry), and outline-only vs filled.
- **Notability:** hold to snap; tap a shape's point to drag it (triangles, polygons); curves are
  drawn with three points and adjusted; *Stroke and Fill* in the style menu.
- **OneNote:** a gallery of shapes to place (lines, arrows, rectangle, ellipse, triangle,
  parallelogram, coordinate axes) plus *Ink to shape*; placed shapes have point handles.
- **Xournal++ (desktop):** drawing tools for rectangle, ellipse, arrow, double arrow, coordinate
  system and spline, plus a recogniser.
- **Common pattern:** two ways in (draw rough → recognised, or pick a shape and drag it out), and
  one way to edit (select → box handles for the whole shape, point handles for its corners).

### Plan

**A. One editable shape type.** A new stroke type holding the shape's definition, which every
other part (drawing, recognising, placing, editing) shares:
- `kind`: line, arrow, double arrow, polyline (open), polygon (closed: triangle, rectangle, any
  n-gon), ellipse (centre, two radii, rotation; a circle is an ellipse with equal radii).
- Anchor points (corners / line ends; for an ellipse its centre and axis ends), the pen's colour,
  size, line style, and an optional fill colour.
- Saved as `shape: 'shape'` with its anchors **and** its outline points (`p`), so old versions show
  the outline (without fill). The existing `rect`/`circle` still load as now and become the new
  type when edited.
- Dashes, dots and tape work on all of it (drawn along the outline, as now), and stay shapes.

**B. Better recognising** (shape pen and hold to shape):
- Replace the $1 guess for straight-sided shapes with corner finding: simplify the stroke to its
  corners; a closed stroke with n corners is an n-gon, an open one a polyline; an open stroke with
  a short "V" at one end is an arrow.
- Ellipse fit for round closed strokes (circle when the radii are close).
- **Tidy up (snapping):** angles near 0/90/45° (and 15° steps, like the ruler) snap; a
  nearly-regular polygon becomes regular; a nearly-square rectangle a square; nearly-equal radii a
  circle. One setting to turn tidying off.
- Like GoodNotes: after the shape appears, keep the pen down and move it to resize the shape
  before lifting.

**C. Placing shapes.** *Shapes* in the *Insert* group opens a row of samples: line, arrow, double
arrow, rectangle, ellipse, triangle, polygon (n chosen in the row, 3–12), coordinate axes. Pick one,
then drag on the page: from corner to corner (or along the line). It uses the current pen's colour,
size and line style; holding Shift (desktop) or a second finger keeps proportions (square, circle,
regular polygon, 15° lines). It stays in that shape until you pick another tool.

**D. Editing shapes.** Selecting a single shape (lasso, box, or tapping it with the select tool)
shows, besides the existing box (move, resize, rotate), a handle on each anchor:
- Drag a corner / line end to move it; snaps to 15° angles, to other anchors and to the ruler's
  edge. Ellipse: its axis handles change each radius.
- A handle in the middle of each side adds a corner there (polygon) or bends the line (curve via
  that point, like Notability; for later, see the questions).
- One undo step per drag, like the other selection actions.
- Rotating or stretching a shape keeps it a shape (it no longer turns into an ordinary stroke).

**E. Fill.** Closed shapes can be filled (exports include it). Replaced by the *Fill* tool, see
*Decided* below.

### Order and effort

1. **A + D** (L): the shape type, anchor handles, saving with the outline fallback. Recognised
   rectangles and circles become editable right away.
2. **B** (M): corner finding, ellipses, arrows, tidying.
3. **C** (M): the *Shapes* row in Insert and drag-to-place.
4. **E** (S).

Tests: every kind saved and loaded, loaded as points by the old code path, edited through the real
editor; recognising on sample strokes (clean, sloppy, sloppy-but-not-a-shape); handles at phone
and desktop sizes.

### Decided (2026-10-20)

- **Order:** A + D first, then B, then C, then E.
- **Curves in the first version:** bending a side through its middle handle.
- **Shapes row:** the proposed samples plus more (e.g. parallelogram, star), and easy to extend:
  each sample is one entry in a list (see 13a), so adding a shape later is one entry.
- **Fill is a tool:** a *Fill* (bucket) tool next to the pens, using the normal colour bar (and
  the eyedropper, once there is one), instead of an option on the shape. First version: tap a
  closed shape to fill it. Filling any area closed by strokes (section 11) can extend the same
  tool later.
- **Hold to shape on the normal pens** gets the new shapes too.

### 13a. Detailed design of the first step: editable shapes (A + D, for confirmation)

**The shape (data):**
- `ShapeStroke`, a stroke defined by **anchors**: a list of points, each a *corner* or *smooth*.
  A side between two corners is straight; next to a smooth anchor it curves through the anchors
  (a smooth curve through the points, like Notability's curves).
- `closed` (polygon) or open (line, polyline, curve), and an **arrow head** at the start and/or
  end (open shapes only). So an arrow is a line with a head, and a curved arrow is free.
- `fill`: none or a colour (set by the Fill tool, step E).
- Ellipses are their own kind (`EllipseStroke`: centre, two radii, rotation), as an ellipse isn't
  exact as a curve through points. A circle is an ellipse with equal radii.
- Constant width (like today's shapes), colour, size, line style (dashes/dots along the outline),
  tape.
- **In the note:** `shape: 'path'` or `'ellipse'` with the anchors, smooth flags, closed, heads
  and fill, **plus the outline points** (`p`), which old Saber versions draw as a plain stroke.
  Existing `rect`/`circle` load as now and become a `ShapeStroke`/`EllipseStroke` when edited.
- **Shape samples** (for step C, and the hook for adding shapes): a list of entries, each with a
  name, an icon and a function from the dragged-out box to the anchors (e.g. parallelogram: four
  corners sheared by a quarter of the width). Recognising (B) produces the same shapes.

**From step 1 on, recognised shapes are `ShapeStroke`s:** lines, rectangles (including rotated
ones), triangles, stars, and dashed/dotted/taped shapes, which are ordinary strokes today. Circles
become `EllipseStroke`s.

**Editing (select a single shape):**
- The box with its handles stays (move, resize, rotate). Rotating or stretching keeps it a shape:
  the anchors (or the ellipse's centre, radii, rotation) are transformed.
- **Anchor handles:** a round handle on each anchor (ellipse: on its four axis ends). Drag one to
  move it; it snaps to 15° from its neighbours, onto other anchors and onto the ruler's edge
  (when the ruler is on). An ellipse's axis handle changes that radius.
- **Middle handles:** a smaller handle in the middle of each side. Dragging it adds a *smooth*
  anchor there, which bends that side into a curve.
- **Tapping an anchor** opens a small bar beside it with labelled buttons: *Corner* / *Smooth*
  (toggles), *Delete point* (not offered when it would leave fewer than 2, or 3 for a closed shape).
- When several things are selected, only the box shows (as now).
- Handles keep their size on screen and are big enough for a finger, like the box's. When anchors
  are too close together on screen, the middle handles are hidden first.
- One undo step per drag or button, like the other selection actions.

**Not in this step:** recognising new shapes (B), the *Shapes* row (C), the Fill tool (E).

**Connectors (wanted, later):** two shapes sharing a point, so moving one drags the other's end
along. Prepared for: anchors already snap onto other shapes' anchors on the page. Still needed:
strokes have no lasting ids in a note, so an anchor can't name another shape's anchor yet; that
needs an id per shape stroke (saved, kept by copies and undo), an `attachedTo` on `ShapeAnchor`,
and moving attached anchors along whenever a shape changes (move, transform, reshape, erase).

### 13b. Built (2026-10-20, step 1)

- **One shape model, no new stroke class:** a `Stroke` has an optional `shape`
  (`components/canvas/stroke_shape.dart`: `PathShape` with anchors, closed, arrow heads;
  `EllipseShape` with centre and two perpendicular semi-axes). `setShape` puts the stroke's points
  along the shape (about a stroke width apart, so the outline keeps an even width), so the eraser,
  lasso, line styles, tape, exports and older Saber versions work unchanged. Changing the points
  (e.g. the area eraser cutting it) makes it an ordinary stroke.
- **Saved** as `shape: 'path'` (`sa` anchors, `ss` smooth indices, `sc` closed, `sh` heads) or
  `'ellipse'` (`se`), plus the points. Old `rect`/`circle` load as before and become shapes when
  transformed or reshaped.
- **Recognised shapes are shapes now:** lines (also auto-straightened ones), rectangles, circles
  (ellipses), triangles, stars, also dashed/dotted/taped. Rotated or stretched, they stay shapes.
- **Editing:** `data/editor/shape_handles.dart` (handles, hit testing, snapping onto anchors on
  the page, then the ruler, then 15° lines from neighbours and their crossing); wired into the
  selection in `editor.dart` (`_SelectionChange.reshape`, `_reshapeSelection`, `_tapAnchor`).
  Tapping an anchor opens a menu (*Smooth*/*Corner*, *Delete point*). A drag that reshapes isn't
  also a tap, and taps on anchors don't count as double taps (double-tap to erase).
- **Changed on the way:** middle handles hide when a side is under two finger widths on screen.
- **After testing on the tablet:** tapping a stroke or image with a selection tool selects it (the
  nearest within a finger's reach; `Select.selectAt`), tapping nothing unselects, tapping inside
  the selection keeps it; tape still opens/closes on tap. A handle only starts moving once the pen
  has moved as far as a tap may (`kTouchSlop`), so a stylus tap on a corner opens its menu instead
  of nudging it; and a handle moves with the pen wherever it was grabbed (no jump).
- **Second round:** the corner menu stayed blocked after a reshape when the next tap didn't start
  a drawing gesture (a finger with finger drawing off); fixed, tested for mouse, stylus and finger
  (`test/shape_anchor_tap_test.dart`). Box selection works like CAD programs: dragged left to
  right it selects what's completely inside (solid outline), right to left everything it touches
  (dashed outline); the lasso is unchanged (70% inside).
- **Tests:** `test/stroke_shape_test.dart`, `test/shape_editing_test.dart` (through the editor),
  updated `hold_to_shape_test.dart` and `selection_transform_test.dart`.

**Tests:** save and load each kind; old notes with `rect`/`circle`; loading a new shape through the
old code path (as points); dragging each handle type through the real editor (corner, middle,
ellipse axis, snapping); the anchor bar; undo/redo; phone and desktop sizes; many anchors.

### 13c. Built (2026-10-20): placing shapes (C)

- *Insert → Shapes* picks `ShapePlacer` (a `Pen` borrowing the last pen's colour, size, line style
  and opacity) and opens a row: each `ShapeSample` drawn as itself (line, arrow, double arrow,
  rectangle, ellipse, triangle, parallelogram, polygon, star, axes), corners for polygon and star
  (3–12), then the pen's size, line style and opacity. Last shape and corners are remembered.
- Drag from corner to corner (along a line for lines); Shift keeps proportions (square, circle,
  regular polygon, lines at 15°). A tap places nothing. One undo step per shape.
- The placer isn't saved as the last tool (its id is the shape pen's), so notes open with the pen.
- Not done: a second finger for proportions on touch screens (only Shift).
- Tests: `test/shape_placer_test.dart`.
- **Later (your requests, 2026-10-20):** move the shape pen into this row as an "auto-detect"
  option (out of the pen tab); axes with tick marks/labels, other axis types and similar maths
  features (plan first).

## Order

1. ~~Opacity, scribble to erase~~ (built)
2. ~~Lasso actions~~ (built)
3. ~~Zoom window, side by side~~ (built)
4. ~~Tape, double tap to erase~~ (built, fixed after feedback)
5. ~~Toolbar clean-up (section 10)~~ (built: *Tools*, fullscreen stays one tap)
6. ~~Choosing PDF pages (section 12)~~ (built)
7. Research for section 11 (shapes done: section 13; the other categories next)
8. Shapes (section 13): ~~step 1 (13a)~~ built (13b); ~~C (placing)~~ built (13c); next E (fill),
   then B (recognising)
