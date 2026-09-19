# `FormLayout`: where the caption, the message and the required marker go

**Status:** filed 2026-09-03 as `design/ideas/caption-and-error-ownership.md`, which
asked whether a field or the container around it owns the caption and the error
state. **That question is settled, and the field half has shipped** — read
`D_caption_ownership` (a field carries no caption; the container does) and
`D_has_validation` (the field stores the verdict in
`HasValidation#error_message` and paints it as a red *well*; whoever owns the
cells paints the *message*, subscribing to `on_error_message_change`) before
this note. Nothing here re-argues either. Note in particular that an invalid
field shows **no ink at all**: it gets a slight red *well*, never the red
foreground on the glyphs that the first draft recommended.

**`FormItem` shipped 2026-09-19** — read {Tuile::Component::FormItem}'s rdoc
before this note; it owns the item's usage, geometry and the message wiring, and
nothing here re-argues them. What is left is the other half, **`FormLayout`**:
the column that stacks items, its per-child placement map, `spacing`, the left
caption column and the multi-column grid. It still owes a decision entry, an
rdoc, a book ch7 section, a README Components row and a CHANGELOG line, and it
is still what infra item 2 of `design/ideas/new-components.md` is blocked on.

## Settled: the word is `caption`, and the *field*'s own is never touched

Decided 2026-09-19, **reversing a `label:` settlement made the same day.** The
reversal is recorded rather than overwritten because the road not taken is the
interesting half; see *How `label` came and went* at the end of this section.

**The wrapper's text is a `caption`, and `FormItem` includes `HasCaption`.**

```ruby
form.add(username, caption: "Username", required: true)
form.add(logging,  caption: "Enable logging")   # Checkbox still paints "[x] Logging"
form.add(save)                                   # no caption cell at all
```

The test the house uses is **is the carrier a `Component`?**, and it has no
judgement in it:

| carrier | a `Component`? | word |
|---|---|---|
| `Window`, `Button`, `Checkbox`, **`FormItem`** | yes — it has a rect and paints in it | **caption**, and it includes `HasCaption` |
| `Tabs::Tab`, `MenuBar::Item` | no — a handle its owner mints and paints | **label** |
| `item_label` on `Select` / `ComboBox` / the groups | no — a renderer over a domain object | **label** |

A `FormItem` has a rect and owns every cell in it, so it is a caption by the
same test that makes a `Window` one — the chrome `Label` doing the painting is a
child it owns outright, which is an implementation detail and not a change of
authorship. This also promotes `D_tabs`' existing *"a `Tab` is not a component"*
from a coincidence to the whole axis.

**No connection to the *field*'s `HasCaption`, in either direction.** The
wrapper neither reads `child.caption` as a fallback nor writes it. `D_caption_ownership` chose the
axis "paints it", not "is a field", so the children that *are* `HasCaption` —
`Checkbox`, `Button` — keep painting their own text inside their own rect, and
the form's column simply stays empty for them:

```
   Username        [________________]
   Enable logging  [x] Logging
                   [ Save ]
```

The rationale, which is better than "who paints it": **the form owns a column,
the widget owns its row face, and the two must not merge.** Move a `Checkbox`'s
text into the left column and it is either duplicated there or missing from the
checkbox — and the checkbox stops being a checkbox-with-a-label, which is the
whole widget. A `Button` in a form belongs in the *right* column, with nothing
to its left; so does a checkbox. Vaadin 25.2 lands the same way, checked rather
than remembered: *"The field label must be applied on the Form Item rather than
the field itself"*, and `FormItem` is *"only intended for wrapping individual
input field components"* — a checkbox's own label is not a form-item label.

Rejected alternatives, both of which reintroduce the collision:

- *Fall back to `child.caption` when no text is given.* `HasCaption` carries no
  change notice, so a later `checkbox.caption =` leaves the column stale — the
  same "the field never invalidates those cells" that forces
  `on_error_message_change` to exist. It would have to grow an
  `on_caption_change` to be correct.
- *Let the layout write `child.caption=`.* The "two places claim authorship of
  the same text" failure `D_caption_ownership`'s *Why not* already refuses,
  arriving through a different door.

Alternatives to the *word*, ruled out on evidence rather than taste, and still
ruled out: **`title:`** is what `design/terminology.md` uses to *define* caption
("a `Window` title"), and `window.rb` names the local `title = caption.slice(…)`;
**`header:`** was refused as a caption synonym once already (`D_confirm_window`'s
*Why not*); **`prompt:`** would collide with `HasPlaceholder`, since
`combo_box.rb` already glosses the placeholder as "a prompt for the query"; and
**`legend:` / `heading:`** both name a group header, the wrong scale for one row.

### How `label` came and went

Worth keeping, because the argument was good and lost to a better one.

`label:` was chosen first, on the split *caption = text a component paints on
its own face; label = text one thing carries and another paints for it*. Under
that reading the form's cell is a label: the app makes the field, the container
paints text for it. Two things then went wrong.

**The axis stopped being operationalizable in the direction it was built for.**
`design/ideas/tab-label-rename.md` picked carried-by-one/painted-by-another
precisely because *whose face is it* "cannot be operationalized (a `Tab` has no
rect, so 'its face' is a figure of speech)". A `FormItem` **has** a rect. It is
the first carrier where the face test works, and it answers caption — so the
tie-break that justified the other axis had expired.

**And the remaining argument for `label` was load-bearing on a test locator.**
The case against `FormItem` including `HasCaption` came down to
`Testing.get(caption:)` matching `is_a?(HasCaption)` and therefore returning a
wrapper nobody can click. That is a library being shaped to suit its tests,
which is not allowed; the term was deleted instead (`D_component_lookup`,
shipped 2026-09-19), and with it the objection. A self-referential /
other-referential axis floated in the same conversation was an invention to
rescue the conclusion, and it contradicted the house test — it is not the reason
for anything and should not resurface.

What `label:` was *right* about survives intact and is the paragraph above: the
form's cell and the widget's own face are different texts and must not merge.
Two `HasCaption` components nested in one printed row is the honest model of
that, not a problem with it.

The cost now sits at the sugar call site: `form.add(checkbox, caption: "Enable
logging")` does read as though it sets the checkbox's caption. Accepted, as the
narrowest remaining objection and the only one — the explicit form
`FormItem.new(field, caption: "Username")` has the right receiver, and the sugar
returns the item it built.

Graduating this costs **no** edit to `design/terminology.md`'s `caption` row,
which was going to have to lose "label" as its informal synonym under the old
settlement and now does not. Whether the non-component carriers still rename —
`Tabs::Tab#caption`, `MenuBar::Item#caption` — is `design/ideas/tab-label-rename.md`,
whose premise this reversal knocked out; it now stands or falls on the
is-it-a-`Component` axis alone.

## What the layout has to place

Three pieces of chrome, none of which the field carries or can carry:

- **the caption** — `FormLayout#add(field, caption: "Username")`; the string lives
  on the {Tuile::Component::FormItem} wrapping the field, never on the field.
- **the message** — read off `content.error_message`, painted in
  `Theme#error_color`.
- **the required marker** — a red dot beside the caption; chrome like the
  caption, so it rides the wrapper too (below).

## Settled: `FormLayout` is a column of `FormItem`s and nothing else

Decided 2026-09-19; the item half shipped the same day, so what is left here are
the three obligations it puts on the layout.

- **`add` always wraps**, even a `Button` with no caption, so `children` stays
  homogeneous `FormItem`s. A captionless item simply does not reserve row 0.
  Non-uniform children is how the chrome-vs-app-children distinction grows back
  at the layout level.
- **`rows:` is a placement constraint in the layout's per-child map**, exactly as
  `Fixed[n]` is in a `Box` — never a property on the item, which measures nothing
  and takes the rect it is given. The trap is an item that knows it needs
  `1 + rows + 1` and a layout that asks: the deleted bottom-up channel under a
  new name.
- **`FormLayout` is a new component**, so it owes the four registrations: rdoc,
  the CHANGELOG, the README Components row, and `component_contract_spec`'s
  catalog.

**No `HasLabel` mixin**, then or now — there is nothing left for it to carry.

## Settled: the geometry, and the v1/v2/v3 staging

Decided 2026-09-19. **This replaces the inline-on-both-sides shape this note
recommended until now** — caption left, field, message right, all on one row. The
correction that killed it is under *Facts* below.

### The item is three rows, and the message row *is* the gap row

Shipped in `FormItem`; kept here for the argument, which `FormLayout`'s decision
entry inherits.

```
   Username ∙
   [________________]
   Must not be blank        ← the third row: the message when there is one…
   Password ∙
   [________________]
                            ← …and the gap when there isn't
```

The item pitch is a flat **3**, and **nothing ever reflows**. That is the whole
reason to fuse the two rows rather than reserve them separately: a form that
grows a row when a field goes invalid pushes the fields below it down *while the
user is typing into one of them*, and on a 24-row terminal that walks the
focused field off the bottom edge.

The only other no-reflow option is a fourth row per item (caption / field /
message / gap), and it costs a third of the screen — 6 items in 24 rows against
8. Not worth it. The price of the choice is that a form with several errors
tightens up exactly where it is least happy; accepted.

v2's configurable `spacing` is then **extra** rows on top of the three,
defaulting to 0 — visually identical to the 1-row gap, but named for what it is
instead of competing with the message for the same cells.

- **One row each for the caption and the message, ellipsized** — bounded by the
  row, truncated by the layout (`InfoWindow#lines=` is the model). Ellipsizing a
  validation message is a genuine loss and there is no fix under fixed geometry.
- **A form-level status row showing the first error in full is the *app's*** to
  build from the same data, not the layout's — `D_status_bar` from the other
  side: the framework reserves no row it was not asked for. That is the escape
  hatch for the truncation above.

### The caption goes above the field in v1; left is v2

Not because inline-left is wrong, but because caption-above needs **no
measurement at all**: the caption spans the form's full width, so there is no
caption-column width policy, no caller-side measuring pass, and the ellipsis
essentially never fires. It is also the shape that survives a narrow terminal,
where a left caption column eats half of it. The measurement question is real and
it lives in v2, which is exactly where deferring it belongs.

### A field declares `rows:`, in v1

`text_area.rb`, `list.rb`, `checkbox_group.rb` and `radio_group.rb` all exist,
and a form that can hold none of them is half a form. Under top-down the layout
has to be told:

```ruby
form.add(notes, caption: "Notes", rows: 5)   # default 1
```

Caller-supplied cross extent, the same move `D_box_layouts` already blesses for
`align:`. The item is then `1 + rows + 1` rows rather than 3; the message row
stays the last one.

### Staging

- **v1** — vertical, one column, caption above, message/gap row below, `rows:`,
  the required marker, `field_for(caption:)`. Spacing fixed at the one fused row.
- **v2** — `spacing` configurable (extra rows, default 0); captions optionally to
  the **left**, which is where the caption-column measurement question lands.
- **v3** — multiple columns, every column the same width, not configurable.

### v3: colspan yes, row breaks no, fixed columns before automatic

- **Row breaks are unnecessary.** Columns are equal-width by decree, so two
  `FormLayout`s of the same width and column count produce identical column
  boundaries — stacking them in a `Vertical` already aligns. A section heading
  between two groups is then a component in that `Vertical`, not a feature of
  the form.
- **Colspan is necessary** — a `TextArea` across both columns — and it is the
  per-child attribute map the caption already needs.
- **Ship a fixed `columns:` first.** Automatic count is only a rule computing
  `columns` from the layout's own assigned width in `rect=`; it is strictly
  additive and breaks nothing when it lands. Worth knowing before building it:
  auto reflows the *grid* on resize — Tab order is unchanged, but what sits
  beside what is not — so it wants to be opt-in rather than the default.
- **Fill is row-major**, as Vaadin's is, so `children` order, add order, Tab
  order and reading order all agree and the index-is-contract rule holds.

### Three small ones, settled with the above

- **Overflow clips.** Items past the bottom get **empty** rects, never stale
  ones (`D_empty_ancestor`). A form that scrolls is a separate problem and must
  not be smuggled in here: `design/ideas/scroller.md`.
- **`required: true` without `caption:` raises.** In the above-shape such a child
  has no caption row at all, so the marker has nowhere to go — and the same holds
  in v2, where a captionless child has no caption cell either. This retires
  `Q_required_without_label`.
- **A child added with no `caption:` gets no caption row**, so a `Button` or a
  `Checkbox` costs `rows + 1` rather than `rows + 2`. In v3 the row height is
  the max over the items sharing that row, as any grid does.

## Wiring the message

The message shows in cells the *field* does not invalidate, so its owner has to
be told: `FormItem` subscribes to `on_error_message_change` in `content=` and
unsubscribes from the outgoing occupant in the same call — one choke point,
because `HasContent` makes every swap go through it. That notice exists for
exactly this consumer, and `D_has_validation` records why it is plain listener
inversion.

**Two notices, one string.** The field's own report needs these cells too, and
this item is the consumer that got it a notice: `on_bad_input_change` shipped
2026-09-19 (`D_bad_input`). So the subscription above is a pair, the second one
guarded on the capability, and what is painted is `shown_message`, where the
precedence between the two channels is stated once (`D_has_validation` — bad
input wins):

```ruby
content.on_error_message_change { refresh_message }
content.on_bad_input_change { refresh_message } if content.is_a?(Component::HasBadInput)
```

Neither notice needs a settling rule here: the bad-input one already fires the
*showable* report, so a `DateField` stays silent through the nine bad prefixes of
a correct date and a `DateTimeField` relays its guilty half's words the moment
that half reddens.

**Shipped with `FormItem` on 2026-09-19**, and `FormLayout` inherits it for
free: the item subscribes, so the layout never touches `error_message` at all.

What unblocked it was `D_listeners` — the slot used to be a single
`attr_accessor`, so a `FormItem` claiming it at `content=` would silently
disable an app that had already set it. Four narrow repairs were refused in
favour of a list on *every* slot; `R_listener_multiplicity` has the survey.

Note for whoever builds the layout: the structural notice is refused *on the
merits*, not for want of a mechanism. An error message is a logical fact, not a structural
one; the Binder is not a Component and has no place on a tree channel; and
Vaadin 6's `Form` / `FieldGroup` already demonstrated that coupling validation
to form structure is an anti-pattern. Don't re-derive it.

## Facts it rests on, so they don't get re-derived

- **A per-child attribute map is a solved shape.** `Box` keeps constraints in an
  identity-keyed per-child map that is explicitly *not* a second copy of
  ordering (`D_box_layouts`); a `FormLayout` holding `{item => {rows:, colspan:}}`
  copies it. Since `FormItem` landed, the *caption* is no longer in that map — it
  is on the item — so what is left there is placement only, which is exactly what
  `Box` keeps. `Component::Slot` is the tree-native answer for a swappable region
  (`D_slots`), and `FormItem` needs none: it has one populatable child, so
  `HasContent` is direct.
- **It owes a `handle_child_visibility_changed` override**, like `Box` — it is the
  rule for any container with layout arithmetic (`D_visibility`). A conditional
  form field is *the* consumer that brought `visible=` in; with `FormItem` the
  caption row and the message row are *inside* the thing being hidden, so the
  override only has to reclaim the item's rows and its gap, not chase chrome.
- **Measuring captions does not reopen bottom-up sizing.** Aligning a caption
  column needs the *container's own* strings measured — caller-side arithmetic,
  the same move `Select` makes when it measures its item labels and assigns the rect
  (`D_select`; `D_box_layouts`' "`align:` is legal only because the cross extent
  is caller-supplied"). It looks like the banned channel and isn't.
- **`field_for(caption:)` is convenience, not necessity — and that changed with
  `FormItem`.** The original argument was that the layout held the *only* copy of
  the caption↔field association, so it owed a locator, as Karibu-Testing does
  against Vaadin 25 form items. That is no longer true: the association is a
  `FormItem` in the tree, reachable by an ordinary walk
  (`Testing.get(Component::FormItem) { _1.caption.to_s == "Name" }`). So the
  method is app-facing sugar to be judged on its own merits, and **not** a
  reintroduction of text lookup by the back door: `D_component_lookup` bans
  shaping a *component* API around a locator, not a form answering a question
  about its own contents. `Component#id` + `Tuile::Testing.get` stays the
  structural handle, unrelated and unreplaced.
- **Top-down layout is the heaviest prior — but it does *not* force both halves
  inline**, which is what this note claimed until 2026-09-19 and got wrong. The
  argument was "a field is handed one row and cannot grow a second for a caption
  or a message"; true, and beside the point, because the *field* never grows —
  the **layout** allocates three rows and hands the field the middle one.
  Nothing bottom-up happens. Top-down constrains this design far less than it
  looks; what it really forbids is the layout *asking* the field how tall it
  should be, which is why `rows:` is caller-supplied.

## Still open

- **Caption geometry in v2** — a left caption column has to pick its width
  (widest caption, capped; a fixed `caption_width:`; a percentage) and that is the
  caller-side measuring pass v1 exists to avoid. `D_select` is the model for
  measuring without reopening bottom-up.
- **The required marker's *color* — shipped reusing `Theme#error_color`, and
  that is the half still worth a second look.** The glyph question is closed:
  `FormItem` paints `∙` U+2219, which with `◦` U+25E6 measures 1 under **both**
  ambiguous-width policies where `•` `●` `·` measure 2 under ambiguous-as-wide.
  Those three would each enlarge the inventory `D_ambiguous_width`'s bet rests
  on; `∙` costs nothing, so the ASCII-default rule never fired and
  `FormItem.required_marker` is the knob if it ever does.

  The color was reused rather than tokenized because a new `Theme` member is
  breaking — every member is validated `is_a?(Color)` and a hand-rolled
  `Theme.new` has to pass all of them. But **a required field is not (yet)
  invalid**, and Vaadin keeps the two apart as separate style properties
  (`--vaadin-input-field-required-indicator-color`), treating *which* mark and
  *what* color as theme choices rather than semantics. If the shared red ever
  reads as "already wrong", that is the entry to write.

  One Vaadin note worth keeping for the layout: the docs recommend *"an
  instruction text at the top of the form explaining the required indicator"* —
  even Vaadin does not consider the marker self-explanatory. In Tuile that
  legend is the app's row, not the layout's (`D_status_bar`).
- **Helper text**, the other half of the seam `design/ideas/new-components.md` infra
  item 2 names, is undesigned — and the inline-right cells are already spoken
  for by the message.

## Related

`D_caption_ownership` and `D_has_validation` (**the two entries this note's
first half graduated into** — read them first), `D_bad_input` (the field's own
report, which reddens the same well), `design/ideas/binder.md` (the writer of
`error_message`; the four-layer vocabulary), `D_on_blur` (the commit point a
field can canonicalize from, which the bad-input notice settles against),
`D_date_field` (a field whose
input outruns its value), `design/ideas/new-components.md` (infra item 2; Tier 2 Form
Layout, Custom Field), `D_box_layouts` (the per-child attribute map;
caller-supplied cross extent), `D_slots`, `D_select` (caller-side measurement),
`D_status_bar` (no framework-reserved row), `D_empty_ancestor` (the empty rect
an overflowing item gets), `D_no_key_interceptor` (one callback
slot cannot be shared), `D_has_value` (the parked required indicator),
`D_has_content` (the statement `FormItem` is an instance of),
`design/ideas/per-child-attribute-map.md` (the placement map `FormLayout` still
hand-rolls), `design/ideas/scroller.md` (what happens past the bottom edge),
`design/ideas/tab-label-rename.md` (the non-component carriers, whose premise
this note's reversal knocked out), `D_component_lookup` (the deleted `caption:`
term, and the rule that deleted it), `lib/tuile/component/AGENTS.md`,
*The value seam* (caption is chrome, text is value).
