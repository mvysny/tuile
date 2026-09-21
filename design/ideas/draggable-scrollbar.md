# A scrollbar you can drag

**Status:** stage 1 shipped 2026-09-21 — `Component::VerticalScrollBar`, with
`Scroller` holding one. `Component::List` converted 2026-09-21.
**Graduated out of this note:** why a child component rather than drag
handlers on the owner, why the bar owns no scroll state, the free-track
geometry and why it differs from Ink's, and the press-relative drag are all
`D_draggable_scrollbar`; the per-symbol contract is the component's rdoc.
**Nothing here re-argues any of it.**

What is left is `Component::TextView`, retiring `VerticalScrollBarInk`, and
the two questions below.

## Still owed: TextView

`TextView` still paints its own column through `VerticalScrollBarInk`, which
is why the two geometries coexist and a `Scroller`'s handle can sit a row off
a `TextView`'s for the same numbers. Ink cannot retire until it converts.

What the `List` conversion found, for whoever does `TextView`:

- **The row cache was never in the way.** Both widgets append the glyph in
  `paintable_row`, *downstream* of the memoized `padded_row`, and the cached
  row is already padded to a `content_width` that excludes the bar's column.
  So the paint change is deleting the append and the `VerticalScrollBarInk.new`
  beside it; the width reservation does not move.
- **`repaint` must gain `invalidate_children`.** Both skip `super` to avoid
  the auto-clear, which also skips the cascade — so the bar paints once and
  then goes stale under an ancestor's clear. Specs that paint the widget alone
  do not catch it (`D_repaint_cascade`).
- **Every input to the bar's numbers needs `invalidate_layout`**, not just
  `invalidate`, once `relayout` pushes them: the scroll setter, the content
  setter, the visibility setter and any internal path that writes the scroll
  ivar directly. `rect=` marks by itself.
- **The spec helper paints one component.** `PaintOne#repaint` does not
  descend, so every glyph assertion has to move to `screen.repaint` over a
  mounted widget — `scroller_spec`'s painting context is the pattern.
- **Turn the bar on in `component_contract_spec`'s catalog.** With the default
  visibility the bar's rect never changes, `places_children?` answers false,
  and every container check skips the one child the widget has.

`TextView`'s reserve is two columns with the sub-width-3 drop
(`D_scrollbar_reserve`), so its arithmetic is not `List`'s.

## Q_capture_mouse_default — should `run_event_loop` default to `:drag`?

Today it is `true` == `:clicks` (mode 1000), which reports no motion, so
`handle_mouse_drag` never fires and the new bar's drag does nothing until an
app passes `capture_mouse: :drag`. Track-paging works at every level, and
`examples/sampler.rb` already asks for `:hover`, so the feature is
demonstrable — but the out-of-the-box answer is "the handle doesn't move",
which reads as a bug. The `List` conversion raises the stakes: a list with a
visible bar is a far commoner sight than a `Scroller`.

For: mode 1002 adds reports only while a button is held, and
`handle_mouse_drag`'s base body is empty, so no existing component can be
surprised. Against: it is a default change, and nobody has measured the
traffic on a slow ssh link — `R_mouse_reporting`'s ~84 reports a second is the
number to weigh, and it was measured for `:hover`, not for a held button.

## Q_ink_glyph_home — where do `handle_char` / `track_char` end up?

They stayed on `VerticalScrollBarInk` through stage 1, so the app-facing knob
has already been renamed once and will move again when Ink retires. The
candidates are the component (the class that survives) or a neutral holder
both read. Deciding it early buys nothing; deciding it *with* the retirement
costs one `**Breaking:**` line either way.
