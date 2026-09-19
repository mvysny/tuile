# `FormLayout`: where the label, the message and the required marker go

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

What is left — and all this note now holds — is the *container* half: the cells
themselves. Since 2026-09-19 that is **two** components, not one — a `FormItem`
carrying the chrome around one field, and a `FormLayout` stacking items — so
`Q_form_layout` graduates into a decision entry, **two** rdocs, a book ch7
section, **two** README Components rows and a CHANGELOG line. Unbuilt, and still
what infra item 2 of `design/ideas/new-components.md` is blocked on.

## Settled: the word is `label`, and there is no connection to `HasCaption`

Two questions that used to sit in *Still open*, decided 2026-09-19.

(A third question, *does the `FormItem` carrying that label include `HasCaption`
itself?*, arrived with the wrapper and is answered **no** further down — the two
findings are the same axis seen from both ends.)

**No connection to `HasCaption`, in either direction.** The layout neither reads
`child.caption` as a fallback nor writes it. `D_caption_ownership` chose the
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

**The keyword is `label:`, not `caption:`** — because the two texts now coexist
in one printed row and the call site must not read as though it sets the
widget's own:

```ruby
form.add(username, label: "Username", required: true)
form.add(logging,  label: "Enable logging")   # Checkbox still paints "[x] Logging"
form.add(save)                                 # no label cell at all
```

The split this fixes the vocabulary on: **caption** is text a component paints
on its own face (`HasCaption`); **label** is text one thing carries and another
paints for it. `label` is not a borrowed synonym — it is already Tuile's word
for *text shown for a thing you don't own* (`item_label` on `Select`,
`ComboBox`, `RadioGroup`, `CheckboxGroup`), it names what the layout replaces
(`D_caption_ownership`: an app puts a `Label` beside the field today), and it is
Vaadin's word for this exact cell, so the locator reads `form.field_for(label:)`
like Karibu does.

Why not the others, all four ruled out on evidence rather than taste:

- **`title:`** — the word `design/terminology.md` uses to *define* caption ("a
  `Window` title, a `Button` label"), and `window.rb` names the local `title =
  caption.slice(…)`. It would make the glossary's synonym the API's antonym.
- **`header:`** — already refused as a caption synonym once (`D_confirm_window`'s
  *Why not*: "it would be the title, which `HasCaption#caption` already is").
- **`prompt:`** — `combo_box.rb`'s rdoc already glosses the **placeholder** as
  "a prompt for the query"; it would collide with `HasPlaceholder`, the other
  text near a field.
- **`legend:` / `heading:`** — both name a group or section header. Wrong scale
  for one row.

Graduating this costs one edit outside the component: terminology.md's `caption`
row must stop using "label" as its informal synonym (→ "a `Window` title, a
`Button`'s face text") and gain a `label` row beside it. Whether the *existing*
non-component carriers of the word follow — `Tabs::Tab#caption`,
`MenuBar::Item#caption` — is `design/ideas/tab-label-rename.md`, deliberately a
separate, breaking change that this note does not wait for.

## What the layout has to place

Three pieces of chrome, none of which the field carries or can carry:

- **the label** — `FormLayout#add(field, label: "Username")`; the string lives
  on the {Tuile::Component::FormItem} wrapping the field, never on the field.
- **the message** — read off `content.error_message`, painted in
  `Theme#error_color`.
- **the required marker** — a red dot beside the label; chrome like the
  label, so it rides the wrapper too (below).

## Settled: `FormItem` carries the chrome, `FormLayout` is a column of them

Decided 2026-09-19, and it retires the "does the layout paint the chrome or hold
`Label` children?" fork this note carried for a day.

**The shape.** A `FormItem` owns a label {Tuile::Component::Label}, a message
`Label` and the required marker outright, and includes
{Tuile::Component::HasContent} for the field. That is precisely the statement
`D_has_content` settled — *this is my content, which you populate; my other
children are chrome, mine to manage* — so `FormItem` is a {Tuile::Component::Window}
without a border, down to `HasContent` forcing the content to index 0 while the
chrome is appended. `FormLayout`'s `children` are then homogeneous `FormItem`s
and nothing else.

**Why not paint the cells directly.** Tuile already has components that clip,
ellipsize, resolve the background chain and take a {Tuile::StyledString};
hand-rolling that with `draw_text` is issuing Canvas calls where a `<div>` would
do. `Label` in particular paints all of `rect.height`, padding blank rows itself,
so an empty message row costs one `Label` with empty text — no lazy creation, no
tree churn, no gap to clear.

**It must measure nothing.** The trap is a `FormItem` that knows it needs
`1 + rows + 1` and a `FormLayout` that asks — the deleted bottom-up channel under
a new name. The legal shape: **a `FormItem` takes the rect it is given, gives row
0 to the label, the last row to the message, and everything between to the
content.** There is no `rows` property on `FormItem` at all; `rows:` is a
placement constraint in `FormLayout`'s per-child map, exactly as `Fixed[n]` is in
a `Box`. A `FormItem` dropped into a `Vertical` by hand then just works, which is
the smell test.

What falls out for free, none of which the painting version got:

- **`HasContent#handle_focus` forwards focus into the field** — click the label,
  the field focuses, no code.
- **`item.visible = false` takes the label and the message with it**, which
  discharges the `handle_child_visibility_changed` obligation `D_visibility`
  names as *the* reason `visible=` exists.
- **One choke point for the message wiring** — subscribe and unsubscribe to
  `on_error_message_change` in `content=`, not across `add`/`remove`. The
  single-slot conflict below is unchanged by this, only localized.
- **The locator is a walk over `children`** matching `item.label`.

Four sharp edges, each of which would otherwise ship broken:

- **`FormItem` owes a `handle_theme_changed`.** The red dot and the error message
  are `StyledString`s it authors, and a `StyledString` bakes its colors at
  construction — that is why `content_fg_color` was built and deleted
  (`D_no_hint_color`): whoever authors the content owns the rebuild.
- **The gesture is `item.visible = false`, not `field.visible = false`** — the
  latter leaves three blank rows. Say so in the rdoc rather than forwarding
  visibility from a hook; a third mutation site turns the naive pair into a 2×2.
- **`add` always wraps**, even a `Button` with no label, so `children` stays
  homogeneous. A labelless item simply does not reserve row 0. Non-uniform
  children is how the chrome-vs-app-children distinction grows back at the layout
  level.
- **`FormItem` is a new component**, so it owes the four registrations: rdoc, the
  CHANGELOG, the README Components row, and `component_contract_spec`'s catalog.

### `FormItem` does **not** include `HasCaption`

It looks like it should — it carries chrome text and owns the cells it appears
in — and that is exactly why this is written down rather than left to taste.

**`Tuile::Testing.get` settles it.** The `caption:` filter matches
`is_a?(HasCaption)` plus a compare (`testing.rb`), so an including `FormItem`
would make `Testing.get(caption: "Save")` return a wrapper nobody can click
instead of the `Button` inside it — merging the two lookups this note declined to
merge. Concretely, `form.add(checkbox, label: "Enable logging")` prints two texts
on two components in one row, and `Testing.get(caption: "Logging")` must keep
finding the `Checkbox`.

**The taxonomy agrees once sharpened.** `HasCaption`'s rdoc says *"the chrome
text a component **wears**"*: a `Window`'s caption names the window, a `Button`'s
names the button. A `FormItem`'s label names **the thing inside it**. So the axis
is **self-referential vs other-referential** — which also explains `item_label`
on `Select` / `ComboBox` / `RadioGroup` / `CheckboxGroup` without special
pleading.

**This sharpens `D_caption_ownership` and should graduate with it.** That entry
chose the axis "paints it", not "is a field" — and a wrapper is the case it was
not written for, since a `FormItem` genuinely *does* own those cells. "Paints it"
alone answers yes here; self-vs-other answers no, and no is right.

No `HasLabel` mixin either, for now: one implementing class, which is where the
locator argument stopped for `Tabs`. Hand-roll `FormItem#label` and pay the
lookup debt on `FormLayout#field_for(label:)`.

## Settled: the geometry, and the v1/v2/v3 staging

Decided 2026-09-19. **This replaces the inline-on-both-sides shape this note
recommended until now** — label left, field, message right, all on one row. The
correction that killed it is under *Facts* below.

### The item is three rows, and the message row *is* the gap row

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

The only other no-reflow option is a fourth row per item (label / field /
message / gap), and it costs a third of the screen — 6 items in 24 rows against
8. Not worth it. The price of the choice is that a form with several errors
tightens up exactly where it is least happy; accepted.

v2's configurable `spacing` is then **extra** rows on top of the three,
defaulting to 0 — visually identical to the 1-row gap, but named for what it is
instead of competing with the message for the same cells.

- **One row each for the label and the message, ellipsized** — bounded by the
  row, truncated by the layout (`InfoWindow#lines=` is the model). Ellipsizing a
  validation message is a genuine loss and there is no fix under fixed geometry.
- **A form-level status row showing the first error in full is the *app's*** to
  build from the same data, not the layout's — `D_status_bar` from the other
  side: the framework reserves no row it was not asked for. That is the escape
  hatch for the truncation above.

### The label goes above the field in v1; left is v2

Not because inline-left is wrong, but because label-above needs **no
measurement at all**: the label spans the form's full width, so there is no
label-column width policy, no caller-side measuring pass, and the ellipsis
essentially never fires. It is also the shape that survives a narrow terminal,
where a left label column eats half of it. The measurement question is real and
it lives in v2, which is exactly where deferring it belongs.

### A field declares `rows:`, in v1

`text_area.rb`, `list.rb`, `checkbox_group.rb` and `radio_group.rb` all exist,
and a form that can hold none of them is half a form. Under top-down the layout
has to be told:

```ruby
form.add(notes, label: "Notes", rows: 5)   # default 1
```

Caller-supplied cross extent, the same move `D_box_layouts` already blesses for
`align:`. The item is then `1 + rows + 1` rows rather than 3; the message row
stays the last one.

### Staging

- **v1** — vertical, one column, label above, message/gap row below, `rows:`,
  the required marker, `field_for(label:)`. Spacing fixed at the one fused row.
- **v2** — `spacing` configurable (extra rows, default 0); labels optionally to
  the **left**, which is where the label-column measurement question lands.
- **v3** — multiple columns, every column the same width, not configurable.

### v3: colspan yes, row breaks no, fixed columns before automatic

- **Row breaks are unnecessary.** Columns are equal-width by decree, so two
  `FormLayout`s of the same width and column count produce identical column
  boundaries — stacking them in a `Vertical` already aligns. A section heading
  between two groups is then a component in that `Vertical`, not a feature of
  the form.
- **Colspan is necessary** — a `TextArea` across both columns — and it is the
  per-child attribute map the label already needs.
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
- **`required: true` without `label:` raises.** In the above-shape such a child
  has no label row at all, so the marker has nowhere to go — and the same holds
  in v2, where a labelless child has no label cell either. This retires
  `Q_required_without_label`.
- **A child added with no `label:` gets no label row**, so a `Button` or a
  `Checkbox` costs `rows + 1` rather than `rows + 2`. In v3 the row height is
  the max over the items sharing that row, as any grid does.

## Wiring the message

The message shows in cells the *field* does not invalidate, so its owner has to
be told: `FormItem` subscribes to `on_error_message_change` in `content=` and
unsubscribes from the outgoing occupant in the same call — one choke point,
because `HasContent` makes every swap go through it. That notice exists for
exactly this consumer, and `D_has_validation` records why it is plain listener
inversion rather than the push notice `D_bad_input` withheld (this fact is
discrete, that one is continuous).

**Open, and a real conflict:** `on_error_message_change` is a single
`attr_accessor` slot, and its rdoc says the container painting the message
claims it — *"an app painting its own takes it instead."* A `FormItem` that
claims it silently at `content=` therefore disables an app that already set it,
which is the one-callback-slot failure `D_no_key_interceptor` names (all four
composed fields hit it). Decide with the component: either the layout refuses
to overwrite a non-nil slot, or it chains the previous callable, or the notice
grows a subscriber list. Do not just assign it.

## Facts it rests on, so they don't get re-derived

- **A per-child attribute map is a solved shape.** `Box` keeps constraints in an
  identity-keyed per-child map that is explicitly *not* a second copy of
  ordering (`D_box_layouts`); a `FormLayout` holding `{item => {rows:, colspan:}}`
  copies it. Since `FormItem` landed, the *label* is no longer in that map — it
  is on the item — so what is left there is placement only, which is exactly what
  `Box` keeps. `Component::Slot` is the tree-native answer for a swappable region
  (`D_slots`), and `FormItem` needs none: it has one populatable child, so
  `HasContent` is direct.
- **It owes a `handle_child_visibility_changed` override**, like `Box` — it is the
  rule for any container with layout arithmetic (`D_visibility`). A conditional
  form field is *the* consumer that brought `visible=` in; with `FormItem` the
  label row and the message row are *inside* the thing being hidden, so the
  override only has to reclaim the item's rows and its gap, not chase chrome.
- **Measuring labels does not reopen bottom-up sizing.** Aligning a label
  column needs the *container's own* strings measured — caller-side arithmetic,
  the same move `Select` makes when it measures its labels and assigns the rect
  (`D_select`; `D_box_layouts`' "`align:` is legal only because the cross extent
  is caller-supplied"). It looks like the banned channel and isn't.
- **The layout is the authority for label↔field lookup**, since it holds the
  only copy of the association — so it owes a locator
  (`form.field_for(label: "Name")`), which is what Karibu-Testing does against
  Vaadin 25 form items. `Component#id` + `Tuile::Testing.get`
  (`D_component_lookup`) is a *different* handle, not a replacement:
  an id is a tag the app assigns. `Testing.get(caption:)` keeps its own meaning
  and is not merged into this one — it matches `is_a?(HasCaption)` and so finds
  the self-painters, which is the *other* text in a checkbox row.
- **Top-down layout is the heaviest prior — but it does *not* force both halves
  inline**, which is what this note claimed until 2026-09-19 and got wrong. The
  argument was "a field is handed one row and cannot grow a second for a label
  or a message"; true, and beside the point, because the *field* never grows —
  the **layout** allocates three rows and hands the field the middle one.
  Nothing bottom-up happens. Top-down constrains this design far less than it
  looks; what it really forbids is the layout *asking* the field how tall it
  should be, which is why `rows:` is caller-supplied.

## Still open

- **Label geometry in v2** — a left label column has to pick its width
  (widest label, capped; a fixed `label_width:`; a percentage) and that is the
  caller-side measuring pass v1 exists to avoid. `D_select` is the model for
  measuring without reopening bottom-up.
- **Required indicator — decided in shape, open in glyph.**
  `FormLayout#add(field, label:, required: true)` paints a **red dot beside
  the label**, as Vaadin does. `D_has_value` parked the indicator; this is
  where it lands, and the field still does not know it is required.

  A child added with no `label:` (a `Checkbox`, a `Button`) has no cell for the
  dot, and `required: true` is simply refused there — settled above, in both the
  v1 and the v2 shape.

  Three things checked against Vaadin 25.2 rather than remembered, since they
  shape the TUI version:

  - Vaadin marks a required field *"with an indicator next to the label"* — so
    the marker rides the **label**, which in Tuile means it rides the
    container, exactly as `D_caption_ownership` puts that text there. The
    precedent lines up; nothing to re-argue.
  - Both the glyph and its color are style properties
    (`--vaadin-input-field-required-indicator` /
    `-color`, `::part(required-indicator)`), i.e. Vaadin treats *which* mark as
    a theme choice, not a semantic. Tuile's equivalent question is whether the
    dot's red is a reused `Theme#error_color` or a token of its own — a required
    field is not (yet) *invalid*, and every `Theme` member is validated
    `is_a?(Color)` with a hand-rolled `Theme.new` having to pass all of them, so
    a new token is a breaking change to weigh, not a freebie.
  - The docs also recommend *"an instruction text at the top of the form
    explaining the required indicator"* — worth knowing that even Vaadin does
    not consider the marker self-explanatory. In Tuile that legend is the app's
    row, not the layout's (`D_status_bar`).

  **The glyph is the one real Tuile problem, and it is the ambiguous-width bet
  (`D_ambiguous_width`).** Measured with the gem: `•` U+2022 and `●` U+25CF and
  `·` U+00B7 are all East-Asian **Ambiguous** — 1 column under Tuile's policy, 2
  under ambiguous-as-wide, so each would enlarge the inventory that keeps the
  bet cheap to reverse. `∙` U+2219 BULLET OPERATOR and `◦` U+25E6 measure **1
  under both policies** and are the dots that cost nothing. So: default to `∙`
  (or ASCII `*` with the dot as an opt-in knob, per the rule that a new
  component defaults to ASCII when the pretty glyph is Ambiguous), and if the
  marker becomes a knob it validates at assignment that it took one cluster one
  column wide (`D_scrollbar_ink`).
- **Helper text**, the other half of the seam `design/ideas/new-components.md` infra
  item 2 names, is undesigned — and the inline-right cells are already spoken
  for by the message.

## Related

`D_caption_ownership` and `D_has_validation` (**the two entries this note's
first half graduated into** — read them first), `D_bad_input` (the field's own
report, which reddens the same well), `design/ideas/binder.md` (the writer of
`error_message`; the four-layer vocabulary), `D_on_blur` (the commit point a
field can canonicalize from; the bad-input push notice that is still unbuilt),
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
`design/ideas/tab-label-rename.md` (the same caption/label split applied to the
non-component carriers already shipped), `lib/tuile/component/AGENTS.md`,
*The value seam* (caption is chrome, text is value).
