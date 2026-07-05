# 2. How the screen repaints

**Status: stub.**

A *why-it's-shaped-this-way* chapter. Explains why components don't
paint immediately or write escape sequences, and how the deferred
invalidate/repaint model stays flicker-free without damage tracking or
clipping. Assumes the component tree from chapter 1.

Will cover:

- Components call `invalidate` (record self in the screen's invalidated
  set); they never call `screen.print`.
- The repaint pass once per event-loop tick: partition tiled vs popup,
  sort tiled by depth (parents first), overdraw popups on top in
  stacking order.
- The back buffer and `Buffer#flush`: the minimal diff — only changed
  cells reach the wire — wrapped in one synchronized-output batch.
  Why overdraw into the buffer is free, and why this is flicker-free on
  any terminal regardless of mode-2026 support.
- The "cover your own `rect`" contract: parents don't paint behind
  children; the default `repaint` clears the background and
  re-invalidates children when direct children leave gaps.
- Don't call `Screen#repaint` from a component — just `invalidate` and
  let the loop coalesce.
