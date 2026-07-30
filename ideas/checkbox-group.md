# Checkbox Group

**Status:** not started. Batch-1 field component (see
`ideas/new-components.md`). Reads as `radio-group` with a multi-valued
value — file them together, build `checkbox` first for the glyph/caption
vocabulary and `radio-group` first for the compose-a-`List`-or-not call.

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
be one.

## Shape

`Component::CheckboxGroup < Component`, `include HasValue`, same strategy
pair as `radio-group` / {Tuile::Component::ComboBox}:

```ruby
cg = Component::CheckboxGroup.new(items: %w[Errors Warnings Info])
cg.item_label = ->(item) { item.name }   # default :to_s
cg.value                                  # => Set["Errors", "Info"]
cg.on_value_change = ->(set) { ... }
```

- `value` — a **`Set`** of selected items. `Set` (not `Array`) because
  the selection is order-insensitive, and `Set#==` then makes
  `HasValue#value=`'s no-op detection mean the right thing. It's
  available without a `require` on our `>= 3.3` floor, and `Screen`
  already uses it.
- `empty_value` — a frozen empty `Set`, so `empty?`/`clear` work.
- Internally track selected **indices** (a `Set<Integer>`), mapping to
  items on read — the duplicate-label identity rule from `D-combobox`
  again.
- `items=`, `item_label=` — as in `radio-group`.

### The in-place-mutation trap (write this in the rdoc)

`HasValue#value=` opens with `return if value == new_value`. If a toggle
mutated the stored `Set` in place and then re-assigned it, the guard
would compare the object with itself, find them equal, and **silently
swallow the event**. So every toggle must build a **new frozen `Set`** and
assign that. Same trap for a caller doing `cg.value << item` — document
that `value` returns a frozen set precisely so that fails loudly instead
of losing an event.

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

**First proposal (agreed 2026-07-25), same as `radio-group`: compose one**
— cursor and scrolling for free. Open to brainstorming, but here the case
is even stronger than for `radio-group`: List's cursor model (`Cursor` position, `on_cursor_changed`,
mouse hit-testing, scrolling) is *exactly* the cursor-distinct-from-
selection structure this component needs, and a checkbox group is more
likely than a radio group to be long enough to scroll. The wiring:

- `lines=` rebuilt on any change to items / labels / the selected set,
- List's cursor is our cursor (no mirroring of selection into it),
- our `handle_key` claims **Space** and toggles at `list.cursor.position`,
  letting everything else fall through to the List,
- a click needs care: List's own mouse handling moves the cursor; we want
  a click on a row to *also* toggle it (that's what a user expects from a
  checkbox). So intercept the click, or toggle on the resulting
  cursor-changed — decide when writing it. Simplest: override
  `handle_mouse`, call `super` (cursor moves), then toggle if the click
  landed inside `rect`.

Match `radio-group`: if composition gets retreated from there, retreat
here too (that file carries the fallback).

Tab stops: wrapper not a stop, inner `List` is — the invariant from
AGENTS.md.

## Open questions

- **Select-all / clear-all keys?** `Ctrl+A` / `Ctrl+D` are tempting but
  `Ctrl+D` is a List scroll key and `Ctrl+A` is HOME-ish in readline
  terms. Leave them out of v1; an app can call `value=` itself.
- **`Set` vs `Array` on the public face.** If a consumer wants
  deterministic order they'd want `Array` (in `items` order). `Set`
  preserves insertion order in Ruby anyway, but the *documented* contract
  should be "unordered". Revisit only if a real consumer complains.
- Should toggling fire once per key, or should we coalesce? Once per key
  — no batching machinery.
- `MultiSelectComboBox` (tier 2) will want this component's selected-set
  semantics; keep the index-set bookkeeping factorable, but **don't**
  build a shared base speculatively (COP: duplicate rather than fold
  shallow commonality).

## Specs

`spec/tuile/component/checkbox_group_spec.rb`. Cover: initial value is an
empty `Set`; Space toggles the cursor row on and off, firing
`on_value_change` once per toggle with a `Set`; the returned `Set` is
frozen; `value=` selects the matching rows; arrows move the cursor
*without* firing `on_value_change`; a click toggles; duplicate labels
toggle independently; `items=` drops selections that no longer exist;
rendered rows via `buffer.region_text(rect)`; ancestor `bg_color`
inheritance.

## Graduation

Sampler pane (a checkbox group filtering an adjacent log/list — the
Errors/Warnings/Info shape above is the natural demo); book ch7 section;
AGENTS.md class index line. The `Set`-and-frozen / no-in-place-mutation
rule is a real invariant: it belongs in the component's rdoc, and — if we
also record the `radio-group` composition decision — in the same
`DECISIONS.md` entry.
