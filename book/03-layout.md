<!--
Written against the target layout design in ideas/simpler-layouting.md,
which is unimplemented as of this writing. Reconcile with the shipped API
(and drop this note) once the layout slices land — see book/README.md.
-->

# 3. Layout: the parent sets the size

In chapter 1 every component gained a `rect` — its absolute position
and size on the screen. In chapter 2 we saw that a component is
responsible for painting every cell of that `rect` and nothing outside
it. This chapter answers the question those two left open: **who decides
what a component's `rect` is?**

The answer is a single rule, and the rest of the chapter is about why
that one rule is enough:

> A component's parent assigns its `rect`. Layout is top-down. A
> component is as big as told to be - it never asks how big it wants to be.

If you have come from a desktop or web toolkit, this will feel
almost aggressively simple. There is no `preferred_size`, no
`min`/`max`, no "shrink to fit," no constraint solver, no reflow
engine. A parent computes rectangles for its children in plain Ruby and
hands them down. That's the whole model. The surprising part is not that
it's small — it's that on a terminal, nothing larger is warranted. The
bulk of this chapter makes that case, because understanding *why* the
simple model is correct is what lets you stop reaching for the machinery
you may be used to.

## The rule, concretely

Every container positions its children by computing their rectangles
from its own. A two-pane split is arithmetic:

```ruby
left.rect  = Tuile::Rect.new(rect.left, rect.top, rect.width / 2, rect.height)
right.rect = Tuile::Rect.new(rect.left + rect.width / 2, rect.top,
                             rect.width - rect.width / 2, rect.height)
```

Notice there is no negotiation. `left` does not announce a desired
width that the parent then reconciles against `right`'s desired width.
The parent simply *decides*, and the two children fill exactly the
rectangles they are given. If new content arrives that is too tall for
its pane, the pane scrolls or clips — it does not push back on the
parent to grow.

This is already how Tuile's tiled UI works today: `ScreenPane` sizes
your content and the status bar; every real layout you write positions
its children the same way. The chapter's job is to convince you that
this is a feature, then show you the few pieces of vocabulary that make
it comfortable.

## Why a character grid changes everything

It's worth being precise about *why* desktop and web layout are complex,
because the reason turns out not to apply to a terminal at all.

Toolkits like Swing, JavaFX, and CSS are complex because they must be
**resolution-independent**. They target a continuous, unknown output:
pixels of unknown physical size (DPI varies per monitor), fractional
and hi-DPI scaling, fonts whose on-screen extent can't be known without
measuring them, and the demand that one layout reflow gracefully from a
phone to a 4K panel. Because the target is continuous and unknown *at
the time you write the layout*, you cannot name a position and have it
mean anything. Layout has to be expressed *relationally* — flex, grid,
percentages, `min`/`preferred`/`max` — and then *resolved* against the
real device when it finally renders. The constraint solver, the
intrinsic-sizing pass, the three size knobs per axis: all of it is the
**price of not knowing your output device**. (In this sense CSS is
closer to vector graphics than to what we're doing — the pixel has
already stopped being the real unit.)

A terminal owes none of that price, because the medium removes the very
uncertainty the machinery exists to absorb:

- **The canvas is a grid of character cells** — integer rows by integer
  columns. There is no sub-cell position. This is a hard property of the
  medium; it will never change.
- **Text extent is known, not measured.** N characters occupy N cells.
  The one wrinkle — wide glyphs and grapheme clusters — Tuile resolves
  *below* the layout layer, in the buffer's display-width pass, so your
  layout coordinates stay exact integers.
- **The grid's size is known** at layout time, and changes only by a
  discrete `SIGWINCH` event you re-lay-out on — a coarse resampling, not
  a continuous reflow.

So the constraint solver, the intrinsic-sizing subsystem, and the
`min`/`preferred`/`max` negotiation are all solving one problem — *"I
don't know my output device"* — that a character grid simply does not
have. `Tuile::Rect.new(10, 3, 40, 5)` means exactly one thing on every
terminal that is that size. Because the space is discrete and known, we
can settle the layout in plain integers and take the coordinates
literally.

There's a nice way to frame this. Automated, relational layout carries a
fixed overhead — system complexity, indirection, a solver whose output
you sometimes have to reverse-engineer — but it scales to huge, unknown
canvases. Explicit layout has a per-element cost (you place each thing)
but zero overhead and total control. As the canvas gets coarser and more
fixed, the per-element cost collapses (there are few elements) and the
automation stops paying for itself. A Commodore 64 artist placing
pixels by hand and a TUI author placing rectangles by hand sit on the
*same side* of that crossover; modern GUI and web sit far on the other.
"Back to the roots" is a real engineering position here, not nostalgia.

## Why simple is also *enough*

The section above argues the relational machinery is *unnecessary*.
A fair follow-up is whether the simple model is *sufficient* — or
whether you'll hit a wall and wish for flexbox. You won't, and there are
two independent reasons.

**A terminal holds few regions — by budget and by cognition.** A large
terminal is maybe 200×50, or 10,000 cells. A minimally *useful* pane is
around 20×5 — a hundred cells — so the hard ceiling is on the order of a
hundred regions, and in practice far fewer once you spend cells on
borders and breathing room. Compare a 1900×1200-pixel window with a
40×20-pixel minimum widget: it budgets thousands. That's one to two
orders of magnitude more elements. And text is high-cognitive-load *per
cell* — you read it, you don't scan it the way you scan an icon grid —
so a person can't usefully attend to many text panes at once anyway. The
cell budget caps what the grid *can* hold; cognition caps what's *worth*
holding. Both point at the same answer: three to eight dense panes, not
two hundred nested boxes.

**"Enough" is validated by the ecosystem, not hoped for.** The genuinely
complex TUIs — tmux, neovim's splits, k9s, lazygit, htop — are all
**nested rectangular splits**: a tree of regions with sizes. None of
them needs flex grow/shrink/wrap/basis or a constraint solve. The
hardest real terminal UIs already live comfortably inside "simple."

It's stronger than "simple happens to work," though. Importing a CSS-like
system would be *actively worse* on a terminal, for three concrete
reasons:

1. **It taxes the common case.** When ninety percent of your layouts are
   an obvious `left 60% | right 40%`, a constraint system makes you
   express even that in constraints — the inversion of what an
   abstraction is supposed to buy you.
2. **Solver non-determinism becomes a *visible* bug.** On a pixel canvas,
   "which constraint gave a little?" hides in sub-pixel drift nobody
   sees. On a character grid, one cell off is two percent of a small
   pane and plainly visible — so an emergent solver result is a bug you
   have to reverse-engineer. Explicit integer arithmetic is auditable;
   a solver hides exactly the rounding you *can* see.
3. **It breaks the audit-in-an-evening ceiling.** A flex engine or a
   Cassowary solver is, by itself, more code than the rest of Tuile's
   layout put together.

So staying simple isn't a compromise you're tolerating. On this medium
it is the *correct* fit, and the elaborate alternative would degrade the
common case, debuggability, and auditability all at once.

## Placing children: `Layout::Absolute`

The place you actually write layout code is a `rect=` override. The base
class for this is `Tuile::Component::Layout::Absolute`: it inherits all
the focus and key-dispatch wiring, paints nothing itself, and asks only
that you position your children whenever your own rectangle is assigned —
which happens once at startup and again on every resize.

```ruby
class SplitPane < Tuile::Component::Layout::Absolute
  def initialize
    super
    @sidebar = Tuile::Component::List.new
    @main    = Tuile::Component::Window.new("Main")
    add(@sidebar)
    add(@main)
  end

  def rect=(new_rect)
    super
    # 40 / 60 split — resolved to exact integers, remainder assigned
    # explicitly to the right pane so no column is ever lost.
    left_w = rect.width * 4 / 10
    @sidebar.rect = Tuile::Rect.new(rect.left, rect.top, left_w, rect.height)
    @main.rect    = Tuile::Rect.new(rect.left + left_w, rect.top,
                                    rect.width - left_w, rect.height)
  end
end
```

Two things to note. First, a proportional split *does* use a ratio — but
on a character grid a ratio resolves to an exact integer (`width * 4 /
10`), and you assign the remainder explicitly rather than letting two
rounded halves fail to add up. One deterministic line, no solve.

Second, because this runs on every resize (chapter 4 explains the
mechanism), responding to a narrower terminal is just an `if` in the same
method — collapse the sidebar below some width, give the main pane
everything:

```ruby
  def rect=(new_rect)
    super
    if rect.width < 60
      @sidebar.rect = Tuile::Rect.new(0, 0, 0, 0)          # hidden
      @main.rect    = rect
    else
      left_w = rect.width * 4 / 10
      # …as above
    end
  end
```

That's the whole "responsive" story: plain Ruby, recomputed on a
discrete resize event. No breakpoint DSL, no media queries — just the
arithmetic you'd write anyway.

## Geometry: `Point`, `Size`, `Rect`

The values you compute with are three small frozen types
(`Data.define`, so they compare by structure and never mutate):

- `Tuile::Point.new(x, y)`
- `Tuile::Size.new(width, height)`
- `Tuile::Rect.new(left, top, width, height)`

`Rect` uses **half-open** edges: `rect.contains?(point)` is true when
`x >= left && x < left + width` (and likewise vertically), so the right
and bottom edges are exclusive. This is what makes adjacent rectangles
tile without overlap — a pane at `left=0, width=40` owns columns 0
through 39, and its neighbour starts cleanly at column 40. `Rect#empty?`
is true for a zero *or* negative width, which is why the "hidden"
sidebar above (`width 0`) simply paints nothing.

`Rect` also carries the helpers you reach for while placing children —
`centered` (used below to center a popup), `clamp_height`, `top_left`,
and friends. Reach for the rdoc for the full set.

## Sizing a popup: `Fraction`

There is exactly one place in Tuile where a child is sized *against its
parent* rather than by hand: a popup against the screen. A popup has no
siblings to compete with and no natural rectangle in a tiled layout, so
"half the screen, centered" is the sensible default — and expressing
that wants a ratio, not a hard-coded cell count that would be wrong on
the next terminal size.

`Fraction` is that ratio, and it is deliberately the *only* relational
primitive in the framework:

```ruby
class Fraction < Data.define(:width, :height)   # each a float in 0.0..1.0
  def resolve(reference)                         # reference: Size => Size
    Tuile::Size.new((reference.width  * width).round,
                    (reference.height * height).round)
  end
end
```

A popup's size is set with `Popup#size=`, which accepts either a
`Fraction` (resolved against the screen at layout time, so it tracks
resize) or an absolute `Size` (clamped to the screen):

```ruby
popup = Tuile::Component::Popup.new(content: some_window)
popup.size = Tuile::Fraction::HALF     # the default — half the screen, centered
popup.size = Tuile::Fraction::FULL     # fullscreen
popup.size = Tuile::Fraction.new(0.8, 0.5)          # 80% wide, half tall
popup.size = Tuile::Size.new(50, 12)                # exact, clamped to screen
```

The default is `Fraction::HALF`, resolved on every layout pass, so a
popup you never size at all is half-screen and follows the terminal as
it resizes. `Fraction::FULL` is the fullscreen shorthand.

A subtle but important point: `size=` is **authoritative, not a
preference**. The name is `size`, not `preferred_size`, on purpose.
There is no parent that might negotiate it downward — the screen simply
*applies* what you asked for (clamping an oversized absolute `Size` to
fit). Calling it a preference would invite a future "well, the parent
may override it" reading, and that's the first step back toward the
`min`/`preferred`/`max` world we just spent half a chapter declining.

Because the popup's box is fixed top-down, its **content fills the box
and handles its own overflow** — wrapping and scrolling. Use a component
that can do that: `TextView` (read-only prose) and `TextArea` (an
editor) both wrap and scroll. A `Label` only truncates, so a `Label` in
a popup shows just what fits on its lines — fine for a short message,
wrong for a paragraph.

> **Why not size the popup to its content?** It's tempting to want a
> popup that shrinks to wrap exactly around its text. Tuile deliberately
> doesn't, and not only for consistency: content-sizing is circular on
> wrapped text (the height depends on the width, which depends on the
> height) and it isn't even reliably pretty — a single long line
> collapses the popup to one row. Half-screen-and-wrap sidesteps all of
> it. When you genuinely know the right size — an autocomplete dropdown
> whose items you own — you set it yourself: `popup.size =
> Tuile::Size.new(longest_item, [items.size, 8].min)`. That's still
> caller-decides, top-down.

## The window footer: chrome vs. slot

A `Window`'s bottom border can carry one of two things, and they are
genuinely different jobs, so they are two different members.

**`footer_text=`** is *border chrome* — a styled string (a `String` is
coerced) embedded into the bottom border line, mirroring the caption on
the top line. It draws at its own width with the border's dashes filling
the remainder, clipped to the inner width. Like the caption, it embeds
with **no added padding** — it butts straight against the left corner:

```ruby
window.footer_text = "gpt-4 · 1.2k tok"
# └gpt-4 · 1.2k tok────────────────────────────────┘
```

If you want the text to breathe against the corner and the dashes, pad
it yourself — a leading and trailing space is the usual choice:

```ruby
window.footer_text = " gpt-4 · 1.2k tok "
# └ gpt-4 · 1.2k tok ──────────────────────────────┘
```

It is not a component and not focusable — it's decoration the frame
draws, keeping its own styling (only the corners and dashes take the
active-border color when the window is focused). This is the right choice
for a status readout precisely *because* it preserves the border: a
full-width label would paint its background across the whole row and
erase the bottom edge, making the window look broken.

**`footer=`** is a *widget slot* — a focusable component occupying the
full inner width of the bottom row. The canonical use is an incremental
search field attached to a list window:

```ruby
window.footer = search_field    # a TextField; always spans the inner width
window.footer = nil             # remove it, restoring the plain border
```

A component in the footer slot always fills the width — there is no
sizing policy to configure, because the window already knows its inner
width and that's the only dimension a bottom-row widget needs.

The two are mutually exclusive by precedence: if a `footer=` component
is present it occupies the bottom row and `footer_text` is hidden;
otherwise `footer_text` embeds into the border. No window needs both at
once.

## Responding to resize

You've already seen the mechanism without the plumbing: when the
terminal resizes, the framework reassigns rectangles from the root down,
and your `rect=` override recomputes its children. That's the *only*
thing you do to be resize-aware — recompute in `rect=`. Do **not**
install your own `SIGWINCH` handler; only one handler can win and the
framework owns it. Chapter 4 covers how the resize event travels through
the event queue and why it's handled there rather than off the signal.
Popups re-resolve their `Fraction` against the new screen size and
re-center automatically.

## What Tuile deliberately doesn't have

It's worth stating the omissions plainly, so you don't go looking for
them:

- **No `min`/`preferred`/`max` size, and no `content_size` a parent
  consults.** Sizing decisions live on the parent, expressed as
  arithmetic, not on the child as advertised constraints.
- **No shrink-to-fit / intrinsic sizing.** A slot is sized top-down;
  content fills or scrolls within it.
- **`Label` doesn't wrap.** It truncates long lines with an ellipsis by
  design — it's the component for one-liners. For wrapping or scrolling
  prose, reach for `TextView`.

If you ever *do* need to measure content in order to choose a size —
say, to size that autocomplete dropdown — measure it yourself in your
own code and set the size top-down. Keep measurement opt-in and
caller-side; the moment the framework starts consulting children for
sizes automatically, it's on the road back to the constraint solver.

And if you find yourself building many dynamic, user-draggable splits by
hand and wishing for a `Layout.vertical([Length(3), Fill(1), …])`
convenience — that's a known, *deliberately deferred* addition. It would
be pure sugar: a rect producer running a small greedy 1-D pass and
feeding results to the very same `rect=` setter you already use, with no
change to the foundation. Absolute-first is the base; a descriptive
split layer is an optional convenience on top, added if and when the
convenience pays for itself.
