# A value-change mode — when a text field's notice fires

**Status:** proposed, nothing built. A prerequisite for `binder.md`, which relies on it for the
cadence of its per-change validation instead of growing blur logic of its own. **Reopens a written
ruling**: `D_date_field`'s *Why not* bullet on "Vaadin's `ValueChangeMode` as a per-field
eager/lazy knob" (survey: `R_value_change_timing`).

## The problem

`TextField` (every `AbstractStringField`) fires `on_value_change` per keystroke, and so do the
number fields. Three consumers want three cadences:

| consumer | wants | Vaadin mode |
|---|---|---|
| a form / the Binder | a verdict when the user is done with the field, not a red well while typing the first two letters of a `length < 3` field | `ON_CHANGE` (its default) |
| a filter / search box | the query ~300–400 ms after the last keystroke, not a refetch per letter | `LAZY` |
| a slash palette, a live echo | every edit | `EAGER` |

Today only the third is expressible; a filter debounces by hand, and the Binder would have to
invent a blur hook (`Screen#on_focus_changed`) to avoid painting verdicts mid-word — which also
breaks `HasValidation`'s own rdoc ("discrete … not recomputed per keystroke").

## Proposal

A `value_change_mode` knob, Vaadin's names, on the string-ish fields only:

- **`:eager`** — every edit, today's behaviour.
- **`:on_change`** — on a commit gesture: leaving the focus chain, or ENTER. `TextArea`: leaving
  only, since ENTER inserts a newline there (Vaadin's `change` event is the same).
- **`:lazy`** — once edits pause for `value_change_timeout` (Vaadin: 400 ms default, verified in
  the 25.2 text-field docs); a commit gesture releases it early.

Skip `TIMEOUT` (throttle) and `ON_BLUR` (on-change minus ENTER) until someone asks.

**Who gets it** — Vaadin's `HasValueChangeMode` implementors, mapped: `AbstractStringField`
(`TextField`, `PasswordField`, `TextArea`), `IntegerField`, `FloatField`, `BigDecimalField`.
**Not** `DateField` / `TimeField` / `DateTimeField` — on-commit unconditionally, as Vaadin's
`DatePicker`/`TimePicker` are, because their grammar is not prefix-closed (`D_date_field`); nor
`ComboBox` (its value moves only on commit already), nor the discrete-gesture fields (`Checkbox`,
the groups, `Select`).

## Why reopening `D_date_field`'s bullet is sound

Its three objections, answered:

1. *"The knob is about a network, not semantics."* True of Vaadin's motive; Tuile's is the
   consumer's cadence — a form and a filter want different ones with no network in sight. Neither
   consumer existed when the ruling was written.
2. *"It would sit on `AbstractWrappingField` meaning noise-suppression for one subclass and
   correctness for another."* Only if it reached the date fields; it doesn't (above).
3. *"No defensible default."* Still the real call — `Q_default`.

Bonus over Vaadin: its `LAZY` lets a blur handler read the *old* value (vaadin/flow#14090,
`R_value_change_timing`). Tuile's `value` is a live parse of the buffer whatever the mode; **only
the push is held** — already the house rule for `notify_on_edit?`.

## Mechanism

1. **Gate the field's own notice; never push the mode down into a wrapped editor.** Internal
   consumers need every edit: `AbstractWrappingField#handle_editor_change` → `sync_bad_input`, and
   `ComboBox`'s refill off its field's notice. So a wrapping field pins its editor at `:eager` and
   holds back its *own* notice — with machinery it already has: `notify_on_edit?`, commit on the
   `active=` falling edge and on ENTER (`commit_and_notify`), the `@last_value` diff guard, and a
   `clear` that announces at once. The knob mostly promotes the protected `notify_on_edit?` into a
   public setting: `notify_on_edit?` becomes "mode is `:eager`", and `DateField`/`TimeField` keep
   their hardcoded `false`.
2. **Hold edits, not writes — and typing funnels through `set_value`.** `insert_text` and the
   deleting keys call `set_value(…, from_user: true)` (`abstract_string_field.rb`), the same path a
   "Today" button or `Testing.set_value` takes. The edit route needs its own internal writer that
   holds the notice; `set_value` keeps firing at once, `from_user:` either way.
3. **Held only while focused.** A notice waits only while the field is on the focus chain; leaving
   it or ENTER releases it (`from_user: true`, like every commit gesture — `D_from_user`), and a
   write to an unfocused field fires at once. Otherwise a whole-value user write to a field that
   isn't focused would wait for a blur that never comes.
4. **ENTER is released and then left to bubble**, so a scope's default button acts on an announced
   value — `AbstractWrappingField#handle_key?`'s existing contract.
5. **`:lazy` needs no new timer primitive**: a self-cancelling `EventQueue#tick`, restarted per
   edit; `FakeEventQueue#tick_once` drives it in specs. The pending ticker is a hook-owned resource
   — cancelled on release, on `set_value`, on `clear`, on detach — so it is **synced from one
   condition** (root `AGENTS.md`), not toggled from four sites. `Q_lazy_timer`.
6. **Shared code as a mixin, `HasValueChangeMode`** (Vaadin's name): the knob, its validation, the
   pending-notice diff guard and the release. Included by `AbstractStringField` and the number
   fields; not by the date fields, which keep `notify_on_edit? = false` as a fixed rule.

## Open questions

- **`Q_default`** — leaning **`:on_change`** (Vaadin's default, and the owner's read that eager is
  rarely what you want). A form is the commonest multi-field consumer and shouldn't need the knob
  per field; a filter silent until blur is obvious on first use and a one-line fix. Cost: a
  `**Breaking:**` CHANGELOG line; `ComboBox`'s inner field and every wrapping field's editor set
  `:eager` explicitly; pikuri's prompt palette sets `:eager`; specs that type and then assert on
  the notice owe an ENTER or a blur (136 `on_value_change` references across 16 spec files — those
  using `value=` / `Testing.set_value` are unaffected).
- **`Q_lazy_timer`** — tick-and-cancel over the existing API, or a one-shot cancellable
  `EventQueue#after(seconds)` (+ its fake) that apps debouncing by hand would use too?
- **`Q_pending_flush`** — does anything outside the field need to release a held notice? The
  Binder's `changed?` does if it counts user edits (a Save *shortcut* leaves focus in the field),
  unless it compares values instead — see `binder.md`. Prefer no public `flush` if the Binder can
  do without.
- **`Q_textarea_submit`** — a `TextArea` subclass that rebinds ENTER to submit (pikuri's prompt)
  wants ENTER to release too; is that its own override, or does the release hook follow whatever
  key the subclass claims?

## Graduation owes

- A `D_` entry on the value-change mode (the modes, who gets them, edits-not-writes,
  held-only-while-focused, the default), and `D_date_field`'s *Why not* bullet amended to point at it rather than deleted —
  the date fields' exclusion still stands on its own grammar reason.
- `R_value_change_timing` gains the verified Vaadin facts: `ON_CHANGE` default, `LAZY`'s 400 ms.
- `lib/tuile/component/AGENTS.md`'s "One not prefix-closed settles its *value* notice" line
  re-phrased around the mixin.
- rdoc on the mixin and each includer, the `**Breaking:**` CHANGELOG line, the regenerated
  `sig/tuile.rbs`; a changed responsibility owes the root `AGENTS.md`'s four registrations.
- `binder.md`'s cadence assumption, once both have landed.
