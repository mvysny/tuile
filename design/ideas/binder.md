# A Binder — Vaadin's pattern, and the layer vocabulary

**Status:** placeholder, nothing built. Two things earn the file: which parts of Vaadin's `Binder` to
copy, and the four-layer vocabulary (settled while designing `HasBadInput`; it is why that channel is
`bad_input`, not `presentation_error`). `D_has_value` stays the authority: model-mapping, converters,
`read_only` and a field-side required flag live *above* the field.

## The vocabulary (settled)

A `Date` field bound to `Person#birth_date`:

| layer | example | spoken by |
|---|---|---|
| **model** | `Person#birth_date` | Binder |
| **transformations** | `year` + `month` + `day` → `Date`; an ISO string → `Date` | Binder |
| **value** | the `Date` or `nil`, `HasValue#value` | both — why `HasValue` is *the* seam |
| **input** | the glyphs typed, a calendar click, a mask's partial fill | the field; the Binder may *ask* |

| arrow | word | note |
|---|---|---|
| input → value | **parse** | partial; its failure is **bad input** (`D_bad_input`) |
| value → input | **format** | total |
| parse + format inside a field | the field's **converter** | house word; private and hardcoded (`D_integer_field`, `D_float_field`) |
| model ⟷ value | a **transformation** chain | may be several steps |

Why not Vaadin's words:
- **`presentation` is taken**: Vaadin's `Converter<PRESENTATION, MODEL>` means the *value* layer by it
  (a `Date` is "the presentation"), and `D_has_value` adopted that axis. It never names glyphs.
- **A pair can't name a chain**: model → value may be several transformations.
- **`input` alone means what the user put in; the widget is always a `field`.** The sweep of `lib/`
  is essentially done (the few remaining hits are the English sense); `design/terminology.md` still
  says "an input" for the widget (`caret_row`, `text`, `caret`, `well`), and `Theme#input_bg_color`
  is grandfathered. Don't touch "a renderer whose inputs changed"-style English.

**Reserved** for above `value`: `model`, `transformations`, `presentation`, `domain`
(`D_has_value`'s word for the top). Don't spend them on a field concept.

## What to copy from Vaadin (v25.2)

It is the one surveyed toolkit keeping form validity single-sourced without pushing rules into
widgets — Tuile's split already: the field reports what its parse couldn't represent and never judges
(`D_bad_input`); the verdict sits in a slot only an outside validator writes (`D_has_validation`).

- `forField(f).withValidator(pred, msg).bind(get, set)`; `asRequired(msg)` as shorthand.
- `withConverter` for model ⟷ value, with a conversion-error message; chained.
- `readBean` / `writeBean` / `writeBeanIfValid` — a write refuses when anything is invalid.
- `isValid` / `hasChanges` / `validate` → a status aggregate.
- `binding.validate()` for cross-field rules, driven from the other field's value-change listener.
- Escape hatches: `setValidatorsDisabled`, `withDefaultValidator(false)`, `setIsAppliedPredicate`.

**Don't copy** `getDefaultValidator` / `addValidationStatusChangeListener` — they repair a *shared*
invalid/message cell, and Tuile keeps the two facts in two places. `on_bad_input_change` is not that
listener renamed: it reaches cells the field doesn't own. **Ruby deletes the ceremony**: a validator
is a proc returning a message or `nil` — no `Validator`, `ValidationResult`, `Result.ok`.

## What the Binder consumes from a field

- **`is_a?(HasValue)`** marks bindable (`D_integer_field`).
- **`respond_to?(:bad_input?) && bad_input?`** — asked at bind, click, write and forced revalidation.
  The capability may be cached at bind; the status never.
- **Bad input blocks the write even for an optional field** — optional means "may be empty", not
  "may be garbage". `empty?` can't answer it: it is `true` for a field full of unparseable glyphs.
- **`on_bad_input_change`** (shipped) serves an *eager* Binder; `on_value_change` can't stand in —
  typing `-` into an empty `IntegerField` goes `nil` → `nil` and fires nothing. A click-gated Binder
  needs neither.
- **Its own writes must not echo back as edits** — it skips any event whose `from_user?` is false
  (`D_from_user`). `old_value` was parked there for the Binder to claim when it needs it.
- **The verdict write is `field.error_message = msg_or_nil` per pass, and the Binder subscribes
  nothing to show it** — `FormItem` (`D_form_item`) and any app `Label` listen on
  `on_error_message_change` and paint `HasValidation#shown_message`, which orders the two channels.

## Gating Save: at the click, not on `enabled`

Save asks the Binder when pressed; on "no", `ConfirmWindow.alert` names the problems
(`D_confirm_window`). Vaadin instead enables the button from a status listener
(`saveButton.setEnabled(binder.hasChanges() && binder.isValid())`). Not copied:

- **No disabled state exists** — `ComponentBackground::STATES` is `normal`/`active`; the axis is
  `design/ideas/enabled-read-only.md`. The click design needs no framework work.
- **A disabled control can't say why** — no tooltip, and hover is opt-in (`capture_mouse: :hover`)
  with an unreliable exit.
- **It removes the only continuous consumer of bad input**, so no settling policy is needed here.
  (The field side has one anyway: `bad_input_settled?`, `D_bad_input`.) If ever wanted, copy
  Vaadin's rule: errors count only after the user edited and submitted.

## Open

- `Q_binder_signal` — a `Signal` type mirroring Vaadin 25's `validationStatusSignal()`? Nothing has
  asked; the listener idiom is a proc.

## Graduation owes

- The four layer words → `design/terminology.md`, one line each; the choice → a `D_` nomenclature
  ruling in the `D_scroll_nomenclature` mould.
- Reverse the parking in `HasValue`'s rdoc and `D_has_value`'s *deferred* list.

## Related

`D_has_value`, `D_bad_input`, `D_has_validation`, `D_integer_field`, `D_float_field`, `D_form_item`,
`D_form_layout`, `D_listeners`, `D_on_blur`, `D_confirm_window`, `D_status_bar` (no framework error
row), `D_scroll_nomenclature`, `D_from_user`, `design/ideas/enabled-read-only.md`,
`design/ideas/new-components.md` (Custom Field; infra item 2).
