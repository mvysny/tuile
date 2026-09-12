# Per-component back buffers + a z-order compositor

**Status:** deferred, not worth doing yet. Graduated out of `Buffer`'s
rdoc (it was speculative design musing, not caller contract — see the
doc-kinds rules in AGENTS.md). Parked here so the thinking isn't lost.

## The idea

Today there is one global {Tuile::Buffer}: every component paints into
the same grid via `set_line` / `set_char` / `fill`, and {Tuile::Screen}
flushes its minimal diff to the terminal.

Components already paint through that drawing surface *without knowing*
whether it's the one global buffer or a private one — the indirection is
deliberate. So per-component back buffers plus a z-order compositor could
drop in **without touching component code**: give each component its own
`Buffer`, let it paint into that, and have a compositor blend the
per-component buffers in stacking order into the frame the terminal sees.

## Why it's not worth doing yet

The current single-buffer diff already captures most of the win a
compositor would give:

- The flush drops unchanged cells from the wire, so an unchanged region
  costs nothing on the terminal side regardless of how many components
  overlap it.
- An occluded component that didn't change is never repainted at all —
  invalidation gates it out before `repaint` runs.

So a compositor would only save **residual `repaint` CPU**: the cost of a
component re-rendering its content into a buffer, when that content then
turns out to be occluded or unchanged after compositing.

## The one regime where it pays off

High repeat-rate scroll — a held arrow key or a spun mouse wheel — over a
**large** component on a **large** screen, where re-rendering the
component's content on every repeat is the dominant cost. A per-component
buffer would let an unchanged-but-scrolled component be re-composited
(cheap) instead of re-rendered (expensive) each repeat.

Until Tuile has a real workload in that regime, the extra machinery
(per-component buffer allocation, a compositor pass, dirty propagation
across buffer layers) buys nothing over what the single-buffer diff
already delivers.

## If we revisit

- The component-facing drawing API (`set_line` / `set_char` / `fill`)
  stays the same — that's the whole point of the existing indirection.
- What changes is *who owns the buffer* and the addition of a
  composite-into-frame step between `repaint` and `Buffer#flush`.
- Measure first: prove the residual-`repaint`-CPU regime is real and
  material before adding a layer.
