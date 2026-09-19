# Scrolling a container of arbitrary components

**Status:** seed, 2026-09-19. Spun off from `design/ideas/form-layout.md`, whose
v1 clips a form taller than its rect. **Reopens** the Tier 3 line in
`design/ideas/new-components.md` ("best kept as a documented road-not-taken") —
not to overturn it, but because a form is the first caller with a real need and
it may want much less than a general `Scroller`.

## The problem

Every scroller Tuile has scrolls its **own** content: {Tuile::Component::TextView}
and {Tuile::Component::TextArea} scroll rows of text, {Tuile::Component::List}
scrolls items it renders itself. None of them scrolls *child components*. A form
of nine fields needs 27 rows and does not fit an 80×24 terminal with a menu bar
on it.

## The two hard parts, stated precisely

**1. Measurement — and it is not the blocker it looks like.** A scroller has to
know how tall its content is, which reads like the bottom-up channel the
framework refuses (`D_declared_size`: a component never advertises how big it
wants to be). But the two escapes both already exist:

- **Caller-supplied.** `scroller.content_rows = 40` — the same move `D_select`
  and `D_box_layouts` bless, where the cross extent comes from the caller rather
  than from the child.
- **The container computes its own.** A `FormLayout` knows its item pitch and
  its item count, so its total height is *its own arithmetic over its own
  state*, never a question put to a child. A **self-scrolling `FormLayout`** is
  therefore free of the banned channel entirely.

**2. Clipping — this is the actual blocker.** Tuile has none: popups overdraw,
and the only enforcement that a component stays inside its rect is the rule
itself. Hand a child a rect taller than the viewport and it paints straight
through the viewport's bottom edge into whatever is below.

The machinery that would give real clipping is
`design/ideas/per-component-buffers.md` — parked, and correctly so; a clip
rectangle threaded through `Component#draw_text` / `#draw_char` and
`Buffer#set_*` is the cheaper half of it and has never been costed.

## The way around clipping: scroll by whole children

`Q_partial_child` — **the crux of this note.** If the scroll unit is a whole
child rather than a row, no clipping is needed at all:

- children entirely above or below the viewport get an **empty rect**, and the
  repaint drain already drops those (`D_empty_ancestor` and `Screen#repaint`'s
  filter);
- children entirely inside get their real rect and paint normally;
- **there is no third case** — a child is never half-scrolled.

A form pays almost nothing for this, and `FormItem` makes it cleaner still: the
scroll unit is one item — label, field and message together, 3 rows — so a
viewport rounds down to a whole number of items and the residue is at most two
blank rows at the bottom. There is no way to half-scroll a label away from its
field, because they are one child. A general `Scroller` over a 20-row `TextArea` pays a great deal — the
child is either wholly in or wholly out.

So the shape ladder is:

- **(a) A self-scrolling `FormLayout`** — cheapest, no new component, no
  clipping, no new vocabulary. Solves the actual caller.
- **(b) A `Scroller` with caller-supplied `content_rows` and whole-child
  granularity** — (a) generalized, still no clipping, and honest about its
  limit: one tall child cannot be scrolled *through*.
- **(c) A true viewport with per-row clipping** — the real answer, blocked on
  clipping machinery, and the one that would let a `TextArea` in a form scroll
  partially into view.

Do not build (c) to get (a).

## Things it must reuse rather than reinvent

- **The vocabulary is fixed**: `scroll_top_row` / `viewport_rows` /
  `row_in_viewport`, per the root `AGENTS.md` and `D_scroll_nomenclature`. A
  scroller that invents a third one is wrong on arrival.
- **{Tuile::VerticalScrollBar} already exists** and is driven by four widgets;
  its ink and its no-handle-when-nothing-scrolls rule are settled
  (`D_scrollbar_ink`), as is the absence of an `:auto` visibility mode.
- **Named scroll verbs** over raw arithmetic, as `D_text_view_scroll_verbs`
  chose for `TextView`.

## Keys are the interesting design question, not the geometry

`Q_scroll_keys` — a scrolling *form* must not claim PgUp/PgDn/arrows: every one
of them belongs to the focused field, and `DateField`/`TimeField` already use
PageUp/PageDown to step a value. The resolution is probably that **a form
scroller claims no keys at all** and instead **follows focus** — Tab moves focus,
the container scrolls the newly focused child into view. That also satisfies
`D_mouse` for free: the wheel needs a key equivalent, and Tab already is one.

A general `Scroller` that is itself a tab stop is the other road, and it is the
one that collides with everything inside it.

`Q_focus_offscreen`: a focused child that scrolls out of view still takes keys
and still wants a cursor (`Screen#cursor_position`) at coordinates nobody can
see. Scroll-into-view on focus makes this unreachable by Tab, but not by an app
calling `screen.focused =` directly.

## Related

`design/ideas/form-layout.md` (the caller), `design/ideas/new-components.md`
(the Tier 3 line this reopens), `design/ideas/per-component-buffers.md` (the
clipping machinery, parked), `D_declared_size` (why measurement looks banned and
isn't, here), `D_empty_ancestor` (the empty rect that makes whole-child
granularity work), `D_scroll_nomenclature`, `D_scrollbar_ink`,
`D_text_view_scroll_verbs`, `D_mouse` (the wheel owes a key).
