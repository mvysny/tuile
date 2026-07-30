# Radio Group

**Status:** not started. Batch-1 field component (see
`ideas/new-components.md`). Depends on nothing, but shares its items /
`item_label` vocabulary with {Tuile::Component::ComboBox}. The sibling
`CheckboxGroup` is now **built** — read `DECISIONS.md` `D-checkbox-group`
before starting, it settled most of the shared vocabulary (and deliberately
left this component's composition question open).

## What it is

Single-select from a small, fully-visible set of typed items:

```
(•) Ascending
( ) Descending
( ) Unsorted
```

`value` is the **selected item** (of whatever type `items` holds), never
its label — same rule as ComboBox (`D-combobox`, `D-has-value`).

## Shape

`Component::RadioGroup < Component`, `include HasValue`, with the
ComboBox strategy pair:

```ruby
rg = Component::RadioGroup.new(items: %w[Ascending Descending Unsorted])
rg.item_label = ->(item) { item.name }   # default :to_s
rg.value                                  # => the selected item, or nil
rg.on_value_change = ->(item) { ... }
```

- `items=` — `Array` of anything; **chrome only, it does not touch `value`**
  (revised 2026-07-30 — it previously said "resets/clamps the selection").
- `item_label=` — `item -> String | StyledString`, default `:to_s`.
  (Generic component ⇒ externalized rendering strategy, per COP.)
- **Store the selected object, not an index** (revised 2026-07-30; this note
  previously said the opposite, and was the file out of step with the
  code). `ComboBox` stores the object and its rdoc states *"The value need not
  be in `#items`"*; the index in `D-combobox`'s identity rule is transient
  *resolution* at commit time (`@filtered[index]` → object), not storage. So an
  object absent from `items` **does not clear** — no row renders selected and
  the value survives, which is what keeps a form saved without edits from
  changing anything silently. `value = nil` is the only thing that clears.
  Duplicate *labels* still resolve correctly because a click/Enter resolves by
  row index at that moment. `D-checkbox-group` carries the set-valued
  generalization of the same rule.

## Selection == cursor (the one real design call)

In a TUI radio group the conventional behavior is that Up/Down move the
*selection directly* — there is no separate cursor to "commit" with
Space, the way {Tuile::Component::List} has a cursor distinct from
`on_item_chosen`. Adopt that: **no dual state.** Space and Enter then
select the row under the cursor, which is already selected, i.e. they're
harmless no-ops kept for muscle memory — and via the `List` route Enter's
no-op comes free, since `on_item_chosen` would re-select what's selected.

This is the sharpest contrast with the built `CheckboxGroup`, where cursor
and selection genuinely *are* two things — which is why composing a `List` was
the obvious call there and is a real question here.

## Build on `List`, or paint rows directly?

**First proposal (agreed 2026-07-25): compose a
{Tuile::Component::List}** — the cursor and scrolling come for free.
Still open to brainstorming if it turns out to fight the host; the
paint-your-own-rows fallback below stays on the table until the code
exists.

`RadioGroup` holds one via {Tuile::Component::HasContent}, exactly the composed-field
shape `D-integer-field` blessed (`ComboBox`/`IntegerField` hold a
`TextField`; this holds a `List`). What that buys, for free:

- scrolling + the scrollbar when the group is taller than its rect,
- mouse hit-testing per row,
- the themed cursor-row highlight,
- `on_cursor_changed` → the hook that fires our `on_value_change`.

The wiring: `lines=` gets the rendered rows, rebuilt whenever `items`,
`item_label`, or the selection changes; `cursor=` mirrors the selection;
`on_cursor_changed` writes the value back. Row text is
`StyledString.plain("(•) ") + label` — {Tuile::StyledString#+} exists and
accepts a `String` on the right, so a `StyledString` label keeps its
spans.

Tab-stop bookkeeping follows the invariant: the wrapper is **not** a tab
stop (inherit `Component`'s `false`), the inner `List` is (it already
returns `true`). `HasContent#on_focus` forwards focus down.

**Update 2026-07-30:** `CheckboxGroup` shipped composing a plain `List`
as-is (`on_item_chosen` covers Enter+click), and the old "if one retreats, both
retreat" clause between the two notes is **dropped** — `D-checkbox-group`
records why the case genuinely differs: cursor ≠ selection and likely
scrolling there, three rows and no scrolling here. Decide this one on the
merits below. Two gotchas that cost time there and apply either way: a bare
`List` has `Cursor::None` at position -1 (install `List::Cursor.new` or arrows
and Enter are silently dead), and `List` pads a one-column gutter, so rows
paint at `rect.left + 1`.

**The fallback, if composition fights us.** A radio group is *small by
nature* — that's why you pick one over a ComboBox — so the scrolling
machinery is mostly dead weight, and `List` brings key handling we don't
want (PgUp/PgDn and ^U/^D over a 3-row group, plus an `on_item_chosen` that
can only re-select what's already selected). Painting three rows in `repaint`
is ~15 lines. So if the
`List` route turns into a pile of suppressions, retreat to
`RadioGroup < Component` painting its own rows via `draw_line` (camp 2,
same as `checkbox`) — and say so here rather than pushing through.

`D-checkbox-group` lists the paint-your-own route among its rejected
alternatives — rejected *for that component*, explicitly still open here.

## Painting

Either route paints through {Tuile::Component#draw_line} so an ancestor
`bg_color` is inherited (camp 2 — no input well here). Glyphs
**`(*)`/`( )` ASCII by default**, with `•` available through a `glyphs=`
knob (settled 2026-07-30 by `D-ambiguous-width`; this note previously
defaulted to `(•)`). Like `checkbox`'s `[x] `/`[ ] `, these live as a
documented convention — three columns plus a space — not as public
constants; see the glyph-home ruling in `DECISIONS.md` `D-boolean-fields`.

U+2022 BULLET is East-Asian-Ambiguous, so of the batch-1 components this is
the one carrying a genuine *cell-count* risk — every row would mis-measure
by a column in an ambiguous-wide terminal. `password-field` ruled the same
way for the same character (`mask_char` defaults to `*`), and the decision's
inventory rule generalizes it: a new component doesn't add an Ambiguous
glyph, it offers one. (`checkbox` is unaffected — `☑` is Neutral; its
problem is font coverage and glyph bleed.)

Selection highlight: the selected row gets `theme.active_bg_color` when
the group is `active?`, read at paint time. Via the List route this is
just the cursor row and comes for free — but note that then the
*selection* highlight and the *focus* highlight are the same pixel, which
is fine precisely because selection == cursor here.

## Open questions

- Left/Right as synonyms for Up/Down (some toolkits do, for horizontal
  groups)? Only matters if we ever add a horizontal orientation — Vaadin
  has one; skip it for v1.
- Should an empty `items` render nothing or a placeholder row? Nothing.
- `value = nil` (no selection) is representable — but is a radio group
  with nothing selected legitimate? Yes for v1 (it's the initial state);
  a `required` axis belongs to the deferred forms layer.

## Specs

`spec/tuile/component/radio_group_spec.rb`. Cover: initial `value` is
`nil`; Up/Down move the selection and fire `on_value_change` once per
move; `value=` with an object selects the matching row; `value=` with an
object absent from `items` selects nothing **but keeps the value**, and
`value = nil` clears; **duplicate labels** — selecting the second of two
equal-labeled items selects that one (the identity regression from
`D-combobox`); `items=` leaves `value` untouched and fires no
`on_value_change`; the rendered rows via `buffer.region_text(rect)`; ancestor
`bg_color` inheritance.

## Graduation

Sampler pane (a radio group driving something visible — sort order of an
adjacent list); book ch7 section; AGENTS.md class index line. A
`DECISIONS.md` entry **is** warranted if we go the compose-a-`List`
route: it extends the composed-field taxonomy from "field composes a
`TextField`" to "field composes any widget", which is exactly the kind of
thing `D-integer-field` exists to record.
