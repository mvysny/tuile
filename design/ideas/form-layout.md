# `FormLayout` v2 and v3 — left captions, multiple columns

**Status:** v1 shipped (`Component::FormLayout`: a column of `FormItem`s, captions above, `rows:`
per child, no `spacing`, no scrolling, overflow clipped). Its choices are `D_form_layout`, usage its
rdoc and book ch7, Vaadin's behaviour `R_form_items`. This note is only the staging v1 deferred and
re-argues none of it.

## v2 — `spacing`, and captions to the left

- **`spacing:` = extra rows on top of an item's three, default 0** — same look as today's gap, named
  for what it is instead of sharing cells with the message row.
- **Optional left captions.** A captionless child still has no caption cell, so `required: true`
  without a caption keeps raising.
- **It may close v1's caption-liveness edge**: a left column must measure captions, so it may need
  the caption notice v1 declined (`D_form_layout`).

`Q_caption_width` — widest caption capped, a fixed `caption_width:`, or a percentage? Whichever,
the container measures *its own* strings and assigns the rect, as `Select` measures its item labels
(`D_select`; `D_box_layouts`' "`align:` is legal only because the cross extent is caller-supplied").
It looks like the banned bottom-up channel and isn't.

## v3 — multiple columns

- **Fixed `columns:` first.** Auto is just a rule computing `columns` from the assigned width in
  `relayout` — additive later. It reflows *what sits beside what* on resize (Tab order unchanged), so
  opt-in, not default.
- **Equal column widths, not configurable** — that is what makes row breaks unnecessary
  (`D_form_layout`).
- **Colspan** (a `TextArea` across both) rides the per-child map `rows:` already uses.
- **Row-major fill**, as Vaadin's: `children`, add, Tab and reading order agree.
- **Row height = max over the row's items** — resolves a captionless item beside a captioned one.

v2 and v3 are in tension by design: Vaadin doesn't recommend side captions with multiple columns
(`R_form_items`).

## Not here

- Helper text and a required-marker legend → `design/ideas/new-components.md`, infra item 2.
- Scrolling → wrap the form in a `Component::Scroller` (`D_scroller`); never smuggle it in here.

## Related

`D_form_layout`, `D_form_item`, `D_caption_ownership`, `R_form_items`, `D_select`, `D_box_layouts`,
`D_scroller`, `design/ideas/new-components.md`.
