# `FormLayout`: the column that stacks form items

**Read first, and nothing here re-argues them:** `D_caption_ownership` (a field carries no caption;
the container does), `D_has_validation` (the field stores the verdict and paints it as a red *well*;
whoever owns the cells paints the *message*), `D_form_item` (why the chrome around one field is a
wrapper component, three rows tall, with the message row doubling as the gap), and
{Tuile::Component::FormItem}'s rdoc, which owns the item's usage, geometry and message wiring.
`R_form_items` has the verified Vaadin behaviour this note leans on.

**The item shipped 2026-09-19; the layout has not.** What is left is the column that stacks items:
its per-child placement map, `spacing`, the left caption column and the multi-column grid. It owes
a decision entry, an rdoc, a book ch7 section, a README Components row, a CHANGELOG line and a
`component_contract_spec` catalog row, and it is still what infra item 2 of
`design/ideas/new-components.md` is blocked on.

The layout never touches `error_message` or a caption: the item subscribes, the item paints. Its
whole job is rectangles.

## Settled: a column of `FormItem`s and nothing else

- **`add` always wraps**, even a `Button` with no caption, so `children` stays homogeneous
  `FormItem`s. A captionless item simply does not reserve row 0. Non-uniform children is how the
  chrome-vs-app-children distinction grows back at the layout level.
- **`rows:` is a placement constraint in the layout's per-child map**, exactly as `Fixed[n]` is in a
  `Box` — never a property on the item, which measures nothing and takes the rect it is given. The
  trap is an item that knows it needs `1 + rows + 1` and a layout that asks: the deleted bottom-up
  channel under a new name.
- **No `HasLabel` mixin**, then or now — there is nothing left for it to carry.

```ruby
form.add(username, caption: "Username", required: true)
form.add(notes,    caption: "Notes", rows: 5)   # rows: defaults to 1
form.add(logging)                               # the Checkbox paints its own "[x] Enable logging"
form.add(save)                                  # no caption row at all
```

The sugar's receiver reads wrong — `add(field, caption:)` looks like it sets the *field*'s caption —
which `D_caption_ownership` accepts as the narrowest remaining objection; `add` returns the item it
built, and `FormItem.new(field, caption:)` stays available with the right receiver.

## Settled: the staging

- **v1** — vertical, one column, caption above, message/gap row below, `rows:`, `field_for(caption:)`.
  Spacing fixed at the one fused row.
- **v2** — `spacing` configurable (**extra** rows on top of the item's three, default 0 — visually
  identical to the 1-row gap, but named for what it is instead of competing with the message for the
  same cells); captions optionally to the **left**, which is where the caption-column measurement
  question lands.
- **v3** — multiple columns, every column the same width, not configurable.

**The caption goes above the field in v1** not because inline-left is wrong, but because
caption-above needs **no measurement at all**: the caption spans the form's full width, so there is
no caption-column width policy, no caller-side measuring pass, and the ellipsis essentially never
fires. It is also the shape that survives a narrow terminal, where a left caption column eats half
of it. Vaadin's docs say the same thing from the other end — side captions and multiple columns are
a pairing it does not recommend (`R_form_items`) — so v2 and v3 are in tension by design.

**A form-level status row showing the first error in full is the *app's*** to build from the same
data, not the layout's — `D_status_bar` from the other side. That is the escape hatch for the item's
one-row, ellipsized message.

### v3: colspan yes, row breaks no, fixed columns before automatic

- **Row breaks are unnecessary.** Columns are equal-width by decree, so two `FormLayout`s of the
  same width and column count produce identical column boundaries — stacking them in a `Vertical`
  already aligns. A section heading between two groups is then a component in that `Vertical`, not a
  feature of the form. (Vaadin ships an explicit `FormRow` for its auto-responsive mode, where
  column boundaries are not fixed by decree; the responsive-steps mode fills row-major without one.)
- **Colspan is necessary** — a `TextArea` across both columns — and it rides the per-child map
  `rows:` already needs.
- **Ship a fixed `columns:` first.** Automatic count is only a rule computing `columns` from the
  layout's own assigned width in `rect=`; it is strictly additive and breaks nothing when it lands.
  Worth knowing before building it: auto reflows the *grid* on resize — Tab order is unchanged, but
  what sits beside what is not — so it wants to be opt-in rather than the default.
- **Fill is row-major**, as Vaadin's is, so `children` order, add order, Tab order and reading order
  all agree and the index-is-contract rule holds.

### Three small ones, settled with the above

- **Overflow clips.** Items past the bottom get **empty** rects, never stale ones
  (`D_empty_ancestor`). A form that scrolls is a separate problem and must not be smuggled in here:
  `design/ideas/scroller.md`.
- **A child added with no `caption:` gets no caption row**, so a `Button` or a `Checkbox` costs
  `rows + 1` rather than `rows + 2`. In v3 the row height is the max over the items sharing that
  row, as any grid does.
- **`required: true` without `caption:` raises** — already the item's behaviour, and the layout
  inherits it; in v2's left-caption shape a captionless child has no caption cell either.

## Facts it rests on, so they don't get re-derived

- **A per-child attribute map is a solved shape.** `Box` keeps constraints in an identity-keyed
  per-child map that is explicitly *not* a second copy of ordering (`D_box_layouts`); a `FormLayout`
  holding `{item => {rows:, colspan:}}` copies it. Since the caption lives on the item, what is left
  in that map is placement only — exactly what `Box` keeps.
- **It owes a `handle_child_visibility_changed` override**, like `Box` — the rule for any container
  with layout arithmetic (`D_visibility`). With `FormItem` the caption row and the message row are
  *inside* the thing being hidden, so the override only has to reclaim the item's rows and its gap,
  not chase chrome.
- **Measuring captions does not reopen bottom-up sizing.** Aligning a caption column needs the
  *container's own* strings measured — caller-side arithmetic, the same move `Select` makes when it
  measures its item labels and assigns the rect (`D_select`; `D_box_layouts`' "`align:` is legal only
  because the cross extent is caller-supplied"). It looks like the banned channel and isn't.
- **Top-down forbids the layout *asking* how tall a child should be, and nothing more** — which is
  why `rows:` is caller-supplied. The rest of that argument graduated into `D_form_item`.
- **`field_for(caption:)` is convenience, not necessity.** The association is a `FormItem` in the
  tree, reachable by an ordinary walk
  (`Testing.get(Component::FormItem) { _1.caption.to_s == "Name" }`), so the method is app-facing
  sugar to be judged on its own merits — **not** text lookup by the back door: `D_component_lookup`
  bans shaping a *component* API around a locator, not a form answering a question about its own
  contents.
- **The structural notice a Binder would want is refused on the merits**, not for want of a
  mechanism: an error message is a logical fact, not a structural one; the Binder is not a Component
  and has no place on a tree channel; and Vaadin 6's `Form` / `FieldGroup` already demonstrated that
  coupling validation to form structure is an anti-pattern. Don't re-derive it.

## Still open

- **Caption geometry in v2** — a left caption column has to pick its width (widest caption, capped; a
  fixed `caption_width:`; a percentage) and that is the caller-side measuring pass v1 exists to
  avoid. `D_select` is the model for measuring without reopening bottom-up.
- **A legend explaining the required marker.** Vaadin's docs recommend an instruction text at the
  top of the form (`R_form_items`); in Tuile that row is the app's, not the layout's
  (`D_status_bar`), so the only question left is whether Tuile offers the wording.
- **Helper text**, the other half of the seam `design/ideas/new-components.md` infra item 2 names, is
  undesigned — and the item's third row is already spoken for by the message.

## Related

`D_form_item` (the wrapper this stacks), `D_caption_ownership`, `D_has_validation`, `D_bad_input`,
`R_form_items` (what Vaadin's form layout does), `design/ideas/binder.md` (the writer of
`error_message`), `design/ideas/new-components.md` (infra item 2; Tier 2 Form Layout, Custom Field),
`D_box_layouts` (the per-child attribute map; caller-supplied cross extent), `D_select`
(caller-side measurement), `D_status_bar` (no framework-reserved row), `D_empty_ancestor` (the empty
rect an overflowing item gets), `D_visibility`, `design/ideas/per-child-attribute-map.md` (the
placement map `FormLayout` would otherwise hand-roll), `design/ideas/scroller.md` (what happens past
the bottom edge), `lib/tuile/component/AGENTS.md`.
