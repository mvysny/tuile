# ComboBox (skeleton — parked pending HasValue)

**Status:** placeholder so we don't forget. The interesting design work
is *not* here — it's the value model, which is spun out to
[`has-value.md`](has-value.md). Read that first; this note only records
the ComboBox-specific decisions that fall out once value is settled.

## What it is

A text field with a dropdown of candidate items: type to filter, arrow
to select, Enter to accept. Vaadin calls the filterable one `ComboBox`
and the non-filterable one `Select`; same widget minus the editable
filter. Start with the filterable one — a non-filterable `Select` is the
same assembly with the field made read-only.

## It already exists, ad-hoc

`examples/sampler.rb`'s `build_slash_demo` is a ComboBox in all but name:
a `TextArea` + a non-modal `Popup(Window(List))`, wired with `on_change`
(refill the list) + `on_key` (forward Up/Down/Enter/ESC to the list while
open) + `List#on_item_chosen` (accept). ComboBox is that assembly
*promoted to a component* so an app writes `ComboBox.new` instead of
re-deriving the six hooks. The stock hooks it's built from
({TextInput#on_key}, `show_cursor_when_inactive`, non-modal `Popup`) were
put there precisely to make this assemblable — see their rdoc.

## Compose, don't inherit (decided)

`ComboBox < Component`, holding a `TextField` child and owning a
`Popup(List)` — **not** `ComboBox < TextField`. Reasons:

- Inheriting from `TextField` nails the value to `String` and leaks
  caret/`text=`/insertion semantics ComboBox doesn't want on its public
  face. Composition lets ComboBox expose a clean `value` (of whatever
  type — the HasValue question) while delegating *editing* to the field.
- Matches the COP carve-out: subclass a framework widget only to *be*
  one concrete thing; compose for everything else (tuile skill, "Window
  frames a view"). ComboBox *is* a Component; it *has* a field.
- The user's own lean, and the right one.

## What's blocked on HasValue

Everything that matters about the public API:

- Is `value` a `String` (the displayed text) or an arbitrary item `T`?
- Does it take `items=` as domain data + an `item_label` render strategy
  (the COP "generic component externalizes rendering" shape), or just
  `Array<String>`?
- What does the change listener carry?

These are not ComboBox questions — they're the questions for *every*
future input component (IntegerField, DatePicker, …), so they're settled
once, in [`has-value.md`](has-value.md). Come back and flesh this file
out (anchoring, sizing the popup via `Popup#size=`, `allow_custom_value`,
Select variant, keyboard map) once that lands.
