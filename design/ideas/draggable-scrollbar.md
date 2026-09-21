# A scrollbar you can drag

**Status:** stage 1 shipped 2026-09-21 — `Component::VerticalScrollBar`, with
`Scroller` holding one. **Graduated out of this note:** why a child component
rather than drag handlers on the owner, why the bar owns no scroll state, the
free-track geometry and why it differs from Ink's, and the press-relative drag
are all `D_draggable_scrollbar`; the per-symbol contract is the component's
rdoc. **Nothing here re-argues any of it.**

What is left is stage 2 — converting the other scrollers and retiring
`VerticalScrollBarInk` — and the two questions it inherits.

## Still owed: the conversion

`Component::List` and `Component::TextView` still paint their own column
through `VerticalScrollBarInk`, which is why the two geometries coexist and a
`Scroller`'s handle can sit a row off a `List`'s for the same numbers.
Converting them is not a small change:

- both concatenate the glyph onto the padded row string inside
  `paintable_row`, so the column has to come out of the row cache first;
- `List#repaint` early-returns on an empty rect, which violates "a container
  assigns every child a rect on every pass" the moment it has a child.

If either turns out not to be worth it, Ink survives as the painter for
widgets that draw their own column, and `D_draggable_scrollbar`'s "until Ink
retires" becomes "for the widgets that keep painting their own".

## Q_capture_mouse_default — should `run_event_loop` default to `:drag`?

Today it is `true` == `:clicks` (mode 1000), which reports no motion, so
`handle_mouse_drag` never fires and the new bar's drag does nothing until an
app passes `capture_mouse: :drag`. Track-paging works at every level, and
`examples/sampler.rb` already asks for `:hover`, so the feature is
demonstrable — but the out-of-the-box answer is "the handle doesn't move",
which reads as a bug.

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
