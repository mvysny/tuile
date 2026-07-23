# HasValue — do input components share a "value" concept?

**Status:** SETTLED, implementation in progress. Spun out of the ComboBox
work ([`combobox.md`](combobox.md)) because it's the question *every*
future input component asks, not a ComboBox detail. Downstream of this
sit Forms and a Binder — mentioned here only to keep the seam honest, not
designed.

## Settled (locked in)

- **Typed value, arbitrary type.** `value` holds whatever the component
  holds — String for text fields, a domain object for the future combo
  box. Ruby's dynamic typing makes "generic over V" free (see "The Ruby
  dissolve," below).
- **Name: `HasValue`, at `Tuile::Component::HasValue`** (file beside
  `has_content.rb`). Rejected alternatives, each naming an *adjacent*
  capability rather than "holds a value": `Field` (carries focus/editing
  too), `Valued`/`Valuable` (reads as *esteemed*/*worth money* — the Ruby
  `-able` idiom just doesn't fit this meaning), `Bindable` (overpromises a
  Binder that doesn't exist; names the downstream use, not the thing),
  `Input`/`InputComponent` (role/base-class flavor, broader than value,
  collides with `TextInput`), `HoldsValue`/`ValueHolder` (no lineage
  payoff; the noun reads as a wrapper class), `Editable` (names the
  *read-only axis we deferred* — a read-only field still has a value; and
  none of the mixin's methods say "edit"). `HasValue` wins on being
  brutally literal, matching its own method names, and carrying the
  Vaadin lineage this project already wears.
- **Minimal surface:** `value` / `value=` / `empty?` / `clear` /
  `on_value_change` (new-value only). Deferred to Forms/Binder: read-only,
  required-indicator, event old-value/from-client, converters/validators.
- **`TextInput` includes it** for unification. A text component's value
  *is* its text: `value`/`value=` are the seam over the same buffer as
  `text`/`text=` (which stays as the text-native name). `text=` fires
  both `on_change` (kept, text-flavored) and `on_value_change` (the seam).
  `empty_value` is `""` there, `nil` by default elsewhere.
- **ComboBox is a separate session.** The mixin is built to drop in: its
  default `@value` storage + `value=` (repaint + listener) is exactly what
  a combo box uses; only `TextInput` overrides the storage (to back it
  with `@text`).

## The question, precisely

Tuile has exactly one editable component today, {TextInput}
({TextField}/{TextArea}), and it exposes its contents as `text` (a
`String`) with an `on_change(new_text)` listener. That is *de facto* a
"holds a value, notifies on change" component — Vaadin's `HasValue` — but
named for text specifically.

The moment a second kind of input arrives (ComboBox, and after it
IntegerField / DatePicker / a checkbox), we face a fork:

1. **String-only.** Every input's value is a `String`; the caller maps
   the string back to whatever it meant (`"42".to_i`, look the label up
   in a hash). No shared abstraction, no renderer machinery. `text` stays
   the whole story.
2. **Typed value (`HasValue`-style).** Each input holds a value of its
   *natural* type — ComboBox a `T`, IntegerField an `Integer`, DatePicker
   a `Date` — behind a uniform `value` / `value=` / change-listener seam.
   The field formats the typed value into the string its editor shows.

The user's instinct: String might be enough, *"if all of them boil to
String we don't have to invent complicated renderer machinery"* — with
the counter-argument being exactly the typed components (date/time,
int/decimal) that don't boil cleanly.

## The Ruby dissolve: the "machinery" fear is a Java fear

The whole reason String-only is *tempting* is the cost of the typed path.
In **Java**, that cost is real and structural:

- `HasValue<E extends ValueChangeEvent<?>, V>` — a two-type-parameter
  generic interface that infects every field signature, every `Binder`
  binding, every `Converter<PRESENTATION, MODEL>`.
- A ComboBox needs an `ItemLabelGenerator<T>`, a `Renderer<T>`, a
  `DataProvider<T, ?>` — a genuine machinery, because Java can't say
  "just call `.to_s`" without an interface to hang it on.

In **Ruby**, almost all of that evaporates:

- "Generic over `V`" is *free*. `value` returns whatever the component
  holds; there is no type parameter to thread, no signature to infect.
  Duck typing *is* the generic.
- A "renderer" is a one-line proc, defaulting to `:to_s`:
  `item_label = ->(item) { item.to_s }`. That's the entire "machinery."
- A "converter" (string ⟷ model) is likewise a proc pair, and it lives
  in the *future* Binder layer, not in the field.

So the axis the user is weighing — "avoid complicated machinery" — is
much flatter in Ruby than the Java experience suggests. Typed value
costs a default `->(x){x.to_s}` and an ivar. That reframes the decision:
we're not buying our way out of machinery by going String-only; we're
mostly just choosing whether `value` returns the item or its label.

## Survey — how other toolkits model input value

| Toolkit | Value seam | Typed? | Change event carries | Model mapping lives in |
|---|---|---|---|---|
| **Vaadin** | `HasValue<E,V>` | yes, generic per component | old, new, **isFromClient** | `Binder` + `Converter` (a layer above) |
| **Swing** | none unified — `getText`/`getValue`/`getSelectedItem` | ad-hoc per widget | `Document`/`ChangeListener`, no value | app code / (JGoodies) Binding |
| **Android View** | none unified — per-widget getters | ad-hoc | per-widget listeners | ViewModel + LiveData/DataBinding |
| **Textual** (Py TUI) | reactive `value` attr per widget | no (Python — dynamic) | `Changed` message w/ value | app / no built-in binder |
| **React** (web) | `value` prop + `onChange` (controlled) | no (JS — dynamic) | event w/ target value | form libs (Formik / RHF) above |
| **Flutter** | `ValueNotifier<T>` / controllers | yes, generic | `ValueListenable<T>` | app / provider packages |
| **SwiftUI** | `Binding<V>` — the whole framework is HasValue | yes, generic | two-way binding | the binding *is* the mapping |

**Findings.**

1. **Statically-typed frameworks converge on a generic value seam**
   (Vaadin `HasValue`, SwiftUI `Binding`, Flutter `ValueNotifier<T>`).
   The generic is the price static typing charges for a *uniform* value
   API — you either pay it or you have Swing (no uniform seam at all).
2. **Dynamically-typed frameworks skip the generic entirely** and just
   have a `value` attribute of whatever type (Textual, React). They get
   the uniform seam *and* typed values for the price a static framework
   pays only for the seam. **Ruby is in this camp** — this is the crux.
3. **Everyone puts model-mapping in a layer above the field**
   (Binder/Converter, Formik, ViewModel). No mature toolkit conflates
   "the field's value" with "the domain model's property." The field
   holds its natural presentation-adjacent value; a binder converts.
4. **Text fields are near-universally String-valued**; numeric/date/
   select fields hold their natural type. Nobody makes DatePicker
   String-valued and nobody makes TextField Date-valued. "String-only
   everywhere" is a position *no surveyed toolkit actually holds.*

## The reconciliation with `TextInput#text` (the flagged tension)

The worry: introducing `value` gives TextField two value-ish APIs
(`text` *and* `value`, `on_change` *and* `on_value_change`) — the exact
smell CLAUDE.md warns about.

It resolves the same way the Vaadin survey suggests: **a text field's
value simply *is* its text.** `text` is String; `String` is TextField's
natural `V`. So `HasValue#value` on a text component is not a second
piece of state — it's a delegating alias over the one buffer:

```ruby
def value = text          # value reads the buffer
def value=(v) = self.text = v.to_s
```

`text` stays as the domain-natural name (a text editor's contents *are*
"text," and reads better than "value" in every call site that edits
prose); `value` is the *uniform seam name* a Binder/Form will reach for
polymorphically across a form of mixed field types. This is a "tiny,
load-bearing restatement" (two one-line aliases), not duplicated state —
the kind the docs rules explicitly bless. It also exactly mirrors the
TextField/TextArea reconciliation from the background-inheritance work
(`DECISIONS.md` `D-bg-inherit`): the inherent-behavior widget keeps its
own semantics and the shared abstraction falls out for free, no
special-casing.

(The one genuine wart: `on_change` vs. `on_value_change`. Options: keep
`on_change` as the text-flavored alias; or migrate to `on_value_change`
and drop `on_change`; or don't add `HasValue` listeners to text
components at all until a Form needs them. Lean: keep `on_change`,
**don't** add a duplicate listener yet — see "How far now," below.)

## What `HasValue` should be *in Ruby* (if we adopt it)

A thin mixin, **much smaller than Vaadin's**, because most of Vaadin's
surface answers problems Tuile doesn't have yet:

Keep (the irreducible core):
- `value` / `value=` — get/set the held value.
- `on_value_change` — a listener. Payload: **just the new value**, to
  match `on_change`'s existing shape; add old-value / from-client only
  when a Binder proves it needs them (Vaadin needs `isFromClient` for
  loop-prevention — a Binder concern, and Tuile is single-threaded so
  there's no thread dimension to it either).
- `empty?` / `clear` — Vaadin's `getEmptyValue`/`isEmpty`/`clear`,
  collapsed. `empty?` is `value == empty_value` (nil for most).

Defer (add with Forms/Binder, not now):
- `read_only` — a form/display concern; no consumer yet.
- required-indicator — pure form chrome.
- `isFromClient` on the event — Binder loop-prevention; no Binder yet.
- Converters/validators — the Binder layer, explicitly out of scope.

Adopting it is a *convention* first (name the methods, duck-typed) and a
`module HasValue` second (only once ≥2 components share real code — per
CLAUDE.md, inherit/mixin to *be* the thing, not to pre-share a shell).

## ComboBox under this model

ComboBox is a **generic** component (like `Grid<T>`), not a domain one —
it doesn't own a domain, so per the COP rule it externalizes rendering
via an injected strategy and holds a typed value:

- `items=` — `Array<T>` (the candidate set).
- `item_label` — `->(item) { item.to_s }`, default; renders an item to
  the `String`/`StyledString` shown in the list and the field. This *is*
  the "renderer machinery," and it's one proc.
- `value` — the selected `T` (or `nil` = empty). **Typed**, not the
  display string. This is the payoff: a ComboBox over `Person` objects
  hands you back a `Person`, not `"Alice Smith"` you have to re-resolve
  (and which breaks the moment two people share a name).
- Internals: the field shows `item_label.(value)`; typing filters
  `items` by label; `List#on_item_chosen` sets `value = items[idx]`.

`allow_custom_value` (Vaadin's escape hatch for "the typed text isn't in
the list") is deferred — it reintroduces the String/T tension at the
value boundary (a custom value is a `String`, not a `T`), and no use case
needs it yet.

## Recommendation — lean: typed `value`, thin `HasValue`, String is just T=String

**Go typed.** The String-only path is a Java-shaped economy that doesn't
price out in Ruby: we'd trade away DatePicker/IntegerField/ComboBox
ergonomics (and re-resolution bugs) to avoid a `->(x){x.to_s}` default.
No surveyed toolkit actually holds "String everywhere," and the dynamic
ones (our camp) get typed values *for free*.

Concretely:
1. Adopt `value` / `value=` / `empty?` / `clear` as the **uniform seam**
   name for input components. Text components get it as a delegating
   alias over `text` (String is their natural `V`); ComboBox holds a
   typed `T`.
2. Keep it **thin** — defer read-only, required-indicator, event
   old-value/from-client, and all converter/validator machinery to the
   Forms/Binder work. Model-mapping is a *layer above the field*
   (universal in the survey), not field state.
3. ComboBox takes `items=` + an `item_label` strategy and exposes a
   typed `value` — the COP generic-component shape.

**Fallback:** String-only ComboBox (value = displayed string) *iff* we
decide even the one-proc renderer + typed ivar is more than the first
ComboBox should carry. It's a weak stop: it fails the "pick a `Person`,
get a `Person`" case that's the whole reason to prefer a component over
`List` + a lookup hash, and it bakes a String assumption that
IntegerField/DatePicker will have to fight later.

## How far to go *now* (scope discipline)

Don't build the whole `HasValue` mixin speculatively — that's a Forms
project. Minimum viable this session/PR:

- Give **ComboBox** a typed `value` / `value=` / `on_value_change` +
  `items=` + `item_label`. This is the first real consumer; let it prove
  the shape.
- Add the `value`/`value=` **alias** to `TextInput` *only if* it's a
  genuine one-liner and something consumes it; otherwise leave `text`
  alone and let ComboBox stand up the vocabulary. Do **not** add a
  duplicate `on_value_change` to text components yet.
- Extract a `module HasValue` **only when** the second typed component
  (IntegerField) lands and there's actual shared code — not before.

That keeps this idea note's *decision* (typed, thin, seam-named `value`)
cheap to honor now and cheap to grow into a Form later.

## Open questions

1. **Listener payload.** New value only (match `on_change`), or
   `(old, new)`? Lean new-only until a Binder needs the delta.
2. **`text` vs `value` naming long-term.** Alias forever, or migrate
   text components onto `value` and retire `text`? Lean: keep both,
   `text` is more readable for prose editors. Revisit if the redundancy
   bites.
3. **Where does a Converter live** when Forms arrive — on the field
   (Vaadin lets a field carry one) or purely in the Binder (cleaner
   separation)? Punt; note it so the Form design remembers the survey's
   verdict (mapping is a layer above).
4. **Empty value.** Is `nil` always the empty value, or per-component
   (Vaadin lets `IntegerField` choose)? Lean `nil` default, overridable.

## Graduation (when implemented + stable)

Per AGENTS.md: reader-half → book (a "values & the input seam" note,
probably alongside whatever chapter Forms eventually earns);
invariant-half → AGENTS.md (the "text components' value *is* their text;
ComboBox is typed; model-mapping is a layer above the field, never field
state" rule); decision-half → DECISIONS.md (`D-has-value`: typed value
over String-only, thin over Vaadin-complete, and *why* the Java
machinery fear doesn't port to Ruby). Retire this file and fold the
ComboBox specifics back into a fleshed-out `combobox.md` → its own
graduation.
