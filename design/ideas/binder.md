# A Binder — Vaadin's pattern, the Ruby way

**Status:** design converging, nothing built. Agreed for v1: no Rails, no dry-rb; the model is a
mutable object with attr_accessors (so ActiveRecord works as-is); both modes, as two classes; a
bind-first chain; bindings run on every value change, at the cadence `design/ideas/value-change-mode.md`
gives the field (**a prerequisite** — build it first). Still open: the `Q_` list at the end.
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

**Buffered** (`BufferedBinder`) — a simple form in an OK/Cancel popup: Cancel is free, nothing is
written until valid.
**Write-through** (`UnbufferedBinder`) — a settings panel or a live filter; and the *complex* form: beans holding lists
of beans, edited through sub-editor dialogs whose OK writes into the bean, which is write-through
whatever the outer form says. There the app deep-copies a draft, binds it write-through, and on
Save applies the draft to the original.

- **Copying is the app's; the Binder ships no copy capability** — only the app knows how deep:
  `dup` shares a `person.addresses` array, `Marshal.load(Marshal.dump(x))` breaks on ActiveRecord,
  procs and IO. The Binder edits whatever it is handed, and its rdoc guides the app to `dup` or
  deep-copy as its model needs. **Applying the draft back is the app's too.** A binder can't do it:
  the draft exists *because* of the nested lists the sub-editors write, and those are unbound, so
  "copy the bound attributes" would miss exactly them. (An earlier sketch had
  `binder.read(draft); binder.write?(original)`; the two-class split below removes it, and it was
  wrong for this case anyway.)
- **Buffered nests too, if the sub-editor edits the field's *value*, never the model** — a list
  field is a `HasValue` whose value is an array; the dialog's OK sets a *new* array holding an edited
  `dup` of the element. Nothing reaches the model until the outer `write?`, so the outer Cancel still
  works. The modes differ in live bean rules and live visibility to other components, not in
  nesting.
- **Bean rules run Vaadin's way: write into the real model, validate, revert on failure** — snapshot
  the bound attributes through their getters, write the candidates, run the rules, and on a failure
  restore the snapshot through the setters. Write-through does the same per change. The cost is
  accepted and goes in the rdoc: on a failure every setter fires twice, and the revert restores
  only *bound* attributes, so state a setter derives elsewhere comes back only if the setter
  re-derives it. Validating a `dup` instead was rejected: it needs a copy the Binder can't do right
  for every model (shallow `dup` leaks in-place setters; ActiveRecord's `dup` has `id == nil`), so a
  customizable copy — against the no-copy-capability ruling above.
- **Buffered `validate` runs bean rules too** — the Binder remembers the model `read` was handed and
  write-validate-reverts against it, so a "Check" button sees cross-field errors before Save.
  Vaadin's buffered `validate()` skips them, holding no bean.

## Two classes, one per mode (settled)

**`BufferedBinder`** has `read` / `write?` / `write!` / `changed?`; **`UnbufferedBinder`** has
`model=`. The split deletes the mode-switch questions outright (`read` after `model=`, `model=`
after `read`), and each API stays small. `bind`, `rule`, `last_validation` and the chain are shared.

- **Sharing is composition, not a base class** (`cop` rule 2): one internal engine both hold, with
  about four one-line delegators. Leaning, not ruled — `Q_shared_engine`.
- **`model = nil`** clears every field (`nil` → `empty_value`, the same rule as `read`) and every
  verdict; bindings keep listening and validating, bean rules are skipped (no bean), nothing is
  written. Vaadin's `setBean(null)`.
- **`changed?` is `BufferedBinder`'s alone in v1** — unbuffered, every valid edit is already in the
  model, so "changed" has no settled meaning there.

## When bindings run (settled)

- **Both classes run a binding whenever its field's value changes** — to refresh that field's
  verdict and `last_validation`. `BufferedBinder` writes nothing then; `UnbufferedBinder` writes the
  model (write-validate-revert, bean rules included). `write?` runs every binding plus the bean
  rules — that is the "click-gated" part, and it is only the Save gate, not the display.
- **The cadence is the field's, not the Binder's**: a form field on `:on_change` announces on blur
  or ENTER, so no verdict paints while the user is mid-word (`design/ideas/value-change-mode.md`).
  The Binder owns no blur hook of its own.
- **`write?` / `validate` read `value` live**, so a Save *shortcut* pressed with focus still in the
  field (its notice held) still writes the right value. `changed?` is the one reader that notices
  the held notice — `Q_changed_detection`.
- **`read` / `model=` re-populate the fields and recompute the whole `last_validation`** — so
  `last_validation.empty?` means something from the first frame. What they do to the *shown*
  verdicts is `Q_read_verdicts`.

## `last_validation` (settled)

The Binder's current verdict: the `{attr => [ValidationFailure]}` map, updated whenever bindings
run — a value change, `write?` / `write!`, `read` / `model=`. Returned frozen. It is how the app
gets the failures after `write?` answered `false`, and what the Save alert iterates.

**Staleness rule:** a binding run replaces only its own attr's *field-step* entry; bean-rule
entries (the `nil` key, and attrs a rule blamed) are replaced only when bean rules run — in
`BufferedBinder` that is `write?` / `write!` / `validate` / `read` alone. So after the user fixes `start_date`,
"Start date is after end date" stays until the next `write?`. Vaadin behaves the same, and "last"
in the name says so.

## The pipeline (settled shape)

```ruby
binder = BufferedBinder.new           # or UnbufferedBinder.new
binder.bind(name_field, :name).required("Name is required")
binder.bind(age_field, :age).validate { |v| "Must be positive" unless v.positive? }
binder.bind(birth_field, :birth_iso)                                  # model stores an ISO string
      .validate { |d| "Can't be in the future" if d > Date.today }   # value side: a Date
      .convert(->(d) { d.iso8601 }, ->(s) { Date.iso8601(s) })       # value→model, model→value
      .validate { |s| "Already taken" if taken?(s) }                 # model side: a String
binder.rule { |p| "Start date is after end date" if p.start_date && p.end_date && p.start_date > p.end_date }
binder.last_validation  # => {attr => [ValidationFailure]}, frozen; {} when valid
binder.validate         # a full run — every binding + the bean rules, every verdict written — → last_validation

# BufferedBinder
binder.read(person)     # model → fields, snapshot for changed?
binder.write?(person)   # write, validate, revert on failure → true / false
binder.write!(person)   # the same, raising ValidationError on failure
binder.changed?

# UnbufferedBinder
binder.model = draft    # model → fields; each valid change writes through
binder.model = nil      # clears the fields; validates, writes nothing
```

- **A chain, because converters make order semantic** — a validator before a converter sees the
  value, after it the model form. Keyword arguments can't say order; the chain costs nothing in the
  common case, where `bind(f, :name)` with no steps is complete.
- **`bind` comes first and registers at once** — each step appends and returns `self`, so there is
  never an unfinished binding (Vaadin's terminal `bind()` needs a check for a forgotten one), and
  the chain still reads field → model.
- **`bind(field, :name)` is `public_send(:name)` / `public_send(:name=, v)`** — attr_accessor,
  `Struct` and ActiveRecord with no adapter. `Data` is immutable and out. **No getter/setter lambda
  pair in v1**: every binding has an attr symbol, which is what keys `last_validation` and what a
  bean rule blames. Additive later, but it then owes an answer for both.
- **A converter is a pair**, since `read` needs model → value too. It fails by raising
  `ArgumentError`, whose message becomes the error (an `error:` override exists) — the stdlib's own
  convention: `Integer("x")`, `Float`, `BigDecimal`, `Date.iso8601` (`Date::Error < ArgumentError`).
  Rescue nothing else, so a bug still surfaces.
- **`required` is not positional** — it asks `field.empty?`, so the order is always bad input →
  `required` → the chain, wherever it is written. Still spelled in the chain: one way to write it.
- **Empty vs `nil`: copy Vaadin** (nobody has solved it better). `read` maps a `nil` attribute to
  `field.empty_value` (Vaadin's null-representation adapter); the write passes the value through
  unchanged, so a blank `TextField` writes `""` over a `nil` — the same drift Vaadin has, accepted.
  `changed?` tracks user edits rather than `==` (Vaadin's default), so the drift doesn't read as a
  change.
- **Validators skip `nil`; a converter maps `nil` *and the field's empty value* to `nil`** (Rails'
  `allow_nil`) — or every validator opens with `v &&`, and `Integer("")` fails an empty optional
  field. Vaadin's built-in `StringToIntegerConverter` maps `""` to `null` itself; ours are procs, so
  the Binder does it for them. Consequence to state in the rdoc: a `TextField` with *no* converter
  hands its validators `""`, not `nil` — as Vaadin's do. Leaning — `Q_empty_values`.
- **A bean rule returns `nil`, a String (form-level), or `{end_date: "…"}` to blame a field**, which
  then lands on that field's `error_message`. Form-level messages go to the Save alert below — there
  is no framework status row (`D_status_bar`).
- **The verdict is one map, `{attr => [ValidationFailure]}`** — each a `Data` holding `field`,
  `message`, `value` (whatever the failing step saw: value side before a converter, model side after
  it; a blamed attribute's candidate), open to more members later. Field steps and bean rules fill
  the same map, so the Save alert and the app iterate one thing. Every key holds an array, one
  shape: a field step stops at its first failure, so a field contributes one; several bean rules may
  blame the same attr. **Form-level failures sit under the `nil` key** (a `Hash` takes it; Rails'
  `:base` is the fallback that wasn't needed), with `field` and `value` nil. The rule's *return*
  stays a bare String or hash; the Binder builds the `Data` — the rule knows no field.
- **A failure is a value, an error is raised** — `ValidationFailure` is the entry; `ValidationError`
  is the exception `write!` raises, carrying the whole map. Not `ValidationResult`: a result may be
  ok and every entry here is a failure (Vaadin's `ValidationResult` is the ok-or-error sum type
  deleted below). `ValidationFailure` covers a parse or conversion failure as naturally as a
  broken rule.
- **`write?` / `write!` are ActiveRecord's `save` / `save!`** (`save!` raises `RecordInvalid`,
  ActiveModel's `validate!` raises `ValidationError`) — `write?` in the house `Set#add?` sense, "did
  the write happen". `ValidationError < Tuile::Error`, like `StyledString::ParseError`: bad data,
  not framework misuse, yet still Tuile's.

## What was taken from Vaadin (v25.2)

It is the one surveyed toolkit keeping form validity single-sourced without pushing rules into
widgets — Tuile's split already: the field reports what its parse couldn't represent and never judges
(`D_bad_input`); the verdict sits in a slot only an outside validator writes (`D_has_validation`).

- `forField(f).withValidator(pred, msg).bind(get, set)` → the bind-first chain; `asRequired(msg)` →
  `.required(msg)`.
- `withConverter` → `.convert(to_model, to_value)`, chained.
- `readBean` / `writeBeanIfValid` / `writeBean` → `BufferedBinder#read` / `write?` / `write!`;
  `setBean` → `UnbufferedBinder#model=`; `ValidationException` → `ValidationError`.
- `isValid` / `validate` → `last_validation` / `validate`, the `{attr => [ValidationFailure]}` map;
  `hasChanges` → `changed?`.
- "Validation errors only display after the user has edited each field and submitted"
  (`components-binder-load.md`) — the source for `Q_read_verdicts`'s lean.
- `binding.validate()` for cross-field rules, driven from the other field's value-change listener.
- Escape hatches: `setValidatorsDisabled`, `withDefaultValidator(false)`, `setIsAppliedPredicate`
  — named here, not yet given Ruby names or a v1/deferred ruling (`Q_escape_hatches`).

**Don't copy** `getDefaultValidator` / `addValidationStatusChangeListener` — they repair a *shared*
invalid/message cell, and Tuile keeps the two facts in two places. `on_bad_input_change` is not that
listener renamed: it reaches cells the field doesn't own. Nor `validationStatusSignal()` — **no
`Signal`s in Tuile, period**, until someone asks; the listener idiom is a proc. **Ruby deletes the ceremony**: a validator
is a proc returning a message or `nil` — no `Validator`, `ValidationResult`, `Result.ok`.

## What the Binder consumes from a field

- **`is_a?(HasValue)`** marks bindable (`D_integer_field`).
- **`respond_to?(:bad_input?) && bad_input?`** — asked at bind, click, write and forced revalidation.
  The capability may be cached at bind; the status never.
- **Bad input blocks the write even for an optional field** — optional means "may be empty", not
  "may be garbage". `empty?` can't answer it: it is `true` for a field full of unparseable glyphs.
- **`on_bad_input_change`** (shipped) — the Binder subscribes it beside `on_value_change`, because
  bindings run on change and `on_value_change` can't stand in: typing `-` into an empty
  `IntegerField` goes `nil` → `nil` and fires nothing, so `last_validation` would miss the bad input
  until the next `write?`. The notice is only a *trigger*: it carries the settled, showable report,
  so the run asks the pull, `bad_input?`, like every other run.
- **A bad-input pass writes `error_message = nil`, not the report** — `shown_message` already
  prefers the field's own report, and a copied one would go stale the moment the user fixes the
  input. The failure still goes into `last_validation`, with `bad_input_message` as its message.
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
  (The field side has one anyway: `bad_input_settled?`, `D_bad_input`; the per-change runs above
  only refresh `last_validation` and the verdicts, never a button.) If ever wanted, copy Vaadin's
  rule: errors count only after the user edited and submitted.

## Open questions

- **`Q_read_verdicts`** — the owner's first take: `read` / `model=` re-run the bindings "so that
  validation errors are shown or cleared". Leaning: **recompute `last_validation`, but write `nil`
  to every field's `error_message`**. Vaadin's docs: errors "only display after the user has edited
  each field and submitted" — otherwise a blank "New person" dialog opens with every required field
  red. Verdicts then appear per field on its first change, and all at once on `write?` / `validate`.
- **`Q_empty_values`** — the converter-maps-empty-to-`nil` / validators-skip-`nil` pair above. The
  alternative is pure Vaadin: validators see `""` and each converter handles empty itself.
- **`Q_changed_detection`** — `changed?` by user-edit events (Vaadin's default) misses an edit whose
  notice a field on `:on_change` is still holding (Save by shortcut, focus still in the field).
  Either `changed?` compares against the `read` snapshot for a focused field, or the Binder can
  release held notices (`value-change-mode.md`'s `Q_pending_flush`) — prefer the first, no new
  public API on fields.
- **`Q_shared_engine`** — an internal engine both classes compose (leaning, `cop` rule 2) vs. an
  abstract `Binder` base both *are*. The delegators are ~4 one-liners.
- **`Q_unbuffered_candidates`** — in `UnbufferedBinder`, what the write-validate-revert of a change
  writes: that one binding, or every binding changed since `model=` whose field steps pass (Vaadin's
  `changedBindings`)? The second lets a rule that failed on field A pass once field B is fixed.
- **`Q_rule_gating`** — do bean rules run while a field step fails? Leaning **no** (Vaadin): a rule
  would see a model missing that field's candidate.
- **`Q_one_message`** — several failures on one attr (bean rules may blame it twice): `FormItem` has
  one message row (`D_form_item`), so leaning **the first** lands on `error_message`; all stay in
  `last_validation`.
- **`Q_read_conversion`** — a model → value converter raising at `read` (a malformed stored ISO
  string): raise (it is the app's data, a bug), or blank the field and record a failure?
- **`Q_validator_return`** — raise on a validator returning anything but a String or `nil`, to catch
  the predicate mistake (`validate { |v| v.positive? }` returning `true`, read as a message)?
- **`Q_required_marker`** — `required` can't light `FormItem`'s marker: the Binder is handed the
  field, never the item, so the app says "required" twice. Accept as a cost, or let `bind` find the
  enclosing `FormItem` (a tree walk up from the field)?
- **`Q_escape_hatches`** — the three Vaadin escape hatches above: v1 or deferred, and their names.
  Note `withDefaultValidator(false)` would skip the bad-input check, which sits oddly beside "Don't
  copy `getDefaultValidator`".
- **`Q_constants`** — leaning `Tuile::BufferedBinder` / `Tuile::UnbufferedBinder` (one top-level
  constant per file), the shared types nested in one of them or in a `Tuile::Binder` namespace
  module: `Binding`, `ValidationFailure`, `ValidationError < Tuile::Error`.

## Graduation owes

- `design/ideas/value-change-mode.md` graduates first; this idea assumes its `:on_change` cadence.
- The four layer words → `design/terminology.md`, one line each; the choice → a `D_` nomenclature
  ruling in the `D_scroll_nomenclature` mould.
- The Vaadin mode table and the ActiveModel / dry-validation survey → `R_` entries with their
  provenance; the two modes as two classes, write-validate-revert over a `dup` (the road not
  taken), no copy capability, the nil policy and `last_validation`'s staleness rule → a `D_` entry.
- "No `Signal`s in Tuile" is framework-wide, not the Binder's → its own `D_` (or a line in an
  existing one) once something graduates that would have used one.
- Reverse the parking in `HasValue`'s rdoc and `D_has_value`'s *deferred* list.
- rdoc for the Binder (the modes and their use cases, the revert caveats, how to `dup` a draft)
  and a CHANGELOG line.

## Related

`D_has_value`, `D_bad_input`, `D_has_validation`, `D_integer_field`, `D_float_field`, `D_form_item`,
`D_form_layout`, `D_listeners`, `D_on_blur`, `D_confirm_window`, `D_status_bar` (no framework error
row), `D_scroll_nomenclature`, `D_from_user`, `design/ideas/value-change-mode.md` (the
prerequisite), `design/ideas/enabled-read-only.md`,
`design/ideas/new-components.md` (Custom Field; infra item 2).
