# `run_event_loop`'s default mouse level: `:clicks` or `:drag`?

**Status:** open question; left over from the draggable scrollbar (`D_draggable_scrollbar`).

## Q_capture_mouse_default

The default `capture_mouse: true` is `:clicks` (mode 1000): no motion, so `handle_mouse_drag` never
fires and a `VerticalScrollBar`'s handle doesn't move without `capture_mouse: :drag`. Track-paging
works at every level; `examples/sampler.rb` runs at `:hover`. Out of the box "the handle doesn't
move" reads as a bug, and a `List` or `TextView` with a bar is far commoner than a `Scroller`.

- **For:** mode 1002 reports only while a button is held, and the base `handle_mouse_drag` is empty
  (`VerticalScrollBar` is the only override in `lib/`), so no component can be surprised.
- **Against:** a default change, and the traffic over slow ssh is unmeasured —
  `R_mouse_reporting`'s ~84 reports/s is for `:hover` (1003), not a held button.

Graduation owes: `run_event_loop`'s `@param capture_mouse` rdoc, a `**Breaking:**` CHANGELOG line if
it flips, a measurement into `R_mouse_reporting`.

## Related

`D_draggable_scrollbar`, `D_mouse`, `R_mouse_reporting`.
