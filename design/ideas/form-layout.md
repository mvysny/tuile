# `FormLayout` v2 and v3: left captions, and multiple columns

**v1 shipped 2026-09-19** — {Tuile::Component::FormLayout}, a column of {Tuile::Component::FormItem}s
with captions above, `rows:` in a per-child placement map, `constrain` / `remove` / `field_for`, no
`spacing`, no scrolling, overflow clipped. Its settled choices and the roads not taken are
`D_form_layout`; the usage is the class's rdoc and book ch7. **Read those first, and nothing here
re-argues them.** `R_form_items` has the verified Vaadin behaviour both lean on.

What is left is the staging v1 deferred.

## v2 — configurable `spacing`, and captions to the left

- **`spacing` is *extra* rows on top of the item's three, default 0.** Visually identical to today's
  1-row gap, but named for what it is instead of competing with the message row for the same cells.
- **Captions optionally to the left**, which is where the caption-column measurement question lands.

**Still open — the caption column's width.** Widest caption, capped; a fixed `caption_width:`; a
percentage. This is the caller-side measuring pass v1 exists to avoid, and `D_select` is the model
for doing it without reopening bottom-up sizing: the *container's own* strings measured by the
container, the same move `Select` makes when it measures its item labels and assigns the rect
(`D_box_layouts`' "`align:` is legal only because the cross extent is caller-supplied"). It looks
like the banned channel and isn't.

It may also close the caption-liveness edge `D_form_layout` carries: a left-caption column has to
measure captions, so it may want the caption notice v1 declined. A captionless child has no caption
cell in this shape either, so `required: true` without a caption still raises.

## v3 — multiple columns

- **Fixed `columns:` first.** An automatic count is only a rule computing `columns` from the
  layout's own assigned width in `relayout`; it is strictly additive and breaks nothing when it lands.
  Worth knowing before building it: auto reflows the *grid* on resize — Tab order is unchanged, but
  what sits beside what is not — so it wants to be opt-in rather than the default.
- **Every column the same width, not configurable.** That is what makes row breaks unnecessary
  (`D_form_layout`).
- **Colspan** — a `TextArea` across both columns — rides the per-child map `rows:` already uses.
- **Fill is row-major**, as Vaadin's is, so `children` order, add order, Tab order and reading order
  all agree and the index-is-contract rule holds.
- **Row height is the max over the items sharing that row**, as in any grid — which is where a
  captionless item sharing a row with a captioned one gets resolved.

Vaadin's docs do not recommend side captions together with multiple columns (`R_form_items`), so v2
and v3 are in tension by design.

## Not here

**Helper text** and **a legend explaining the required marker** are the rest of the same seam and
live with it, in `design/ideas/new-components.md` infra item 2. **Scrolling** is
{Tuile::Component::Scroller} around the form (`D_scroller`) and must not be smuggled in here.

## Related

`D_form_layout` (v1, and what it refused), `D_form_item`, `D_caption_ownership`, `R_form_items`
(what Vaadin's form layout does), `D_select` (caller-side measurement), `D_box_layouts` (the
per-child map), `design/ideas/new-components.md` (infra item 2), `D_scroller`.
