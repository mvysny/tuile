# Scrolling a container of arbitrary components

**Status:** designing, 2026-09-20 (seeded 2026-09-19). Spun off from
`design/ideas/form-layout.md`, whose v1 clips a form taller than its rect.
**Reopens** the Tier 3 line in `design/ideas/new-components.md` ("best kept as a
documented road-not-taken"), and **unparks half of**
`design/ideas/per-component-buffers.md`.

The seed's central proposal — *scroll by whole children so no clipping is
needed* — is **withdrawn** (see "Why whole-child scrolling is out"). What
replaces it is bigger and better: a **`Canvas` seam** between a component and
the back buffer, with clipping as its first implementation.

## The problem

Every scroller Tuile has scrolls its **own** content: {Tuile::Component::TextView}
and {Tuile::Component::TextArea} scroll rows of text, {Tuile::Component::List}
scrolls items it renders itself. None of them scrolls *child components*. A form
of nine fields needs 27 rows and does not fit an 80×24 terminal with a menu bar
on it.

**Not** the same problem as a long list: a `List` of 10,000 items holds no child
components and renders lazily (`D_list_items`). A `Scroller` costs one component
per child, and virtualization — *don't even build the off-screen children* — is
explicitly out of scope. If you have 10,000 rows you want a `List`.

## Why whole-child scrolling is out

The seed's `Q_partial_child` proposed that the scroll unit be a whole child:
children wholly above or below get an empty rect, children wholly inside get a
real one, and there is no third case. Three counts kill it:

1. **The mouse wheel makes it visibly wrong.** With children of uneven height —
   which is the entire point of a container of arbitrary components — one wheel
   notch jumps 1 row here and 12 rows there. No toolkit surveyed scrolls a
   heterogeneous container this way; the ones that scroll by whole units
   (`RecyclerView`, Tuile's own `List`) do it over *homogeneous items*, which is
   a different widget.
2. **It cannot express the case that matters most.** A focused child *taller
   than the viewport* has to be shown partially — there is no other option — so
   partial painting is required even if scrolling were whole-child everywhere
   else.
3. **It buys less than it looks.** It avoids clipping only for children; the
   content container itself still overflows (see the background-clear trap
   below).

## What Tab wants, precisely

Tab scrolling and wheel scrolling want *different* things, and the difference is
not granularity — it is **which edge is allowed to be ragged**:

- **The wheel** moves by rows. Both edges may cut a child in half.
- **Tab** must leave the **newly focused child fully visible**; the child at the
  *other* end of the viewport may be chopped in half, and routinely will be.

That is exactly Swing's `scrollRectToVisible` semantics — *scroll the minimum
distance that makes this rect fully visible* — and every toolkit with a viewport
has the same verb under a different name. So Tab is **not** a second scroll
granularity; it is one scroll-into-view request expressed as a rect, satisfied
by a row-granular scroller. One mechanism serves both.

Corollary the seed got right and which is free in Tuile: **a scrolled-out child
is still a tab stop.** Nothing needs to pretend anything — `D_empty_ancestor`
settled that *geometry cannot express hiding*: `tab_stop?` does not consult
geometry, `Screen#focused=` refuses only a *hidden* target, and a child scrolled
out of view is neither hidden nor detached. It keeps its rect (a real one, just
outside the viewport), keeps its keys, and Tab reaches it. All the scroller has
to do is answer the focus change by scrolling.

## Clipping is now mandatory, and here is the exact failure

The invariant *a component must not draw outside its `rect`* has been enough so
far for one reason that has never been written down: **until now, a component's
rect has always been fully visible.** Widgets honour it by hand — horizontally
with `StyledString#ellipsize` / `#slice` (`Button`, `Checkbox`, `Label`,
`Tabs`, `List`), vertically with a loop bound of `rect.height`. Both are correct
*and both are useless here*, because a scroller is the first parent that hands
out a rect it will not show in full. The child is right to paint all 40 of its
rows; the parent must cut.

The sharpest form is not even a widget's text — it is the framework's own
clearing. Put a `Layout::Vertical` of 40 rows in a 5-row viewport at screen row
10, scroll to the bottom, and the box's rect is `(0, -25, 40, 40)`. Its default
`repaint` calls `canvas.fill(local_rect)`; {Tuile::Buffer#fill} clamps to the
buffer, so it blanks **rows 0–14** — the menu bar and everything else above the
viewport. There is no version of this that works without a clip.

Two things Tuile already has make the clip cheap:

- **Exactly one drawing choke point.** {Tuile::Canvas}'s three methods are the
  only place in `lib/` that reaches a {Tuile::Canvas::Backend}, and a widget has
  no other surface to name. Whatever they delegate to, every widget follows,
  with no widget edited.
- **Tuile already clips — at one rectangle.** `Buffer#in_bounds?` silently drops
  an out-of-bounds write and `set_text` breaks at the right edge; negative
  coordinates already work. The terminal edge *is* a clip rect, hard-coded and
  unnamed. This work is that one rectangle made into n.

## The `Canvas` seam — **built, 2026-09-20**

The seam below shipped ahead of this component, as pure plumbing: a final,
frozen {Tuile::Canvas} carrying the background and an **origin** over a
{Tuile::Canvas::Backend} ({Tuile::Buffer} is one), `Screen#canvas_for`, and a
required canvas parameter on `Component#repaint`. Everything in this section
about *delivery* and *coordinates* is now settled and lives in `D_canvas` and
`D_relative_rect`; what is left for the scroller is a `clip` field on the canvas
and the two consumers below — and note the clip is now a *field*, not a second
backend, so no `Canvas::Clipped` is coming.

Two things that change for this note. A scrolled child's rect already carries a
negative `top` **inside its scroller**, which is the natural spelling now rather
than a screen coordinate that happens to be negative; and its canvas origin is
negative to match, so `Buffer` drops the rows above the viewport for free. What
a clip still has to do is the *sides* and the rows a partial write straddles.

A **`Canvas` is what a component paints onto.** Three methods — the three the
component layer actually uses:

```ruby
canvas.set_text(x, y, styled)     # a StyledString in the component's own coordinates
canvas.set_char(x, y, grapheme, style)
canvas.fill(rect, style)
```

### `Q_clip_trim` — what does a clip cost on the paint path?

Dropping a fully-outside write is a rect test; a *partial* `set_text` has to be
cut to the intersection in columns, which is `StyledString#slice` —
column-accurate and already built (`D_ambiguous_width`), but real per-write work
that the pass-through to {Tuile::Buffer} never did. Measure it against
`benchmark/` before this component leans on it.

{Tuile::Buffer} already implements all three, so **the backend on the common
path is the buffer itself** — no new class, no wrapper. The clip is a `Rect`
field on the final {Tuile::Canvas}, intersected before the backend is called.
That is the whole v1.

### Who computes the canvas — settled, in `D_canvas`

The canvas is **passed to `Component#repaint`**, and **computed by the screen**,
which is not a contradiction: `Screen#repaint` drains the invalidation set flat
and a component never paints its children, so there is no parent frame to hand
one down from the way Swing and Android do. The Screen therefore derives each
component's canvas by walking *up* from it — Turbo Vision's model, where
`TView::writeBuf` intersects clip rects along the owner chain — and then passes
the result in. `D_canvas` carries the argument; what is left here is the
declaration a container makes:

- `Component#clip_rect` → `Rect | nil`, default `nil`, meaning *I impose no clip
  on my descendants*. Exactly parallel to `extent`: `extent` says how much of my
  rect **I** paint, `clip_rect` says how much of it **my descendants** may.
- The resolved value is the intersection up the parent chain — parallel to
  `effective_bg_color`, resolved at paint time and never cached, for the same
  reason (an ancestor can scroll between two frames).

### Translation — **settled, 2026-09-20**

This note used to decline translation and argue it was the load-bearing
decision. It was overtaken: 0.17.0 made every `rect` parent-relative and gave
the canvas an origin (`D_relative_rect`). The three objections raised here were
each answered by building the conversion once, in the framework, rather than
per caller:

- **The mouse.** `Mouse::Router`'s descent already held the running offset, so
  it converts as it walks and hands each component the event in its own
  coordinates — the `convertPoint` this note feared is the walk itself, not an
  extra pass.
- **`ListDropdown#anchor_to`.** It takes screen coordinates and the driver says
  so: `absolute_extent_rect`. One named call at three sites.
- **`Screen#cursor_position`.** It converts the focused component's answer, so
  a widget reports a column and a row.

What survives for the scroller is better than what it asked for. A child
scrolled above the viewport gets a rect with a negative `top` *inside the
scroller* — the natural spelling now — its canvas origin goes negative to
match, and `Buffer` drops those writes for free. The clip is still needed for
the sides and for a partial row, which is all `Q_clip_trim` above has to cost.

### How the Scroller supplies its children's canvas

Not by handing one over: **the Scroller never calls `child.repaint`.** `Screen#repaint`
drains the invalidation set flat, so when a wheel notch invalidates one field
three levels down, the Screen calls that field's `repaint` directly and no
ancestor is on the stack. The container therefore *answers* rather than hands:

```ruby
# Component — default: my children paint on what I paint on
def canvas_for_child(child, canvas) = canvas

# Scroller
def canvas_for_child(child, canvas) = canvas.clipped(viewport_rect)
```

and `Screen#canvas_for(c)` folds that down the ancestor chain, root canvas
first, memoized per drain pass (one canvas per distinct clip chain, not per
component). Per-*child* rather than per-container because the asker varies:
a `TabSheet` clips only its pane, and a container that one day gives each child
its own origin needs the child in hand.

`Q_canvas_for_child` — **deferred until this component is built**, deliberately.
The shape above is a sketch with no caller, and the one question it cannot
answer yet is whether the fold is worth memoizing at all, or whether a clip is
cheap enough to recompute per draw call the way `effective_bg_color` already is.

### The three consumers, and only one is new work

`extent` is consulted in three places (clear, hit-test, anchor). The clip is
consulted in three too:

1. **Painting** — the three draw helpers. New.
2. **The cursor** — `Screen#cursor_sequence` hides the cursor when
   `cursor_position` falls outside the focused component's effective clip. One
   line, beside the existing `nil` branch. This retires the seed's
   `Q_focus_offscreen` outright: a caret that is scrolled away is *hidden*, not
   parked at a coordinate nobody can see.
3. **The mouse** — nothing. Already correct, as above.

And one bonus: `Screen#repaint`'s drain filter already drops a component with an
empty rect anywhere on its ancestor chain; a component whose rect misses its
effective clip entirely is the same kind of "no place on the screen" and belongs
in the same `delete_if`. That is the cheap half of virtualization — the
off-screen children of a scroller are built and laid out, but never painted.

### The fiddly part

A **wide cluster straddling the clip edge**. `Buffer#put_char` already handles
this at the terminal's right edge (a wide glyph that would overflow the last
column becomes a blank, and `blank_left_partner` / `blank_right_partner` handle
a half-overwritten pair), so the policy exists; the canvas has to apply it at an
arbitrary column instead. `set_text` must slice through
`StyledString#slice` rather than dropping whole spans, per the width invariants
— never `each_char`.

### What the seam buys beyond the scroller

This is the argument for building `Canvas` as an object rather than threading a
bare `Rect` through the three helpers (which would also work, and is ~40 lines
less):

- **Per-component buffers stay droppable.** `design/ideas/per-component-buffers.md`
  parks the idea and names the one regime where it pays: *high repeat-rate
  scroll over a large component*. A `Scroller` is the first thing Tuile has ever
  had that lives in that regime — a wheel notch re-lays-out and re-paints every
  child. If it turns out slow, the fix is a `Canvas::Buffered`, and the seam is
  what makes that a new class rather than a refactor of every widget.
- **Painting without a `Screen`.** Tuile already guarantees a tree assembles
  with no screen (`attached?`, `Component#locale`). Painting is the last thing
  that reaches `Screen.instance`, and a canvas passed to a spec closes it: render
  one widget into a 20×3 buffer and assert `region_text`, with no fake screen.
- **A compositor, if it ever comes.** Same seam, z-ordered targets.

Not on that list, though it was: a `Canvas::Strict` raising on a write outside
the component's rect. `component_contract_spec` already paints every catalogued
component over a sentinel buffer and sweeps the cells outside its rect, so the
invariant is guarded and a second mechanism is not worth a class (`D_canvas`).

## Open questions

`Q_clip_universal` — **opt-in or does every component clip its children?**
Universal clipping is what Qt and the browser do, and it would mechanically
enforce the invariant above. Declined for v1 on two counts: it turns a loud bug
(a widget visibly corrupting its neighbour) into a silent one (a widget
truncated for no visible reason), which is the `overflow: visible` argument; and
it pays a chain walk on every draw call in every app, for a guarantee
`Canvas::Strict` gives the test suite for free. Keep `clip_rect` opt-in and let
`D_extent`'s principle hold — forgetting to declare one degrades to today's
behaviour.

`Q_content_rows` — **who says how tall the content is?** `D_declared_size`'s
re-grow rule allows measurement back only as *an optional, read-only,
caller-side query*. So: **`scroller.content_rows = 40`, app-supplied**, with the
natural supplier being the content's own arithmetic over its own state — a
`FormLayout` knows its item pitch and count; a `Layout::Vertical` of all-`Fixed`
children can sum its constraints without asking a child anything
(`Percent`/`Expand` are meaningless unbounded, so such a box cannot answer).
Spelled `declared_rows` if it lands on `Box`, per the re-grow rule's naming.
What is genuinely unresolved is **staleness**: add a field to the form and
`content_rows` is wrong until someone re-sets it. Re-reading it in the
scroller's own `rect=` covers a resize and nothing else. A push from the box is
the banned channel. Two TUI precedents pick the same explicit route —
Terminal.Gui v2's `SetContentSize()` and ratatui's `tui-scrollview`, both of
which also have no measurement pass — so the honest v1 is app-supplied, and this
is the first thing to revisit.

`Q_scroll_keys` — **resolved, keep the seed's answer.** A scrolling form claims
no keys: PgUp/PgDn/arrows all belong to the focused field, and
`DateField`/`TimeField` already step values with PageUp/PageDown. It follows
focus instead, and the wheel's `D_mouse` key equivalent is Tab, which already
exists. The remaining case is a scroller whose content has **no** tab stop (a
long `Label`, a read-only panel): nothing can scroll it. The web platform hit
exactly this and shipped the heuristic — Chrome 127 made scrollers
keyboard-focusable *only when they have no focusable children* — but a
heuristic that changes a component's `tab_stop?` when a child is added is worse
in a framework this explicit. Proposal: an explicit `focusable:` knob, default
off, which when set makes the scroller a tab stop that claims the arrows and
PgUp/PgDn for itself.

`Q_scroll_to_visible` — **how does the scroller learn about the focus change?**
Every toolkit surveyed makes this a **request that bubbles up from the child**,
never a pull by the container: Swing `scrollRectToVisible`, Android
`requestChildRectangleOnScreen`, brick's `visible` combinator, FTXUI's `focus`
decorator, CSS `scrollIntoView()`. So: `Component#scroll_to_visible(rect =
extent_rect)`, walking up to the nearest ancestor answering a `clip_rect`,
scrolling the minimum distance, then asking *its* parent (brick merges nested
requests with the inner taking preference — same rule). The rect parameter earns
itself immediately: a `TextArea` wants its *caret row* visible, not its whole
40-row self, which is brick's `visibleRegion` and prompt_toolkit's
`ScrollOffsets`.

Who calls it on a focus change, then — two candidates:

- **`Screen#focused=`**, one line at the sole firing site, between
  `handle_focus` and `on_focus_changed`, so an app's status-line listener sees
  settled geometry. Matches four toolkits. Costs: `Screen` learns the word
  "scroll", and the documented firing order grows a step.
- **The `Scroller` appends to `Screen#on_focus_changed`**, synced from
  `attached?` per the hook-owned-resource rule. Keeps every trace of scrolling
  inside the component, which is the COP answer — and it is *newly possible*:
  before 0.16.0 a component taking that slot would have silently replaced the
  app's own listener. It is also the weaker of the two, since it only ever
  answers focus, where the bubbling verb answers "show me this" from anywhere.

Recommendation: build `scroll_to_visible` regardless (it is the API an app
wants), and wire the focus case from `focused=`.

`Q_scroller_name` — `Scroller`, `ScrollPane` (Swing, "pane" collides with
`ScreenPane`), `Viewport` (brick, prompt_toolkit — but the viewport is only the
hole; the component also owns the bar and the content) or `Frame` (FTXUI —
collides with window chrome). `Scroller` unless someone objects.

## The component, concretely

`Component::Scroller`, one content child via `HasContent`, vertical only in v1
(`Canvas` clips both axes, so horizontal is later and cheap; `left_column` stays
private per the nomenclature rules).

- `clip_rect` = its rect, minus the scrollbar column and the blank reserve
  column beside it (`D_scrollbar_reserve`, the same shape `TextView` uses).
- `content_rows=`, `scroll_top_row` / `viewport_rows` / `row_in_viewport` — the
  fixed vocabulary, no third one (`D_scroll_nomenclature`).
- Named verbs over arithmetic, as `D_text_view_scroll_verbs` chose:
  `scroll_half_page_up` / `#scroll_half_page_down`, plus the internal
  `move_scroll_top_row_by`.
- `rect=` assigns the content child `Rect.new(left, top - scroll_top_row,
  inner_width, content_rows)` — the one place a Tuile rect goes negative.
- `handle_mouse_scroll?` claims the wheel; no key bindings (`Q_scroll_keys`).
- {Tuile::VerticalScrollBar} painted in the reserved column, with its settled
  no-handle-when-nothing-scrolls rule (`D_scrollbar_ink`).
- A hidden child costs no rows, so whoever computes `content_rows` skips hidden
  children — consistent with `D_visibility` (a hidden child is not a member of
  the sequence and does not even keep its `spacing` gap).

**`FormLayout` needs to know nothing about any of this**, which retires the
seed's shape ladder: option (a), a self-scrolling `FormLayout`, was only ever
attractive because clipping looked expensive. Scrolling is a container you
compose, not a capability every container grows. Terminal.Gui v2 went the other
way — `View` itself gained `Viewport` + `SetContentSize`, so *every* view
scrolls — and it is the one survey entry whose choice this project's first
principle rules out.

## What other toolkits actually do

Sources at the bottom; on graduation the verified rows become one `R_` entry in
`design/research.md`, each claim carrying a provenance marker. Two axes:
**how a component is prevented from painting outside its box**, and **how a
viewport scrolls**.

| Toolkit | Paint surface | Clipping | Granularity | Scroll-into-view |
|---|---|---|---|---|
| Swing | `Graphics` created per child by the parent, translated + clipped | mandatory, parent-applied | pixels; `Scrollable` names unit/block increments | `scrollRectToVisible` bubbles to `JViewport` |
| Android | `Canvas`; `ViewGroup.drawChild` does save/clip/translate/restore | mandatory, `clipChildren` can be turned off | pixels | `requestChildRectangleOnScreen` bubbles |
| Flutter | `Canvas` via `PaintingContext`, offset passed to `paint` | opt-in — a clip is a *layer* you push; `Clip.none` is the cheap default | pixels, slivers | `Scrollable.ensureVisible` |
| Qt | widget makes its own `QPainter` | by the backing store | pixels | `QScrollArea.ensureWidgetVisible` |
| Web/CSS | — | `overflow` clips all descendants; overlays escape only via a portal / top layer | pixels | `scrollIntoView()`, and focus scrolls implicitly |
| Turbo Vision | no object: `TView::writeBuf` / `writeLine` | mandatory, **resolved at write time** by walking the owner chain (`getClipRect`); `writeBuf` clamps to the view width | cells | — |
| ncurses | a `WINDOW`; `newpad` is a window bigger than the screen | by construction (per-window buffer) | `prefresh` origin | manual |
| notcurses | an `ncplane`, any size, may sit wholly off-screen; total z-order, compositor | by construction | plane move | manual |
| Textual | widget yields `Strip`s; the **compositor crops** them to the visible region | framework-applied after the fact; the widget is unaware | cells, smooth; `virtual_size` is a real bottom-up measurement | `scroll_to_widget` / `scroll_visible` |
| Terminal.Gui v2 | driver with a clip `Region` | mandatory | cells | scrolling moved *into* the base `View` (`Viewport` + `SetContentSize`) |
| brick | widget renders a vty `Image`; `viewport` crops it | framework-applied | rows/cols | the `visible` / `visibleRegion` combinators — the child *requests*, inner wins |
| prompt_toolkit | `UIControl` renders a `Screen`; the `Window` copies a `WritePosition` | framework-applied | rows, with `ScrollOffsets` margins | cursor-driven |
| ratatui | a sub-`Rect` of the frame's `Buffer` | **none** — the buffer *is* the clip, you cannot address outside it; oversized content is the caller's problem (`tui-scrollview` renders into an oversized buffer and copies the window out) | cells | — |
| FTXUI | `Element` into a `Screen` box | `frame` / `yframe` create a clipped scrollable area | cells | the `focus` / `select` decorator marks what the frame keeps visible |
| **Tuile today** | the one global `Buffer` via three helpers | only at the terminal edge | — | — |

What the survey settles:

- **Everyone clips.** The only libraries that do not are immediate-mode ones
  whose widget is handed an area-sized buffer and *physically cannot* address
  outside it. Tuile is retained-mode with absolute coordinates into a shared
  buffer, so it has neither the guard rail nor the excuse.
- **Two families.** *Clip at write* (Swing, Android, Turbo Vision, Terminal.Gui)
  versus *render then crop* (Textual, brick, ncurses pads, notcurses,
  tui-scrollview). The second family is per-component buffers under another
  name: it costs an allocation per component per frame and buys caching. Clip at
  write is the cheap one and is what Tuile should do first — with the `Canvas`
  seam keeping the other family reachable.
- **A canvas object is not what makes clipping possible.** Turbo Vision proves a
  TUI can clip with no graphics object at all, by resolving up the owner chain
  at write time. That is precisely the model Tuile's flat, drain-driven repaint
  forces, which is a pleasant coincidence rather than an argument against the
  object: keep the object for the *target*, resolve it like Turbo Vision.
- **Scroll-into-view is always a bubbling request, never a container poll.**
  Five of five. Adopt the verb.
- **Nobody scrolls a heterogeneous container by whole children.** Confirms the
  withdrawal above.
- **Measurement splits by whether the toolkit has a layout pass.** Swing
  (`Scrollable`) and Textual (`virtual_size`) ask the content; Terminal.Gui v2
  and tui-scrollview, which have no measurement pass, are told. Tuile is in the
  second group by construction.

## Staging

0. ~~**The `Canvas` seam.**~~ Done — see `D_canvas`.
1. **`clip_rect`, no new component.** The clip field on {Tuile::Canvas},
   resolution up the parent chain, the cursor guard, the drain filter term. Behaviour-neutral until
   something declares a `clip_rect`; testable on its own with a deliberately
   overflowing widget inside a clipping parent.
2. **`Component#scroll_to_visible(rect)`** plus the call from `Screen#focused=`.
3. **`Component::Scroller`.** Four registrations owed: rdoc, CHANGELOG, the
   README components table, `component_contract_spec`'s catalog.
4. **`FormLayout`** — unchanged, composed inside a `Scroller`.

## Risks

- **Per-draw chain walk.** Already mitigated: `Screen#canvas_for` resolves
  `effective_bg_color` once per component per pass rather than once per draw.
- **Scroll cost.** One wheel notch re-lays-out and re-paints every child of the
  content box. Fine for a nine-field form, unknown for a hundred. This is the
  regime per-component buffers were parked for; measure before unparking.
- **Silent truncation.** A clip hides a layout bug that used to be loud. This is
  why `Q_clip_universal` says opt-in, and why `Canvas::Strict` exists.
- **Nested clips** intersect up the chain — cheap, but the first thing to write
  a spec for.
- **Popups escape the clip for free**, being `ScreenPane` children, which is the
  bug CSS needed portals to fix. Verify it rather than assume it.

## Related

`design/ideas/form-layout.md` (the caller), `design/ideas/new-components.md`
(the Tier 3 line this reopens), `design/ideas/per-component-buffers.md` (the
other family, now with a first real caller), `D_relative_rect` (the translation
this note used to decline), `D_declared_size` (the re-grow rule
`content_rows` obeys), `D_empty_ancestor` (geometry cannot express hiding — why
Tab reaches a scrolled-out child), `D_visibility`, `D_extent` (the parallel
`clip_rect` is drawn on), `D_repaint_cascade`, `D_mouse_dispatch` (the
descending rect gate that makes the mouse need no change), `D_scroll_nomenclature`,
`D_scrollbar_ink`, `D_scrollbar_reserve`, `D_text_view_scroll_verbs`, `D_mouse`
(the wheel owes a key), `D_list_items` (the other answer to "a lot of rows"),
`D_no_native_backend` (why the paint seam stays ours).

**Sources for the survey** (to be re-verified with markers on graduation):
Textual's [Strip](https://textual.textualize.io/api/strip/) and
[widget guide](https://textual.textualize.io/guide/widgets/);
[Terminal.Gui v2 what's new](https://gui-cs.github.io/Terminal.Gui/docs/newinv2)
and its [clip Region issue](https://github.com/gui-cs/Terminal.Gui/issues/3413);
[brick's guide](https://github.com/jtdaugherty/brick/blob/master/docs/guide.rst)
and [Brick.Widgets.Core](https://hackage.haskell.org/package/brick/docs/Brick-Widgets-Core.html);
[tui-scrollview](https://github.com/ratatui/tui-widgets/tree/main/tui-scrollview)
and ratatui's [scrollable-widgets RFC](https://github.com/ratatui/ratatui/discussions/1924);
[FTXUI frame.cpp](https://arthursonzogni.com/FTXUI/doc/frame_8cpp_source.html);
[notcurses_plane(3)](https://notcurses.com/notcurses_plane.3.html);
Turbo Vision's [view.h](https://fossies.org/linux/rhtvision/include/tv/view.h) and
[2.0 Programming Guide](https://archive.org/stream/bitsavers_borlandTurrogrammingGuide1992_25707423/Turbo_Vision_Version_2.0_Programming_Guide_1992_djvu.txt);
Chrome's [keyboard focusable scrollers](https://developer.chrome.com/blog/keyboard-focusable-scrollers).
