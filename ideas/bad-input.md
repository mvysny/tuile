# Bad input — the deferred half: the push notice and the blur it needs

**Status:** **v1 shipped and graduated, 2026-09-03.** The pull —
`Component::HasBadInput#bad_input_message` / `#bad_input?`, included by
`IntegerField`, `FloatField` and `BigDecimalField` — is in, and everything
settled about it now lives in its durable homes: **`D_bad_input`** (the
decision, the population test, the roads not taken), **book ch7 "Reporting bad
input"** (the user-facing half), **AGENTS.md** (the one cross-file invariant),
and the mixin's own rdoc. `D_input_filters` owns the complementary half —
prevent where the grammar is prefix-closed, report where it is not. Read
`D_bad_input` first; this file is now only what did **not** ship.

Three things remain, and they are one thing in three parts: **the push notice
has no consumer yet, the consumer it is waiting for needs a settling rule, and
settling needs a commit point Tuile does not have.** None is blocking; the save
gate works on the pull alone.

## 1. The push — `on_bad_input_change`

The shape, if it lands, and the reason it did not:

```ruby
attr_accessor :on_bad_input_change   # 1-arg: the new message-or-nil
protected
def sync_bad_input                   # the sole writer of the edge trigger
```

- **What it buys, and only it can:** the silent transitions. Typing `-` into a
  blank field moves the buffer and not the value, so `on_value_change` is
  correctly silent and *nothing* announces that the field went bad. A consumer
  that must react between clicks — an error ink, a live status row — has no
  other channel. A consumer that is only ever *asked* does not need it.
- **It brings the design's only ivar.** The pull is derived and stores nothing;
  an edge trigger has to remember the last status it fired. That is
  `IntegerField#fire_if_changed`'s `@last_value` shape, and the writer
  discipline is `ProgressBar#sync_ticker`'s: **one idempotent sync, the sole
  writer, called from every input mutation and derived from the invariant**,
  never toggled by whichever event happened to notice.
- **The AGENTS.md line it would owe** (it clears the gate; the pull's did not):
  *a field that parses owes `sync_bad_input` on every input mutation, or its
  bad-input status goes stale with nothing in the diff to notice.* A **new**
  field breaks that from its own file.
- **The spec that would define it:** input `""` → `"-"` fires a bad-input
  notice while `on_value_change` stays silent. (The pull's version of that spec
  is already in `integer_field_spec`, asserting the silence and the pull.)

## 2. `on_blur` — the commit point Tuile lacks

`D_integer_field` already recorded this gap once, in a different consumer, when
it declined to canonicalize `"007"`: *"canonicalizing needs a blur/commit point
a TUI lacks."* Same missing thing, second consumer.

- **Enter is not enough.** `TextField#on_enter` exists and is what Vaadin uses,
  but Tab is unconditional (rung 1 of the key ladder, `D_key_dispatch`), so
  tabbing out of a broken field is the *likely* path, not the exotic one.
- **Blur does not exist, and is nearly free.** `Screen#focused=` already holds
  `previous` and already diffs it to fire `@on_focus_changed`, so a protected
  `on_blur` is one line at that single existing site, reached via `__send__`
  (`D_hook_visibility`) and inheriting the edge-trigger properties
  `D_attach_hooks` demands.
- **What it must not assume, written down before it ships:** it fires during the
  popup-close focus repair and during `Screen#close`, and the component may be
  *detached* by then — so a blur handler that invalidates is a silent no-op,
  exactly as in `on_detached`.
- Note `ideas/hover.md` records the same `on_focus`-without-a-counterpart
  asymmetry from the other side.

## 3. The measurement nobody has taken

Wire `on_bad_input_change` to a status `Label` with **no** settling and type
`-0.5` into a `FloatField`. That is the flicker `D_bad_input`'s
"the fact is continuous, the consumers settle" ruling rests on, and it has been
reasoned about but never observed. It is
`ideas/caption-and-error-ownership.md`'s input — take the number there, since
that note owes the settling rule that reads it.

## Related

`D_bad_input` (**the entry this note graduated into** — read it first),
`D_input_filters` (the complement: prevent where prefix-closed, report where
not), `ideas/caption-and-error-ownership.md` (the ink, its settling rule, and
the `HasValidation` question — the file that unblocks all three items above),
`ideas/binder.md` (the consumer that needs only the pull: a Save gate asked at
the click), `ideas/date-picker.md` (the first field whose residue prevention
cannot shrink; it already holds the format, mask and no-text-input options this
note used to carry), `ideas/hover.md` (the `on_focus`/no-`on_blur` asymmetry),
`D_attach_hooks` (the edge-trigger shape `on_blur` must copy),
`D_hook_visibility` (a framework-invoked hook is protected, via `__send__`),
`D_progress_bar` (`sync_ticker`: one idempotent sync, the sole writer),
`D_key_dispatch` (Tab is unconditional, which is why Enter-only settling leaks).
