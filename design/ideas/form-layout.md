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

What is left — and all this note now holds — is the *container* half: the
`FormLayout` that has the cells. Unbuilt, and still what infra item 2 of
`design/ideas/new-components.md` is blocked on. `Q_form_layout` graduates into a decision
entry, the component's rdoc, a book ch7 section, a README Components row and a CHANGELOG
line.

## Settled: the word is `label`, and there is no connection to `HasCaption`

Two questions that used to sit in *Still open*, decided 2026-09-19.

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

- **the label** — `FormLayout#add(field, label: "Username")`; the string
  lives in the layout's per-child map, never on the field.
- **the message** — read off `child.error_message`, painted in
  `Theme#error_color`.
- **the required marker** — a red dot beside the label; chrome like the
  label, so it rides the container too (below).

## Recommended shape: one row per field, inline on both sides

```
   Username ∙ [________________] Required
   Password ∙ [________________] Required
```

(the `∙` is the required marker, red; whether it sits before or after the
label text, and whether it widens the label column, goes with the label
geometry below.)

- **Inline right for the message.** One row, no growth, nothing bottom-up —
  which is the whole reason to prefer it. The message is bounded by the row, so
  the layout truncates with an ellipsis (`InfoWindow#lines=` is the model).
- **A form-level status row showing the first error is the *app's*** to build
  from the same data, not the layout's — `D_status_bar` from the other side: the
  framework reserves no row it was not asked for.

## Wiring the message

The layout paints the message in cells the *field* does not invalidate, so it
has to be told: subscribe to `on_error_message_change` at `add`, unsubscribe at
`remove`. That notice exists for exactly this consumer, and `D_has_validation`
records why it is plain listener inversion rather than the push notice
`D_bad_input` withheld (this fact is discrete, that one is continuous).

**Open, and a real conflict:** `on_error_message_change` is a single
`attr_accessor` slot, and its rdoc says the container painting the message
claims it — *"an app painting its own takes it instead."* A `FormLayout` that
claims it silently at `add` therefore disables an app that already set it,
which is the one-callback-slot failure `D_no_key_interceptor` names (all four
composed fields hit it). Decide with the component: either the layout refuses
to overwrite a non-nil slot, or it chains the previous callable, or the notice
grows a subscriber list. Do not just assign it.

## Facts it rests on, so they don't get re-derived

- **A per-child attribute map is a solved shape.** `Box` keeps constraints in an
  identity-keyed per-child map that is explicitly *not* a second copy of
  ordering (`D_box_layouts`); a `FormLayout` holding `{field => label}` copies
  it. `Component::Slot` is the tree-native answer for a swappable region
  (`D_slots`).
- **It owes a `handle_child_visibility_changed` override**, like `Box` — it is the
  rule for any container with layout arithmetic (`D_visibility`). A conditional
  form field is *the* consumer that brought `visible=` in, so a `FormLayout`
  that skipped this would leave the hole in exactly the place it was built for:
  the label row and the message cells of a hidden field must go with it.
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
- **Top-down layout is the heaviest prior**, and it is what makes both halves
  inline: a field is handed one row and cannot grow a second for a label or a
  message.

## Still open

- **Label geometry** — label column left (aligned, measured caller-side)
  versus a row above. Inline-left is the natural pair to the inline-right
  message; the row-above shape wants the message on a third row and reopens the
  growth question.
- **Required indicator — decided in shape, open in glyph.**
  `FormLayout#add(field, label:, required: true)` paints a **red dot beside
  the label**, as Vaadin does. `D_has_value` parked the indicator; this is
  where it lands, and the field still does not know it is required.

  `Q_required_without_label`: a child added with no `label:` (a `Checkbox`, a
  `Button`) has no cell for the dot. Either `required: true` is refused there,
  or the marker gets a column position of its own independent of the label —
  goes with the geometry question above.

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
`D_status_bar` (no framework-reserved row), `D_no_key_interceptor` (one callback
slot cannot be shared), `D_has_value` (the parked required indicator),
`design/ideas/tab-label-rename.md` (the same caption/label split applied to the
non-component carriers already shipped), `lib/tuile/component/AGENTS.md`,
*The value seam* (caption is chrome, text is value).
