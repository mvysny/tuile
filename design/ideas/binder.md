# A Binder — Vaadin's pattern, the Ruby way

**Status:** design converging, nothing built. Agreed for v1: no Rails, no dry-rb; the model is a
mutable object with attr_accessors (so ActiveRecord works as-is); both modes; a bind-first chain.
The four-layer vocabulary below was settled while designing `HasBadInput` (it is why that channel is
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

## Ruby has no JSR-303

No spec, no annotations — one de-facto library and one alternative:

- **ActiveModel::Validations** (Rails): class macros (`validates :name, presence: true`), `valid?`,
  an `errors` map. It *assigns first and validates after* — the object may sit invalid, `save`
  refuses. That works because a Rails object is a request-scoped copy of the database and dies; a
  Tuile model may be the in-memory source of truth, so **the Binder never leaves an invalid value
  in it**.
- **dry-validation**: a contract *beside* the model, run over a hash, with coercion — closer to
  Vaadin's shape.

v1 depends on neither: `activemodel` drags in `activesupport` + `i18n`, and a validator is just a
proc. Worth knowing: Rails keeps the raw input in `age_before_type_cast` and `numericality` checks
*that* — the same side channel as `bad_input`, found independently.

## Two modes (settled: both, for different use cases)

What Vaadin 25.2 does (docs `building-apps/forms-data/add-form/validation.md`,
`…/fields-and-binding.md`, `flow/binding-data/components-binder-load.md`; `Binder` javadoc):

| | buffered (`readBean` / `writeBean…`) | write-through (`setBean`) |
|---|---|---|
| field-level rule fails | nothing written; `writeBean` throws, `writeBeanIfValid` → `false` | that field isn't written |
| bean-level rules run | only inside `writeBean` / `writeBeanIfValid` / `writeRecord` | on every field change |
| how they see candidates | write into the bean, run, **revert** on failure | the same, per change |
| `validate()` / `isValid()` | bean rules skipped when no bean is set (since 25 `validate()` no longer throws) | all rules |

Either way an invalid value never stays in the bean — but the real bean is scratch space, so its
setters fire, get reverted, and fire again ("your setters must consider this").

**Buffered** — a simple form in an OK/Cancel popup: Cancel is free, nothing is written until valid.
**Write-through** — a settings panel or a live filter; and the *complex* form: beans holding lists
of beans, edited through sub-editor dialogs whose OK writes into the bean, which is write-through
whatever the outer form says. There the app deep-copies a draft, binds it write-through, and on
Save applies the draft to the original.

- **Copying is the app's, never the Binder's** — only the app knows how deep: `dup` shares a
  `person.addresses` array, `Marshal.load(Marshal.dump(x))` breaks on ActiveRecord, procs and IO.
  The Binder edits whatever it is handed. For flat attributes it knows its bindings, so it can copy
  the bound ones draft → original with no diff machinery (`Q_copy_back`).
- **Buffered nests too, if the sub-editor edits the field's *value*, never the model** — a list
  field is a `HasValue` whose value is an array; the dialog's OK sets a *new* array holding an edited
  `dup` of the element. Nothing reaches the model until the outer `write?`, so the outer Cancel still
  works. The modes differ in live bean rules and live visibility to other components, not in
  nesting.
- **Bean rules run against `model.dup`, not Vaadin's write-validate-revert** — write the candidates
  into the copy, run the rules, and only on a pass write the real model. Its setters run once, with
  valid values only, and the rules can run at any time — which closes Vaadin's buffered
  `validate()` gap. Write-through does the same per change. Caveats for the rdoc: `dup` is shallow
  (a setter mutating a shared collection in place leaks into the original; one assigning a new
  object doesn't), and ActiveRecord's `dup` is a new record with `id == nil`, so a rule excluding
  "self" by id misfires (`Q_copy_strategy`).

## The pipeline (settled shape)

```ruby
binder.bind(name_field, :name).required("Name is required")
binder.bind(age_field, :age).validate { |v| "Must be positive" unless v.positive? }
binder.bind(birth_field, :birth_iso)                                  # model stores an ISO string
      .validate { |d| "Can't be in the future" if d > Date.today }   # value side: a Date
      .convert(->(d) { d.iso8601 }, ->(s) { Date.iso8601(s) })       # value→model, model→value
      .validate { |s| "Already taken" if taken?(s) }                 # model side: a String
binder.rule { |p| "Start date is after end date" if p.start_date && p.end_date && p.start_date > p.end_date }

binder.read(person)     # buffered: model → fields, snapshot for changed?
binder.write?(person)   # buffered: validate on a dup, write the real model only on a pass
binder.model = draft    # write-through
binder.changed?
```

- **A chain, because converters make order semantic** — a validator before a converter sees the
  value, after it the model form. Keyword arguments can't say order; the chain costs nothing in the
  common case, where `bind(f, :name)` with no steps is complete.
- **`bind` comes first and registers at once** — each step appends and returns `self`, so there is
  never an unfinished binding (Vaadin's terminal `bind()` needs a check for a forgotten one), and
  the chain still reads field → model.
- **`bind(field, :name)` is `public_send(:name)` / `public_send(:name=, v)`** — attr_accessor,
  `Struct` and ActiveRecord with no adapter; a getter/setter lambda pair is the escape hatch. `Data`
  is immutable and out.
- **A converter is a pair**, since `read` needs model → value too. It fails by raising
  `ArgumentError`, whose message becomes the error (an `error:` override exists) — the stdlib's own
  convention: `Integer("x")`, `Float`, `BigDecimal`, `Date.iso8601` (`Date::Error < ArgumentError`).
  Rescue nothing else, so a bug still surfaces.
- **`required` is not positional** — it asks `field.empty?`, so the order is always bad input →
  `required` → the chain, wherever it is written. Still spelled in the chain: one way to write it.
- **Validators skip `nil`; converters map `nil` → `nil` both ways** (Rails' `allow_nil`) — or every
  validator opens with `v &&`. An empty optional field passes untouched; a required one was stopped
  by `required`.
- **A bean rule returns `nil`, a String (form-level), or `{end_date: "…"}` to blame a field**, which
  then lands on that field's `error_message` (`Q_rule_blame`). Form-level messages go to the Save
  alert below — there is no framework status row (`D_status_bar`).
- **`write?` is the house `Set#add?`**: "did the write happen".

## What was taken from Vaadin (v25.2)

It is the one surveyed toolkit keeping form validity single-sourced without pushing rules into
widgets — Tuile's split already: the field reports what its parse couldn't represent and never judges
(`D_bad_input`); the verdict sits in a slot only an outside validator writes (`D_has_validation`).

- `forField(f).withValidator(pred, msg).bind(get, set)` → the bind-first chain; `asRequired(msg)` →
  `.required(msg)`.
- `withConverter` → `.convert(to_model, to_value)`, chained.
- `readBean` / `writeBeanIfValid` / `setBean` → `read` / `write?` / `model=`; `writeBean`'s
  exception has no counterpart.
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
(`D_confirm_window`). In write-through mode the rules have already run live, but Save is still the
gate for applying the draft. Vaadin instead enables the button from a status listener
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
- `Q_copy_back` — the draft → original copy of bound attributes: a Binder method (name?), or left to
  the app as `binder.read(draft); binder.write?(original)`, which already does exactly that?
- `Q_copy_strategy` — ship `dup` hardcoded, or a `copy:` proc for models whose `dup` misbehaves
  (ActiveRecord's `id == nil`, in-place setters)? Generic machinery takes strategies.
- `Q_rule_blame` — the blame shape: a `{attr => msg}` hash, or `[attr, msg]`? Several at once?
- `Q_binder_names` — `read` / `write?` / `model=` / `rule` are placeholders.

## Graduation owes

- The four layer words → `design/terminology.md`, one line each; the choice → a `D_` nomenclature
  ruling in the `D_scroll_nomenclature` mould.
- The Vaadin mode table and the ActiveModel / dry-validation survey → `R_` entries with their
  provenance; the two modes, the `dup` choice and the nil policy → a `D_` entry.
- Reverse the parking in `HasValue`'s rdoc and `D_has_value`'s *deferred* list.
- rdoc for the Binder (the modes and their use cases, the `dup` caveats) and a CHANGELOG line.

## Related

`D_has_value`, `D_bad_input`, `D_has_validation`, `D_integer_field`, `D_float_field`, `D_form_item`,
`D_form_layout`, `D_listeners`, `D_on_blur`, `D_confirm_window`, `D_status_bar` (no framework error
row), `D_scroll_nomenclature`, `D_from_user`, `design/ideas/enabled-read-only.md`,
`design/ideas/new-components.md` (Custom Field; infra item 2).
