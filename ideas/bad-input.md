# Bad input — the one thing a field knows that no value-change event can carry

**Status:** filed 2026-09-03, nothing implemented, nothing measured. Opened
from the question "**a `DatePicker` cannot report `"xyz"` through
`on_value_change`, so what is the channel?**", and narrowed to exactly that: a
`HasBadInput` mixin, and which fields include it.

**Scope, after two splits.** This note owns **the field's own report**: that
its input cannot be turned into a value, and why nothing else can say so.
Everything else that started here has moved out —

- **the four-layer vocabulary** (`model` / `transformations` / `value` /
  `input`, with `parse` / `format` as the arrows) and the Binder that consumes
  this signal → `ideas/binder.md`;
- **`invalid?` / `error_message` / anything painted** — the `HasValidation`
  question → `ideas/caption-and-error-ownership.md`.

In one line, the words this note needs: **input** is what the user put in;
**bad input** is input the field's value cannot represent. There is
deliberately **no `HasValidation`** on any component today, and it is not this
file's call to add one.

## 1. The hole, stated precisely

`on_value_change` is a **diff over values**, and the map from input to value is
not injective — every unrepresentable input collapses onto the same value. So
the event is structurally incapable of carrying "bad input": the information
was destroyed by the parse before the diff ran.

**One correction to the obvious premise, because it changes the size of the
hole.** Tuile's typed fields do *not* keep the old value on bad input: `value`
is a **derived parse of the input**, recomputed on read
(`integer_field.rb:53-57`, `float_field.rb:61-64`), so a field holding
`2020-01-01` whose input becomes `"xyz"` reads `nil` — the same reset-to-empty
Vaadin's non-configurable "bad input" constraint performs. That transition
*does* fire an event. The residue is what fires nothing:

| input before | input after | `value` before | after | `on_value_change` |
|---|---|---|---|---|
| `"2020-01-01"` | `"xyz"` | a date | `nil` | **fires** (`nil`) — but says *empty*, not *bad* |
| `""` | `"xyz"` | `nil` | `nil` | **silent** |
| `"xyz"` | `"xyzw"` | `nil` | `nil` | **silent** |
| `"xyz"` | `""` | `nil` | `nil` | **silent** — and the field is now *genuinely* empty |

Two distinct failures, and a design must answer both. The silent rows are the
plumbing problem. The *first* row is the semantic one: even when an event fires
it reports the wrong fact, and a form that reads "empty" as "the user cleared
it" will happily save `nil` over a good date the user believes they typed.

**Vaadin hit this exact wall and named it**, which is worth quoting because it
is the failure mode, not a hypothetical (v25.2
`flow/binding-data/components-binder-validation.md`, "Bind Validation on
Changes"):

> Since the provided value can't be parsed correctly, a `null` is provided to
> the binder. Since the field is optional, the binder doesn't complain and the
> validation status would be `true`. This behavior can create the illusion for
> the user that they were able to save an invalid value.

Their fix is a second channel (`ValidationStatusChangeEvent`) whose only job is
to make the binding revalidate. A channel whose diff is over *bad-input status*
rather than over *value* is the irreducible part of whatever Tuile builds.

## 2. Tuile already ships the miniature, and it shows why the trick expires

`IntegerField`'s per-key filter is not a fix, it is a *shrink*: the input can
still hold text the parse rejects, and `value` still silently reads `nil`. The
complete reachable residue, by construction from the accepted characters and
`NUMERIC` (`float_field.rb:44`):

| field | bad input reachable by typing | reads as |
|---|---|---|
| `IntegerField` | `""`, `"-"` | `nil` |
| `FloatField` / `BigDecimalField` | `""`, `"-"`, `"."`, `"-."` | `nil` |

Three states, each of which *looks* obviously incomplete on screen. That is the
whole reason the trick got away with it — the residue is tiny, enumerable and
self-evident, so nobody needed telling. (`"1."` is deliberately *not* in the
table: `NUMERIC` admits it and `normalize` rewrites it, which is that design
being careful about exactly this axis.)

A date's residue is unbounded, and the reason is structural: **a date's
validity is not a per-character property.** `"2020-13-45"` is well-formed under
any per-key filter and denotes nothing; month lengths and leap years are
whole-string facts. So the filter cannot be tightened into a fix — no automaton
over single keystrokes can decide it, because the decision needs the whole
input.

**And masking only converts the problem.** A `dd/mm/yyyy` mask with per-field
ranges (the strictest thing a TUI can do) still admits `"31/02/2026"`, and it
manufactures a *new* bad state: `"__/05/2026"`, which is not garbage but
*incomplete*. Vaadin models that separately and gives it its own message
(`DateTimePickerI18n#setIncompleteInputErrorMessage`) — independent evidence
that the channel survives the mask rather than being obviated by it.

## 3. Only the field can know, and it must not be handed anyone else's verdict

Two error categories exist, and exactly one of them belongs to the component:

| | **bad input** — this note | a rule's verdict — elsewhere |
|---|---|---|
| example | `"xyz"` is not a date; a lone `"-"` | must be in the past; age ≥ 18; not nil |
| authority | **the field, and only the field** (it owns the format) | the app / a Binder (it owns the domain) |
| when known | on every input mutation | when the rules run |
| the field's role | **it is the fact** | a mailbox it cannot fill, defend, or recompute |
| lives on | the field (`HasBadInput`, §4) | the Binder (`ideas/binder.md`) |

The tempting economy is one `invalid?` flag both write. **Vaadin's own
custom-field guide warns against it** (v25.2
`building-apps/forms-data/create-custom-field/index.md`, "Internal
Validation"):

> Do not rely on the same `invalid` and `errorMessage` properties for internal
> validation. Otherwise, when bound to a Binder, external validation is likely
> to override or ignore the internal state.

Vaadin then needs two mechanisms to stop the shared flag lying (a pull via
`getDefaultValidator`, a push via the status event). Tuile inherits neither,
because it puts the two facts in two *places* rather than sharing one cell —
so there is nothing to repair, no manual-validation mode, and no ownership to
hand over. The consequence for this file is simple: **the field reports; it
never stores a verdict.**

## 4. `HasBadInput`

A mixin, per the house pattern (`HasValue` / `HasCaption` / `HasContent`) and
per `D_has_value`'s "`HasValue` is the Ruby-idiomatic `AbstractField`". Being a
mixin is also what makes `is_a?(HasBadInput)` a locator seam for a Binder and
for tests, the same argument that keeps `HasCaption` a mixin.

```ruby
# For a field whose input can be something its value cannot represent.
module HasBadInput
  def bad_input_message = nil          # pull, and the one override point:
                                       # nil when the input converts, else
                                       # why not ("'xyz' is not a valid date")
  def bad_input? = !bad_input_message.nil?
  attr_accessor :on_bad_input_change   # push. 1-arg: the new message-or-nil

  protected
  def sync_bad_input                   # the sole writer of the edge trigger
end
```

One override point, two readers, and `nil` means fine — the convention
`Component#extent` already uses. **The component composes the message**,
because only it holds the input: `"'xyz' is not a valid date"` quotes glyphs
nobody else has, which is an independent reason the channel carries a message
rather than a boolean. No reader for the input itself is needed — on the three
composed fields it is already public as `content.text` (`HasContent` makes
`content` public, which `D_integer_field` lists as a consequence).

### Who includes it: *can my input be something my value cannot represent?*

That is `D_integer_field`'s compose-vs-subclass taxonomy read from the other
side, and it splits the widget set cleanly:

- **Yes** — `IntegerField`, `FloatField`, `BigDecimalField` (the ≤4 inputs of
  §2), and a future `DatePicker` or masked field. The parse is *partial*.
- **No, the parse is identity** — `TextField`, `TextArea`, `PasswordField`. A
  string field's value *is* its input; nothing can fail. `PasswordField` is the
  sharp case: it substitutes glyphs but keeps one display character per text
  character, so the value still equals the input.
- **No input layer at all** — `Checkbox`, `Select`, `RadioGroup`,
  `CheckboxGroup`. The input *is* the selection.
- **No, and it is the interesting exclusion** — `ComboBox`. It has an input
  layer, but the input is a **filter**, not a formatting of the value, so a
  no-match is not a failed conversion; it resolves the desync by *reverting*
  the query. A third strategy beside nil-out and flag, and the reason this
  mixin is not called `HasInput`: having an input layer and having a bad-input
  state are different facts.

### The two members answer two different questions

- **Pull (`bad_input_message`)** is what a consumer needs at every moment it
  did not witness: at bind, before any keystroke, after a programmatic
  `value=`, when a sibling's rule forces a revalidation, and at write time. A
  push-only design would force the consumer to cache the last status it heard
  — a second copy of a derived fact.
- **Push (`on_bad_input_change`)** is the only channel that can report §1's
  silent rows at all. But **v1 does not need it**: a Binder that is only ever
  *asked* (`ideas/binder.md` gates Save at the click) needs the pull alone.
  Every consumer of the push is a *display* — an ink, a live error row, a
  status line — so **the push lands with the first reactive consumer**, which
  is `ideas/caption-and-error-ownership.md`'s call, not this file's.

The notice is named for the bad-input channel, not for validity, and with §3
that is now structural: there is no component-side aggregate for a broader
notice to fire over.

### Uniform iteration without a fake member

A consumer holding a mixed bag asks
`field.respond_to?(:bad_input?) && field.bad_input?` — one line, in one place,
and the Ruby-native form of the question. **Don't give `HasValue` a
`bad_input? = false` default** to flatten that: it would put a field-kind
concept on every `Checkbox` and destroy the locator seam, the same argument
`D_has_value` used to keep `tab_stop?` out of `HasValue`. The *capability* is a
class fact and may be cached at bind time; the *status* may never be.

### Two house rules the implementation inherits

- **`R_no_rules_on_the_field`** — `D_has_value` put converters and validators
  above the field; `D_integer_field` kept `min`/`max` out ("range and format
  are a forms concern") and the converter private. So Tuile's analogue of
  `getDefaultValidator` collapses to a single fact, needing no `Validator`
  object and no registration protocol. A `validators=` array on a component is
  out of scope, and a `valid?` that *runs rules* is the forms layer leaking
  downward.
- **`R_derived_not_cached`** — the status is a pure function of the input, and
  caching a derived fact in an ivar has bitten three times (theme accents,
  `bg_color`, `TextArea#@wrap`). So `bad_input_message` is computed on read and
  the *only* stored state is the last-fired status, for the edge trigger —
  exactly `IntegerField#fire_if_changed`'s `@last_value` shape
  (`integer_field.rb:136-142`). The writer discipline is
  `ProgressBar#sync_ticker`'s: one idempotent sync, the sole writer, called
  from every mutation site, derived from an invariant rather than toggled by
  whichever event noticed.

## 5. Timing — the fact is continuous, and every consumer settles for itself

**Every prefix of a valid date is bad input.** Typing `2020-05-01` walks `"2"`,
`"20"`, `"202"`, … — nine bad inputs before one good one. So the signal is
*correct at every instant* and unusable if consumed naively: an enabled-state
Save button would flicker while the user types correctly, and an ink would
flash red through the same act.

**Ruling: the fact is continuous, the consumers settle.** `bad_input_message`
recomputes per keystroke and the notice fires on every real transition — a
consumer asking "can I save" must never see a stale answer. And v1 has *no*
continuous consumer: the click-time Save gate sees one settled state
(`ideas/binder.md`), and the ink does not exist yet
(`ideas/caption-and-error-ownership.md`). So no settling machinery is needed to
ship this correctly.

**The prerequisite this analysis found, for whenever a settling consumer does
arrive.** `D_integer_field` already recorded the gap in one clause when it
declined to canonicalize `"007"`: *"canonicalizing needs a blur/commit point a
TUI lacks."* Same missing thing, second consumer. Two candidates:

- **Enter** exists (`TextField#on_enter`, `text_field.rb:89`) and is what
  Vaadin uses. Fine for a user who submits, useless for one who Tabs away — and
  Tab is unconditional (rung 1 of the key ladder), so tabbing out of a broken
  field is the *likely* path, not the exotic one.
- **Blur does not exist** — `Component#on_focus` has no counterpart
  (`ideas/hover.md` notes the asymmetry). It is nearly free:
  `Screen#focused=` **already holds `previous` and already diffs it** to fire
  `@on_focus_changed` (`screen.rb:329`, `screen.rb:346`), so a protected
  `on_blur` is one line at that single existing site, reached via `__send__`
  per `D_hook_visibility`, inheriting the edge-trigger properties
  `D_attach_hooks` demands. What it must not assume needs writing down before
  it ships: it fires during the popup-close focus repair and during
  `Screen#close`, and the component may be *detached* by then — so a blur
  handler that invalidates is a silent no-op, exactly as in `on_detached`.

## 6. Options for the component that raised this

- **(A) `DatePicker` with no text input.** Calendar grid only — arrows, PgUp,
  Home. **No bad input is possible**, so the channel has nothing to carry and
  the question evaporates for the component that raised it. Cheapest by far.
  Cost: a keyboard-first user entering a known date (a birth date, the
  canonical case) pays ~30 keystrokes for what typing costs 10 — the wrong
  trade for a TUI.
- **(B) Text input behind a modal commit.** The input lives in a
  `ConfirmWindow`-shaped dialog that refuses to close on garbage, so bad input
  never reaches the form and nothing needs telling. No mixin, no blur;
  `ConfirmWindow` already exists (`D_confirm_window`). Cost: a modal per date
  is heavy in a form with six.
- **(C) `HasBadInput` (§4).** **Recommended if anything is built.** It answers
  both failure rows of §1, gives the fact exactly one home and one writer, and
  needs no framework addition at all for v1 (the `on_blur` of §5 is optional
  and deferred). It retrofits onto the three numeric fields for free (§7),
  which is also how to test it against something real.
- **(D) Vaadin-faithful: one shared flag plus a pull seam and a push event.**
  Rejected on the strength of Vaadin's own warning (§3) — the repair mechanisms
  exist *because* the flag is shared.
- **(E) Do nothing; bad input reads as empty.** The *current* behavior, and the
  illusion §1 quotes, shipped deliberately. Defensible only combined with (A)
  or (B), where no bad input is possible. Not defensible under a text-input
  `DatePicker`.

## 7. Consequences elsewhere, if (C) is taken

- **`empty?` is a statement about the *value*, not the input** — a field
  holding `"xyz"` reports `empty?` → `true` while the user is looking at three
  glyphs. That is §1's semantic hole restated in the settled vocabulary, and it
  is the most consequential line to fall out of the naming pass, because
  `empty?` is what a required-field rule reaches for first. `HasValue#empty?`
  owes an rdoc caveat — *"empty of **value**; ask `bad_input?` whether there is
  input it could not use"* — and a required rule owes the pair.
- **`EmailField` is probably not a component.** Its value *is* its input
  (`D_integer_field`'s taxonomy → it would subclass `TextField`, like
  `PasswordField`), so it has **no bad-input state at all** and needs only
  rules, which `TextField` plus a regex already gives you. What it would
  actually contribute is *a packaged regex*, so ship a validator constant and
  re-tier the component toward reject. `new-components.md` listed it as
  "blocked on the validation seam"; it is blocked on nothing, and building it
  teaches nothing about this.
- **The three numeric fields retrofit as the test case**, one
  `bad_input_message` override each over the ≤4 inputs in §2's table, plus one
  `sync_bad_input` call beside the existing `fire_if_changed`.
- **Items-plus-value components stay out of it.** `Select`, `ComboBox`,
  `RadioGroup` and `CheckboxGroup` deliberately allow a `value` that `items`
  does not contain, with no reconcile, no clamp and no silent drop
  (`D_combobox`, `D_checkbox_group`, `D_radio_group`). That is *not* bad input
  and must not become it — a value outside the item set is a domain rule.
  Worth writing down because wiring it up is the obvious wrong move once a
  channel exists.
- **rdoc / `D_` split at graduation:** the two-places-not-one-cell ruling, the
  pull-and-push argument, the population test, and "the fact is continuous, the
  consumers settle" are `D_` material. The one line that clears AGENTS.md's
  gate is *"a field that parses owes `sync_bad_input` on every input mutation,
  or its bad-input status goes stale with nothing in the diff to notice"* — a
  **new** field breaks that from its own file.

## 8. Cheapest experiment

1. **Prototype the pull on `FloatField`** — it already has 4 bad inputs and a
   `fire_if_changed` to hang a sync beside. Add `bad_input_message`, and a
   sampler pane with two fields and a Save button that alerts ("2 problems:
   …") when any field reports `bad_input?`. That is the whole v1 path, it
   needs no ink ruling and no `Button` work, and it answers the question this
   note opened with: type `xyz` into an empty date-ish field, press Save, and
   see whether the app can tell.
2. **Then add the push and watch it flicker.** Wire `on_bad_input_change` to a
   status `Label` with **no** settling and type `-0.5`. This is the measurement
   §5 rests on and the one thing nobody has observed — and it is
   `ideas/caption-and-error-ownership.md`'s input, so take the number there.
3. **Spec the row that motivates everything:** input `""` → `"xyz"` must fire a
   bad-input notice while `on_value_change` stays silent. A design that cannot
   pass that one has not addressed the question.

## Related

`ideas/binder.md` (the vocabulary; the consumer; the Save gate),
`ideas/caption-and-error-ownership.md` (the `HasValidation` question; the ink
and its settling; where a rule's message lives),
`ideas/new-components.md` (Tier 2 Email Field, Date/Time Picker; infra items
2–3), `ideas/hover.md` (the `on_focus`/no-`on_blur` asymmetry),
`D_has_value` (validators and converters live *above* the field; the deferred
Vaadin-`HasValue` members; why `tab_stop?` stayed out of the mixin),
`D_integer_field` (the derived parse; the missing blur/commit point; the
compose-vs-subclass taxonomy that supplies the population test), `D_float_field`
(the deliberate-copy rule the retrofit follows), `D_attach_hooks` (the
edge-trigger shape `on_blur` must copy), `D_hook_visibility` (a
framework-invoked hook is protected, via `__send__`), `D_progress_bar`
(`sync_ticker`: one idempotent sync, the sole writer), `D_confirm_window`
(option B's vehicle), `D_combobox` / `D_checkbox_group` / `D_radio_group`
(items vs. value: no reconcile — and why that must not be recast as bad input),
`D_key_dispatch` (Tab is unconditional, which is why Enter-only settling
leaks).
