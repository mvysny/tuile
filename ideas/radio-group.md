# Radio Group

**Status:** not started. Batch-1 field component (see
`ideas/new-components.md`). Depends on nothing, but shares its items /
`item_label` vocabulary with {Tuile::Component::ComboBox} and its
rendering approach with `checkbox-group` — decide those two together.

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

- `items=` — `Array` of anything; replacing it resets/clamps the
  selection.
- `item_label=` — `item -> String | StyledString`, default `:to_s`.
  (Generic component ⇒ externalized rendering strategy, per COP.)
- Internally track the **selected index**, not the object, so identity
  survives duplicate labels — the exact reasoning `D-combobox` records.
  `value=` maps object → index via `items.index(v)`; `value = nil` (and
  an unknown object) clears the selection.

## Selection == cursor (the one real design call)

In a TUI radio group the conventional behavior is that Up/Down move the
*selection directly* — there is no separate cursor to "commit" with
Space, the way {Tuile::Component::List} has a cursor distinct from
`on_item_chosen`. Adopt that: **no dual state.** Space and Enter then
select the row under the cursor, which is already selected, i.e. they're
harmless no-ops kept for muscle memory.

This is the sharpest contrast with `checkbox-group`, where cursor and
selection genuinely *are* two things. Both files should say so.

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

**The fallback, if composition fights us.** A radio group is *small by
nature* — that's why you pick one over a ComboBox — so the scrolling
machinery is mostly dead weight, and `List` brings key handling we don't
want (its incremental-search keys, `on_item_chosen`, PgUp/PgDn over a
3-row group). Painting three rows in `repaint` is ~15 lines. So if the
`List` route turns into a pile of suppressions, retreat to
`RadioGroup < Component` painting its own rows via `draw_line` (camp 2,
same as `checkbox`) — and say so here rather than pushing through.

Whichever way it lands, both group components match: `checkbox-group`
carries the same proposal.

## Painting

Either route paints through {Tuile::Component#draw_line} so an ancestor
`bg_color` is inherited (camp 2 — no input well here). Glyphs `(•)`/`( )`
— U+2022 BULLET is East-Asian-Ambiguous, so it is double-wide in a CJK
locale; if that bites, fall back to `(*)`/`( )` ASCII.

**Open: default to `(*)` instead?** (raised 2026-07-30.) Bullet's
ambiguity is the real *cell-count* hazard — the group's rows would each
mis-measure by a column in an ambiguous-wide terminal — and
`password-field` already ruled the same way for the same character,
defaulting `mask_char` to `*` and keeping `•` as a knob. `checkbox` does
**not** hit this: `☑` is EAW-Neutral, and its problem is font coverage plus
glyph bleed (see the corrected note there). So of the batch it's this
component, not `checkbox`, that carries a genuine width risk — which argues
for ASCII by default here too, and a `glyphs=` knob for `•`.

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
unknown object clears; **duplicate labels** — selecting the second of two
equal-labeled items keeps that index (the identity regression from
`D-combobox`); `items=` clamps a now-out-of-range selection; the rendered
rows via `buffer.region_text(rect)`; ancestor `bg_color` inheritance.

## Graduation

Sampler pane (a radio group driving something visible — sort order of an
adjacent list); book ch7 section; AGENTS.md class index line. A
`DECISIONS.md` entry **is** warranted if we go the compose-a-`List`
route: it extends the composed-field taxonomy from "field composes a
`TextField`" to "field composes any widget", which is exactly the kind of
thing `D-integer-field` exists to record.
