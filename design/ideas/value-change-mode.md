# A value-change mode — when a text field's notice fires

**Status:** proposed, nothing built; next. The Binder shipped first, against eager fields
(verdicts paint mid-word, accepted) and gains the commit-gesture cadence from this with no change of
its own — it grows no blur logic. **Reopens a written
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

Today only the third is expressible: a filter debounces by hand, and the Binder, which owns no
blur hook, paints a string or number field's verdict mid-word (`D_binder_verdicts`, accepted
until this lands).

## Proposal

A `value_change_mode` knob, on the string-ish fields only:

- **`:eager`** — every edit, today's behaviour.
- **`:commit`** — on a commit gesture: leaving the focus chain, or ENTER. `TextArea`: leaving
  only, since ENTER inserts a newline there (Vaadin's `change` event is the same).
- **`:lazy`** — once edits pause for `value_change_timeout` (Vaadin: 400 ms default, verified in
  the 25.2 text-field docs); a commit gesture releases it early.

Skip `TIMEOUT` (throttle) and `ON_BLUR` (commit minus ENTER) until someone asks.

**Named `:commit`, not Vaadin's `ON_CHANGE`.**
- **The word is already the house one.** `AbstractWrappingField#commit` runs on exactly these
  gestures, "commit gesture" is the phrase across `lib/`, `design/` and `book/`, and
  `R_value_change_timing`'s "commit notice" column is defined as Enter-or-leaving.
- **It stays true per field.** It means "this field's commit gestures", so `TextArea`'s leave-only
  set needs no caveat.
- **`:on_change` reads as its opposite** beside `on_value_change`: every change, which is `:eager`.
- **`:on_blur` is taken and wrong.** Vaadin's `ON_BLUR` excludes ENTER, so borrowing the name
  misleads anyone who knows Vaadin, and it squats the name that mode would need. It also hides
  mechanism 4's ENTER release.
- **No `on_` prefix at all**, since `on_` is reserved for listener slots. `:eager` / `:commit` /
  `:lazy` are then one kind of word.

**The default is `:commit`** (settled; Vaadin's `ON_CHANGE` default too). Eager is rarely what you
want: a form is the commonest multi-field consumer and shouldn't need the knob per field, while a
filter that stays silent until blur shows up on first use and takes one line to fix. The cost:
- a `**Breaking:**` CHANGELOG line;
- `ComboBox`'s inner field and every wrapping field's editor set `:eager` explicitly, and so does
  pikuri's prompt palette;
- specs that type and then assert on the notice owe an ENTER or a blur. There are 136
  `on_value_change` references across 16 spec files; those using `value=` / `Testing.set_value`
  are unaffected.

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
3. *"No defensible default."* `:commit`, above. The ruling's "nobody wants a search-as-you-type
   `TextField` silent until blur" still holds, but that failure is loud and fixed in one line,
   whereas an eager default makes every form paint verdicts mid-word.

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

- **`Q_lazy_timer`** — tick-and-cancel over the existing API, or a one-shot cancellable
  `EventQueue#after(seconds)` (+ its fake) that apps debouncing by hand would use too?
- **`Q_pending_flush`** — does anything outside the field need to release a held notice? Leaning
  no: the Binder's `changed?` counts user edits, which a held notice would fool (a Save *shortcut*
  leaves focus in the field), and `D_binder_verdicts` answers that with a live compare for the focused
  field, owed by this idea's graduation. `write?` / `validate` read `value` live and need nothing.
- **`Q_textarea_submit`** — a `TextArea` subclass that rebinds ENTER to submit (pikuri's prompt)
  wants ENTER to release too; is that its own override, or does the release hook follow whatever
  key the subclass claims?

## Graduation owes

- A `D_` entry on the value-change mode (the modes, the `:commit`-over-`ON_CHANGE` name, who gets them, edits-not-writes,
  held-only-while-focused, the default), and `D_date_field`'s *Why not* bullet amended to point at it rather than deleted —
  the date fields' exclusion still stands on its own grammar reason.
- `R_value_change_timing` gains the verified Vaadin facts: `ON_CHANGE` default, `LAZY`'s 400 ms.
- `lib/tuile/component/AGENTS.md`'s "One not prefix-closed settles its *value* notice" line
  re-phrased around the mixin.
- rdoc on the mixin and each includer, the `**Breaking:**` CHANGELOG line, the regenerated
  `sig/tuile.rbs`; a changed responsibility owes the root `AGENTS.md`'s four registrations.
- The Binder, built against eager fields, owes three things once this lands: `changed?` gains the
  live compare for the focused field (`D_binder_verdicts`, whose last why-not then becomes the
  answer); `D_binder_verdicts`' "Built against eager fields, accepted" sentence is rewritten; and
  the "fields fire per keystroke" cadence notes in `Binder::Buffered`'s and `Binder::Unbuffered`'s
  rdoc move to the `:commit` default.
- The book: `08-forms.md`'s "a text or number field announces every keystroke", and
  `07-components.md`'s `filter_results` example on `on_value_change`, which goes silent until blur
  under a `:commit` default and becomes the place to show `:lazy`.
