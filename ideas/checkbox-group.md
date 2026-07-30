# Checkbox Group

**Status:** not started. Batch-1 field component (see
`ideas/new-components.md`). Reads as `radio-group` with a multi-valued
value — file them together; `checkbox` is built (glyph/caption vocabulary
settled), and the compose-a-`List` call is now settled *here* (see below),
so which of the two groups gets built first is an open scheduling call, not
a design dependency.

**Read `DECISIONS.md` `D-boolean-fields` before starting** — it owns the glyph
and caption rulings this component inherits. It also carries the settled but
**unbuilt tri-state (indeterminate) shape for `Checkbox`**, and this
component's *group header* is its first plausible consumer: a header over a
partially-selected group is the whole use case tri-state was deferred for. If
you build a header here, build the flag with it (and graduate that paragraph
of the entry from settled to implemented).

## What it is

Multi-select from a small set of typed items:

```
[x] Errors
[ ] Warnings
[x] Info
```

Arrows move a cursor, **Space toggles the row under the cursor** — so
unlike `radio-group`, cursor and selection are genuinely two pieces of
state here. That difference is the whole reason the two components can't
be one. Enter and a click toggle too (see below); they are the composed
`List`'s "choose the item under the cursor", inherited rather than designed.

## Shape

`Component::CheckboxGroup < Component`, `include HasValue`, same strategy
pair as `radio-group` / {Tuile::Component::ComboBox}:

```ruby
cg = Component::CheckboxGroup.new(items: %w[Errors Warnings Info])
cg.item_label = ->(item) { item.name }   # default :to_s
cg.value                                  # => Set["Errors", "Info"]
cg.on_value_change = ->(set) { ... }
```

- `value` — a **frozen `Set` of the selected items themselves** (not of
  indices; settled 2026-07-30, see below). `Set` (not `Array`) because the
  selection is order-insensitive, and `Set#==` then makes `HasValue#value=`'s
  no-op detection mean the right thing. It's available without a `require` on
  our `>= 3.3` floor, and `Screen` already uses it.
- `empty_value` — a frozen empty `Set` **constant**, so `empty?`/`clear` work.
  (`Set.new == Set.new` is true, so a constant isn't needed for correctness —
  it just avoids allocating on every `empty?`.)
- `items=`, `item_label=` — as in `radio-group`.

### `items` is chrome; `value` is authoritative and independent

**Settled 2026-07-30.** `items` controls only what is *presented*; `value`
holds whatever the app set, whether or not those items are in `items`. If a
selected item isn't present, no row renders checked — and the value still
holds it, so a form saved without the user touching anything changes nothing
silently. Keeping the two in sync is the app's job.

This is **not a new decision — it's exactly what {Tuile::Component::ComboBox}
already does**, generalized from one item to a set. `ComboBox#value=`
(`combo_box.rb:88`) stores the object via `super` into `HasValue`'s ivar, its
`items=` (`:67`) never touches the value, and its rdoc says verbatim *"The
value need not be in `#items`."* The index in `D-combobox`'s identity rule is
**transient resolution at commit time** (`commit(index)` → `@filtered[index]`
→ object), never storage. Here `on_item_chosen(idx, _line)` → `items[idx]` →
add/remove plays exactly the role of `commit`.

What this shape *deletes*, which is the main argument for it: there is no
re-map on `items=`, so no clamp-vs-remap-vs-clear choice, no "does `items=`
fire `on_value_change`?" (it cannot — it never touches the value), and no
raise-vs-silent-drop for an out-of-range assignment (nothing is out of
range). `items=` rebuilds `lines=` and stops. `value=` before items have
loaded just works.

Rendering asks `value.include?(items[i])` per row — O(1), and the reason the
duplicate-*label* case below still behaves.

**Accepted limitation: items need stable `hash`/`eql?`.** `Set` is
Hash-backed, so an item mutated after insertion becomes unfindable. An index
set had no such requirement; this does. Vaadin's `CheckboxGroup` carries the
identical constraint via `HashSet`, so it's conventional — but it's an rdoc
sentence, not a silent assumption.

**Duplicates split into two cases, and only one collapses.** Duplicate
**labels** (distinct objects whose `item_label` renders the same string) stay
distinct `Set` members and toggle independently — that's the `D-combobox`
regression, preserved. Duplicate **items** (genuinely `==`-equal, hence
indistinguishable) collapse: toggling one checks both rows. No user intent is
lost, since nothing could have told them apart. Spec both, so the line between
them is visible to the next reader.

### `Set` order is toggle history — document "unordered" and mean it

Ruby's `Set` is Hash-backed and therefore *insertion*-ordered, and a
delete-then-re-add moves the element to the **end** (verified on 3.3.11:
`zebra, apple, mango`, delete `apple`, re-add → `["zebra", "mango", "apple"]`).
So `value`'s iteration order is the user's **toggle history**, not `items`
order. An app that wants `items` order must write `items & value.to_a` and
never iterate `value` directly. (Ruby 3.5 makes `Set` a C core class, still
Hash-backed and insertion-ordered; nothing here depends on it either way.)

### The in-place-mutation trap becomes structural

`HasValue#value=` opens with `return if value == new_value`. A toggle that
mutated the stored `Set` in place and then re-assigned it would compare the
object with itself, find them equal, and **silently swallow the event**. With
item sets there is no code path that *could*: `Set#+` and `Set#-` return new
sets, so the toggle is one expression —

```ruby
self.value = value.include?(item) ? value - [item] : value + [item]
```

— and the `value=` override freezes what it stores. It stays worth an rdoc
sentence for the *caller's* sake: `value` returns a frozen set precisely so
`cg.value << item` fails loudly instead of losing an event.

### `value=` coerces, *then* compares

The override does `Set.new(enumerable).freeze` and only then calls `super`, so
`cg.value = %w[Errors Info]` works and the no-op guard compares Set-to-Set.
Coercing *after* the guard would leave `HasValue#value=` comparing an `Array`
against a `Set`, finding them unequal, and firing spuriously. Precedent:
`Checkbox#value=` coerces the same way (`D-boolean-fields`). `Set.new(arg)`
also gives the defensive copy for free — it doesn't alias the caller's set, so
`s = Set["a"]; cg.value = s; s << "b"` can't reach in.

## Rendering

`[x] `/`[ ] ` prefixes from `checkbox` (ASCII for the font-coverage and
glyph-bleed reasons recorded there — *not*, as this note previously said,
a width-ambiguity one: `☑` is EAW-Neutral) plus the item label:
`StyledString.plain("[x] ") + label`.

Those literals are a **documented convention, not shared constants**
(decided 2026-07-30; `DECISIONS.md` `D-boolean-fields`): repeat them here and
point the rdoc at Checkbox's house-style sentence rather than referencing a
`Checkbox::CHECKED`. Drift shows up as a `region_text` spec mismatch, and
promoting them to constants later is additive if it ever bites.

Two highlights coexist and must stay distinguishable: the **cursor** row
(where Space lands) and the **checked** rows (`[x]`). Let the checkmark
carry "checked" and `theme.active_bg_color` carry "cursor" — i.e. don't
also tint checked rows, or a checked cursor row becomes unreadable. Read
the theme at paint time; paint through
{Tuile::Component#draw_line} (camp 2 — no input well, so ancestor
`bg_color` must show through).

## Compose a `List`

**Settled 2026-07-30: compose a plain {Tuile::Component::List}, as-is** — no
subclass, no key forwarding, no suppressions. Cursor and scrolling come free,
and List's cursor model (`Cursor` position, `on_cursor_changed`, mouse
hit-testing, scrolling) is *exactly* the cursor-distinct-from-selection
structure this component needs; a checkbox group is also more likely than a
radio group to be long enough to scroll. The wiring is four lines:

- `lines=` rebuilt on any change to items / labels / the selected set,
- List's cursor is our cursor (no mirroring of selection into it),
- our `handle_key` claims **Space** only. Space is not a List key, so the
  focused List declines it and it bubbles *up* to us — this is the ladder's
  normal delivery, **not** downward delegation (which AGENTS.md forbids; the
  earlier draft of this note described it backwards),
- `on_item_chosen` toggles at the reported index. That one hook covers **both**
  Enter and a left click (`list.rb:209` and `:264`), so there is no
  `handle_mouse` override at all.

Two rulings from `D-boolean-fields` were relaxed on 2026-07-30 to let this
shape work; both are recorded there, inline, with reasoning.

- **Enter may toggle.** The entry used to promise Enter stays unhandled so a
  form's submit bubbles past a checkbox. Withdrawn — no widget owes that
  (`TextArea`/`Button` claim Enter). Without the withdrawal, `List#handle_key`
  claiming Enter whenever the cursor is on an item would have forced this
  component onto the `ListDropdown::Menu` shape — non-focusable `List` subclass
  plus hand-forwarded movement keys — to protect a guarantee nothing used.
- **A click anywhere on the row toggles.** The extent rule (a standalone
  one-row field ignores clicks on its blank tail) is scoped to standalone
  widgets: with a cursor visible and rows stacked, the user aims at a *row*,
  and a row's affordance is its full width. The vertical half still holds and
  needs no code — List fires `on_item_chosen` only for `line < @lines.size`, so
  a click below the last row toggles nothing.

Decide `radio-group` on its own merits — the old "if one retreats, both
retreat" clause is dropped, since composition's case is strong here (cursor ≠
selection, scrolling likely) and weak there (three rows, scrolling is dead
weight).

Tab stops: wrapper not a stop, inner `List` is — the invariant from
AGENTS.md, and unchanged by the above (focus stays in the List).

## Open questions

- **Select-all / clear-all keys?** `Ctrl+A` / `Ctrl+D` are tempting but
  `Ctrl+D` is a List scroll key and `Ctrl+A` is HOME-ish in readline
  terms. Leave them out of v1; an app can call `value=` itself.
- **`Set` vs `Array` on the public face** — settled as `Set`, contract
  "unordered"; see the toggle-history section above for why that contract is
  load-bearing rather than pedantic. Revisit only if a real consumer complains.
- Should toggling fire once per key, or should we coalesce? Once per key
  — no batching machinery.
- `MultiSelectComboBox` (tier 2) will want this component's selected-set
  semantics; keep the set bookkeeping factorable, but **don't** build a shared
  base speculatively (COP: duplicate rather than fold shallow commonality).
  Note it inherits the items-are-chrome rule for free, since it's the same rule
  `ComboBox` already follows.

## Specs

`spec/tuile/component/checkbox_group_spec.rb`. Cover: initial value is an
empty `Set`; Space toggles the cursor row on and off, firing
`on_value_change` once per toggle with a `Set`; the returned `Set` is
frozen; `value=` accepts a plain `Array` and stores a frozen `Set`; `value=`
selects the matching rows; arrows move the cursor *without* firing
`on_value_change`; Enter toggles the cursor row; **a click far right of the
label toggles** (the relaxed horizontal rule) but **a click below the last row
does not** (the retained vertical one); duplicate *labels* toggle
independently (the `D-combobox` regression) while duplicate `==`-equal *items*
toggle together (intended); **`items=` leaves `value` untouched and fires no
`on_value_change`**, and a value holding an item absent from `items` renders no
checked row while surviving intact; mutating the `Set` a caller passed to
`value=` doesn't reach in; rendered rows via `buffer.region_text(rect)`;
ancestor `bg_color` inheritance.

## Graduation

Sampler pane (a checkbox group filtering an adjacent log/list — the
Errors/Warnings/Info shape above is the natural demo); book ch7 section;
AGENTS.md class index line. Three things are real invariants rather than
rationale, so they graduate into the component's rdoc and AGENTS.md, not just
the book: the **`Set`-and-frozen / no-in-place-mutation** rule, the
**items-are-chrome / value-survives** rule (stated once for `ComboBox` *and*
this component, since it's one rule with two instances), and the **coerce-then-
compare** ordering in `value=`. A `DECISIONS.md` entry is warranted for the
composed-a-`List` shape; the items-are-chrome half belongs as an amendment to
`D-combobox`, which is where the singular version of it already lives, rather
than as a second competing home.
