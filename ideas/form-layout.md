# `FormLayout`: where the caption, the message and the required marker go

**Status:** filed 2026-09-03 as `ideas/caption-and-error-ownership.md`, which
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
`ideas/new-components.md` is blocked on. Graduates into a `D_form_layout`, the
component's rdoc, a book ch7 section, a README Components row and a CHANGELOG
line.

## What the layout has to place

Three pieces of chrome, none of which the field carries or can carry:

- **the caption** — `FormLayout#add(field, caption: "Username")`; the string
  lives in the layout's per-child map, never on the field.
- **the message** — read off `child.error_message`, painted in
  `Theme#error_color`.
- **the required marker** — a red dot beside the caption; chrome like the
  caption, so it rides the container too (below).

## Recommended shape: one row per field, inline on both sides

```
   Username ∙ [________________] Required
   Password ∙ [________________] Required
```

(the `∙` is the required marker, red; whether it sits before or after the
caption text, and whether it widens the caption column, goes with the caption
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
  ordering (`D_box_layouts`); a `FormLayout` holding `{field => caption}` copies
  it. `Component::Slot` is the tree-native answer for a swappable region
  (`D_slots`).
- **Measuring captions does not reopen bottom-up sizing.** Aligning a caption
  column needs the *container's own* strings measured — caller-side arithmetic,
  the same move `Select` makes when it measures its labels and assigns the rect
  (`D_select`; `D_box_layouts`' "`align:` is legal only because the cross extent
  is caller-supplied"). It looks like the banned channel and isn't.
- **The layout is the authority for caption↔field lookup**, since it holds the
  only copy of the association — so it owes a locator
  (`form.field_for(caption: "Name")`), which is what Karibu-Testing does against
  Vaadin 25 form items. `Component#id` + `Tuile::Testing.get`
  (`D_component_lookup`) is a *different* handle, not a replacement:
  an id is a tag the app assigns.
- **Top-down layout is the heaviest prior**, and it is what makes both halves
  inline: a field is handed one row and cannot grow a second for a caption or a
  message.

## Still open

- **Caption geometry** — caption column left (aligned, measured caller-side)
  versus a row above. Inline-left is the natural pair to the inline-right
  message; the row-above shape wants the message on a third row and reopens the
  growth question.
- **Required indicator — decided in shape, open in glyph.**
  `FormLayout#add(field, caption:, required: true)` paints a **red dot beside
  the caption**, as Vaadin does. `D_has_value` parked the indicator; this is
  where it lands, and the field still does not know it is required.

  Three things checked against Vaadin 25.2 rather than remembered, since they
  shape the TUI version:

  - Vaadin marks a required field *"with an indicator next to the label"* — so
    the marker rides the **caption**, which in Tuile means it rides the
    container, exactly as `D_caption_ownership` puts the caption there. The
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
- **Helper text**, the other half of the seam `ideas/new-components.md` infra
  item 2 names, is undesigned — and the inline-right cells are already spoken
  for by the message.

## Related

`D_caption_ownership` and `D_has_validation` (**the two entries this note's
first half graduated into** — read them first), `D_bad_input` (the field's own
report, which reddens the same well), `ideas/binder.md` (the writer of
`error_message`; the four-layer vocabulary), `D_on_blur` (the commit point a
field can canonicalize from; the bad-input push notice that is still unbuilt),
`ideas/date-picker.md` (a field whose
input outruns its value), `ideas/new-components.md` (infra item 2; Tier 2 Form
Layout, Custom Field), `D_box_layouts` (the per-child attribute map;
caller-supplied cross extent), `D_slots`, `D_select` (caller-side measurement),
`D_status_bar` (no framework-reserved row), `D_no_key_interceptor` (one callback
slot cannot be shared), `D_has_value` (the parked required indicator),
AGENTS.md "Input values" (caption is chrome, text is value).
