# `FormLayout` v3 — multiple columns

**Status:** v1 shipped (`Component::FormLayout`: a column of `FormItem`s, captions above, `rows:`
per child, no scrolling, overflow clipped), and v2 with it — `spacing:`, and left captions in a
column the form sizes. Their choices are `D_form_layout`, usage the rdoc and book ch7, the prior
art `R_form_items`. This note is only the staging still deferred and re-argues none of it.

## v3 — multiple columns

- **Fixed `columns:` first.** Auto is just a rule computing `columns` from the assigned width in
  `relayout` — additive later. It reflows *what sits beside what* on resize (Tab order unchanged), so
  opt-in, not default.
- **Equal column widths, not configurable** — that is what makes row breaks unnecessary
  (`D_form_layout`).
- **Colspan** (a `TextArea` across both) rides the `Layout#constraints` entry `rows:` already uses.
- **Row-major fill**: `children`, add, Tab and reading order agree.
- **Row height = max over the row's items** — resolves a captionless item beside a captioned one.
- **The narrow-terminal fallback is argued here too** — side labels elsewhere drop back above the
  field when the layout gets too narrow (`R_form_items`), the same width-driven switch as an auto
  `columns`. v2 shipped without it; its caption yields to keep the field's minimum instead.

v3 is in tension with left captions by design: side captions with multiple columns are a documented
bad pairing (`R_form_items`), so a left-caption column per form column is a question, not a given.

## Not here

- Helper text and a required-marker legend → `design/ideas/new-components.md`, infra item 2.
- Scrolling → wrap the form in a `Component::Scroller` (`D_scroller`); never smuggle it in here.

## Related

`D_form_layout`, `D_form_item`, `R_form_items`, `D_scroller`, `design/ideas/new-components.md`.
