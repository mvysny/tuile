# 2. How the screen repaints

In chapter 1 you built a tree and ran the loop, and text appeared. This
chapter is about the gap between those two — what happens between "a
component changed" and "the terminal shows it." The short version is that
components don't paint when they change, and they never write to the
terminal at all. They *invalidate*, and once per loop tick the screen
paints everything that asked to be repainted, in one flicker-free batch.

Understanding this model matters for two reasons. It's the contract every
custom component has to honor (paint your rectangle, don't touch the
wire). And it's *why* Tuile stays smooth without any of the damage-region
or clipping machinery a UI toolkit would normally need.

## Components invalidate; they never paint the terminal

When something about a component changes — its text, its focus, its size
— it does not repaint itself on the spot, and it certainly doesn't emit
escape sequences to the terminal. It calls one protected method:

```ruby
invalidate
```

That does exactly one thing: it records "this component needs to be
repainted" in a set the {Tuile::Screen} owns. Nothing is drawn yet. If
the same component is invalidated ten times before the next repaint —
because an event handler changed its text, then its color, then its size
— it's still just one entry in the set, and it repaints once.

That coalescing is the whole point of deferring. A single keystroke can
ripple through a dozen components; a naive "repaint on every change"
would draw the screen a dozen times per key, and you'd see it flicker and
tear. By separating *"I changed"* (`invalidate`, cheap, happens whenever)
from *"the screen is now redrawn"* (once per tick, batched), Tuile makes
the number of repaints independent of the number of changes.

`invalidate` is deliberately protected — you don't call it from outside a
component. You mutate a component through its public setters (`text=`,
`content=`, `rect=`, …) and *they* invalidate. And it's a no-op on a
component that isn't attached to the live tree, so mutating a component
you've stashed off-screen (say, inside a closed popup) is silent rather
than an error.

## When a component does paint, it paints into a buffer

Eventually the screen does call a component's {Tuile::Component#repaint}.
Even then, the component does not write to the terminal. It writes styled
cells into the screen's **back buffer** — a {Tuile::Buffer}, an in-memory
grid of styled cells mirroring the terminal — through three methods:

```ruby
screen.buffer.set_line(x, y, styled_string)   # a run of text
screen.buffer.set_char(x, y, grapheme, style) # one cell
screen.buffer.fill(rect, style)               # a blank region
```

That's the entire painting vocabulary. A component's `repaint` computes
what its rectangle should look like and stamps it into the buffer. No
cursor moves, no color escapes, no `print` — just cells into a grid.

Keeping the buffer between the component and the terminal is what unlocks
everything in the rest of this chapter, so it's worth saying plainly: the
buffer *is* the seam. Components produce a desired grid state; the screen
turns grid state into the minimal set of bytes on the wire. Neither side
knows about the other's job.

## The repaint pass, once per tick

The event loop (chapter 4) processes whatever arrived — a key, a click, a
resize — and each of those may invalidate some components. When the queue
runs dry, the loop fires one repaint pass. The screen walks the
invalidated set and draws it in a specific order:

1. **Tiled components first, parent before child.** The framework walks
   the tree in pre-order, which naturally visits a parent before its
   children. That order matters: a parent lays down its background (and,
   for a container with gaps between its children, re-clears them) *first*,
   so a child drawing afterward paints on top of a clean surface rather
   than fighting whatever was there before.
2. **Popups last, on top.** Any popups (chapter 7) repaint after the tiled
   layer, in stacking order, so they overdraw the content beneath them.
   There is no clipping and no "punch a hole in the content" step —
   popups simply draw over what's below. If a tiled repaint touched cells
   a popup also covers, the whole popup stack is reasserted on top so it
   stays visually in front.

Notice what's *absent*: no region tracking, no dirty-rectangle geometry,
no z-buffer, no clip stack. The order is just "tree order, then popups,"
and the correctness comes from painting in that order into a buffer that
sorts out the rest.

## Overdraw is free; the wire is minimal

The reason all that overdraw doesn't cost anything is the buffer's flush.
After every component has painted into the buffer, the screen calls
{Tuile::Buffer#flush}, which computes the **minimal diff**: it compares the
buffer to the state the terminal was left in by the previous flush and
emits escape sequences only for the cells that actually changed. An
unchanged cell is never rewritten, no matter how many components painted
over it this tick.

So "overdraw is free" is literal. A popup can repaint over the entire
content area, a parent can re-clear a region a child then fills — none of
it reaches the terminal unless the *net* result differs from what was
already on screen. You get to write dead-simple paint code (just draw
your whole rectangle, every time) and pay only for what visibly changed.

The whole diff, plus the cursor repositioning, is wrapped in one
**synchronized-output batch** (the terminal's mode-2026 escape) and
written in a single `write`. A terminal that supports synchronized output
composites the frame atomically — no partial frame is ever visible. But
here's the part that makes Tuile flicker-free *everywhere*: the
smoothness doesn't depend on that support. Because an unchanged cell is
never touched, there's nothing to flicker even on a terminal that ignores
the batch escape entirely. Synchronized output is a bonus on top of a
model that's already tear-free.

## The contract: cover your own rect, and only your rect

All of this rests on one rule every component must follow:

> A component paints every cell it's responsible for, and never a cell
> outside its `rect`.

The "never outside" half keeps siblings from corrupting each other —
there's no clipping to save you, so drawing out of bounds means drawing
on someone else's cells. The "every cell it's responsible for" half is
what keeps stale pixels from surviving: if your rectangle used to show
"Loading…" and now shows nothing, the cells that held the old text have
to be actively overwritten (with blanks), or they'd linger.

Meeting that second half is easy, because the default
{Tuile::Component#repaint} does the tedious part for you:

- A **leaf** component (no children) gets its background cleared
  automatically, so you can paint your content and trust the rest is
  blanked.
- A **container whose children exactly tile its rect** skips the clear —
  the children will cover everything anyway.
- A **container with gaps** between its children (a form with
  mixed-width fields, say) gets the background cleared *and* its children
  re-invalidated, so they repaint cleanly on top. This is what makes
  gappy layouts safe without every container writing its own
  damage-tracking pass.

The practical rule for writing a component: **call `super` in your
`repaint`** to inherit that clearing, then paint your content. The only
components that skip `super` are the few that paint every cell of their
rect themselves and don't want the redundant clear — {Tuile::Component::Window}
(its border and interior cover the whole rect) and
{Tuile::Component::List} (it paints every row explicitly). Everything else
should `super`.

You are *not* required to tile your rect with children — leaving gaps is
fine, the default handles it. You're only required to make sure that when
the dust settles, every cell you own reflects the current state, not a
previous one.

## Don't reach for repaint

One last rule, and it follows from everything above: **never call
`Screen#repaint` from inside a component.** Repaint is the loop's job,
fired once per tick after the queue drains. If you call it yourself you
break the coalescing — you force a draw mid-event, before other
components have reacted, and you may draw a half-updated frame. Just
`invalidate` (or, in practice, mutate through a setter that invalidates)
and let the loop batch it.

The one place you *will* see `Screen#repaint` called directly is in tests,
which drive the system a step at a time and need to force a paint to
assert on the buffer's contents. That's chapter 8; in application code,
invalidation is the only lever you touch.

With the repaint model in hand, the natural next question is the one this
chapter kept deferring: who decides a component's `rect` in the first
place? That's chapter 3 — layout.
