# Per-component back buffers + a z-order compositor

**Status:** parked until measured; `paint-cull.md` goes first.

## Proposal

Each component paints into its own buffer; a compositor blends them in stacking order into the
frame before `Buffer#flush`. Component code doesn't change:

- **The seam exists:** a `repaint` writes through the `Canvas` it is handed, and
  `Canvas::Backend` (`set_text` / `set_char` / `fill`) is where cells land — "a per-component
  buffer" is one of its named targets (`D_canvas`).
- **Renders are movable:** the canvas origin puts a component's `(0, 0)` at its rect, so a render
  bakes no screen position and can be blitted elsewhere.
- **What changes:** who owns the buffer, a composite step between `repaint` and `flush`, and dirty
  propagation across layers.

## Why not yet

The single buffer already gets most of the win:

- `flush` emits only changed cells (`Cell#set` dirties on a real change), so overlap costs nothing
  on the wire.
- An unchanged component isn't repainted — invalidation gates it before `repaint`.

The saving left is **`repaint` CPU**: re-rendering content that turns out unchanged or occluded. Two
places it shows:

- **Scroll** — a held arrow or a spun wheel over a large component: re-composite a shifted render
  instead of re-rendering it. `Scroller` makes this regime real: a notch re-paints every child of
  its content. `paint-cull.md` removes the off-viewport half cheaply; measure what remains.
- **Popups** — a layer repaints whole whenever anything beneath it repaints (AGENTS.md); a cached
  popup layer would be re-composited instead.

## If revisited

- Measure first, on `examples/` and `benchmark/`, after the cull.
- `Q_layer_clip`: the clip (`D_clip`) becomes the buffer's size — does a scrolled child get a
  full-content buffer (memory) or a viewport-sized one (re-render on scroll, losing the win)?

## Related

`D_canvas`, `D_clip`, `D_relative_rect`, `R_paint_context`, `design/ideas/paint-cull.md`.
