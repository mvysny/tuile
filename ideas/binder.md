# A Binder for Tuile — the pattern to copy, and the vocabulary that comes with it

**Status:** filed 2026-09-03 as a **placeholder plus a settled vocabulary**.
Nothing is designed here and nothing is implemented; the forms layer is not
started. Two things earn the file: (1) Vaadin's `Binder` is the pattern to
copy, and it is worth writing down *which parts* before anyone improvises one,
and (2) the four-layer terminology below was settled while designing
`HasBadInput` and has nowhere else to live until a `D_` entry exists — it is
the reason that channel is called `bad_input` and not `presentation_error`.

`D_has_value` is the standing authority on what belongs above the field:
"Model-mapping (presentation ⟷ domain) is left to a future forms/binder layer
*above* the field, never baked into field state", and it parks converters,
`read_only` and the required-indicator there too. Nothing here overrides that.

## The terminology (settled — this is the file's real content)

Four layers, and the two arrows that matter. A `Date`-valued field bound to
`Person#birth_date`:

| layer | example | who speaks it |
|---|---|---|
| **model** | `Person#birth_date` | Binder only |
| **transformations** | `birth_year` + `birth_month` + `birth_day` → a `Date`; a `birth_date_iso_string` → a `Date` | Binder only |
| **value** | the `Date`, or `nil` — `HasValue#value` | **both** — the shared layer, which is why `HasValue` is *the* seam |
| **input** | the glyphs the user typed, a calendar click, a mask's partial fill: `"2020-05-01"`, `"xyz"` | the field owns it; the Binder must be able to *ask about* it |

| arrow | word | note |
|---|---|---|
| input → value | **parse** | *partial* — it can fail, and that failure is **bad input** (`D_bad_input`) |
| value → input | **format** | *total* — formatting a `Date` into glyphs cannot fail |
| the parse/format pair, inside a field | the field's **converter** | already the house word (`D_integer_field`: "the converter stays private and hardcoded"; `DECISIONS.md:2010`: a `parse`/`format` hook pair *is* the converter strategy) |
| model ⟷ value, in the Binder | a **transformation** / the Binder's converters | a *chain*, possibly several steps |

Why these words and not Vaadin's, in three lines:

- **`presentation` is unavailable.** Vaadin's `Converter<PRESENTATION, MODEL>`
  uses it for the **value** layer — `convertToModel` "receives a value that
  originates from the user", `convertToPresentation` one "that originates from
  the business object" — so it never names the glyph layer at all, and
  `D_has_value` already adopted the same axis in prose. `Date` is the tell: it
  *is* "the presentation" in Binder-speak while saying nothing about
  formatting.
- **A pair cannot name a chain.** model→value may be several transformations
  (an old schema splitting a date across three columns), so naming one arrow
  after the endpoints of a different chain is what made this confusing.
- **`input` had to be freed.** Tuile's rdoc used "an input" for the *widget*
  (~40 real sites, plus `Theme#input_bg_color`). The rule going forward:
  **"input" alone is what the user put in; the widget is always a `field`**,
  never "an input" — Tuile already says `field` 188 times, and TERMINOLOGY
  already calls that background a **well**, so the token name is grandfathered
  legacy. The sweep is a standalone mechanical pass, deliberately not bundled
  with an unimplemented design. Note ~30 further hits are the ordinary English
  sense ("a renderer whose *inputs* changed", "both shorter and longer *inputs*
  are bugs") and must **not** change.

**Reserved:** `model`, `transformations` and `presentation` belong to the
layers above `value`; `domain` is the word `D_has_value` uses for the topmost
one. Don't spend them on a field-level concept. At graduation the layer words
go to TERMINOLOGY.md (one line each, beside `text` and `caption`) and the
choice to a `D_` entry — a nomenclature ruling in the `D_scroll_nomenclature`
mould.

## Why Vaadin's `Binder` is the pattern

It is the only one of the surveyed toolkits that keeps *form validity* as a
single source of truth without pushing rules into the widgets — which is
exactly the split Tuile has already committed to (`R_no_rules_on_the_field` in
`ideas/bad-input.md`). The parts worth copying, from v25.2:

- **`forField(field).withValidator(pred, message).bind(getter, setter)`** — a
  builder per binding, rules declared beside the binding and nowhere else;
  `asRequired("msg")` as the shorthand.
- **`withConverter`** for the model⟷value transformations, including a
  conversion-error message, and chains where each step sees the previous
  step's output.
- **`readBean` / `writeBean` / `writeBeanIfValid`**, with a write that refuses
  when anything is invalid.
- **`isValid` / `hasChanges` / `validate` → `BinderValidationStatus`** as the
  aggregate the app asks.
- **`binding.validate()`** for cross-field revalidation ("cannot return before
  departing"), driven from the other field's value-change listener.
- **Escape hatches that exist for real reasons:** `setValidatorsDisabled`,
  `setDefaultValidatorsEnabled(false)` / `withDefaultValidator(false)`, and
  `setIsAppliedPredicate` for a binding that shouldn't participate at all.

What Tuile should *not* copy: `HasValidator#getDefaultValidator` and
`addValidationStatusChangeListener`. Both exist to repair a *shared*
`invalid`/`errorMessage` cell on the component; Tuile puts the two facts in two
places instead, so the repair has nothing to fix (`D_bad_input`, and the
`HasValidation` question parked in
`ideas/caption-and-error-ownership.md`). Ruby also deletes most of the
ceremony: a validator is a proc returning a message or `nil`, so there is no
`Validator` interface, no `ValidationResult`, and no `Result.ok`.

## What the Binder must consume from a field

- **`is_a?(HasValue)` is the marker** for "this is bindable" — `D_integer_field`
  says so explicitly.
- **`field.respond_to?(:bad_input?) && field.bad_input?`** is the bad-input
  question — **this half exists today** (`D_bad_input`) — asked at bind, at
  click, at write, and whenever a sibling forces a revalidation. The *capability* is a class fact and may be cached at bind
  time; the *status* may never be cached.
- **Bad input must block the write even for an optional field.** This is the
  failure Vaadin names and the whole reason the channel exists — an optional
  field means "may be empty", not "may be garbage". And it cannot be reached
  through `empty?`, which reports `true` for a field full of glyphs the value
  cannot represent.
- **A push notice (`on_bad_input_change`) is deliberately *not* built** — it
  is needed only by a consumer that must react *between* clicks, which a Binder
  gated at the click is not (`ideas/bad-input.md`).

## The Tuile-specific part: gating Save

**The gate goes at the click, not on the button's enabled state.** Save asks
the Binder when pressed and, on "no", opens an alert naming the problems
(`ConfirmWindow.alert` exists — `D_confirm_window`). Vaadin's idiom is the
other one (v25.2 `flow/binding-data/components-binder-load.md`):

```java
binder.addStatusChangeListener(event -> {
    saveButton.setEnabled(event.getBinder().hasChanges()
                       && event.getBinder().isValid());
});
```

Three reasons not to copy it, ascending:

- **`Button` has no disabled state** — no `enabled` axis on `Component`, no
  `:disabled` in `BG_STATES` (AGENTS.md is explicit that the key is absent
  because the *state* is absent). The enabled design needs framework work
  first; the click design needs none.
- **A disabled control says nothing about why**, and a TUI has no channel to
  explain it: no tooltip, and hover is not even received (mode 1000 is
  press-only — `ideas/hover.md`).
- **It removes the only *continuous* consumer of the bad-input signal**, so
  nothing needs a settling policy: a Binder asked only at the click sees one
  settled state, and the flicker `D_bad_input` describes never arises on this
  side. (The ink still owes one — that is
  `ideas/caption-and-error-ownership.md`.)

If a settling policy is ever wanted here anyway, copy Vaadin's display rule
rather than inventing one: errors count only after the user has edited a field
and submitted.

## Open, and deliberately not designed here

Where a rule's message is *stored* and *shown* (the Binder's own per-binding
cell, or a component member) is
`ideas/caption-and-error-ownership.md`. Whether Tuile grows a `Signal` type to
mirror Vaadin 25's `validationStatusSignal()` is untouched — Tuile's listener
idiom is a plain proc, and nothing has asked for more.

## Related

`D_bad_input` (the field-side channel this consumes, already shipped),
`ideas/bad-input.md` (its deferred push notice), `ideas/caption-and-error-ownership.md` (the `HasValidation`
question; where a message lives and who paints it),
`ideas/new-components.md` (Tier 2 Form Layout, Custom Field; infra items 2–3),
`D_has_value` (the forms layer owns converters, `read_only`, the
required-indicator; the typed-value survey), `D_integer_field` (the field's own
converter stays private; `is_a?(HasValue)` is the Binder's marker),
`D_scroll_nomenclature` (the nomenclature ruling this vocabulary copies),
`D_confirm_window` (the alert the Save button opens), `D_status_bar` (why the
framework places no error row).
