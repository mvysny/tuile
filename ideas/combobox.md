# ComboBox

**Status:** designed, implementation pending. The value model lives in
[`has-value.md`](has-value.md) (now SETTLED and shipped) — read that
first; ComboBox consumes {Tuile::Component::HasValue} for its typed
`value`. This note is the ComboBox-specific design.

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

## The core model: two values, never conflated

A ComboBox holds *two* value-ish things, and the whole design hinges on
keeping them distinct:

- **`combo.value`** — the committed selection, type `T`, the {HasValue}
  seam. Changes *only on commit* (Enter/click); that's the sole trigger
  of `on_value_change`. `nil` = nothing selected (`empty_value` is `nil`).
- **the embedded field's `text`** — a transient **query string**. It's
  `item_label(value)` at rest, becomes whatever you type while filtering,
  and **reverts to `item_label(value)` on ESC/blur** if nothing was
  committed. Keystrokes move the query, never the value.

The payoff over "String value + a lookup hash": selection is by list
index → `items[idx]`, so **object identity survives duplicate labels**
(two `Person`s named "Alice" resolve to the right object). That's the
whole reason `value` is typed `T`, not the display string — see
[`has-value.md`](has-value.md) "The Ruby dissolve."

## Public API

```ruby
combo = Tuile::Component::ComboBox.new
combo.items = [:red, :green, :blue]              # Array<T>
combo.item_label = ->(c) { c.to_s.capitalize }   # T -> String|StyledString; default :to_s
combo.value = :green                             # HasValue seam; field shows "Green"
combo.on_value_change = ->(v) { … }              # commit-only, receives the T
combo.clear                                      # value = nil, field blanks
```

`item_label` is the COP "generic component externalizes rendering via an
injected strategy" rule (like `Grid<T>`) — ComboBox owns no domain, so it
takes items + a render proc, not a data API in domain terms.

## Composition

`ComboBox < Component`, `include HasValue`. `value=` uses the mixin's
default `@value` storage, then *also* sets the field's query text to
`item_label(value)` and invalidates. Children: `[@field]` (a
{Tuile::Component::TextField}). It *owns* — but does not parent — a
non-modal `Popup(List)` opened on demand. This is
`examples/sampler.rb`'s `build_slash_demo` promoted to a component —
*minus the Window* (see "borderless tinted dropdown" below); the stock
hooks it leans on (`TextField#on_change`/`on_key`,
`List` + `Cursor` + `on_item_chosen`, `show_cursor_when_inactive`,
non-modal `Popup`) exist precisely to make this assemblable.

## Settled decisions

- **Filterable only.** The non-filterable `Select` variant is deferred —
  it needs the read-only field behavior HasValue already parked for the
  form layer, so it's a clean later addition once read-only lands.
- **`▾` affordance** in the field's rightmost column, so it reads as a
  combo at rest. Layout: `@field.rect` = the combo rect minus one column;
  `ComboBox#repaint` calls `super` (clears the gap) then paints `▾` in
  the last cell. (TextField already reserves its own last column for the
  caret, so usable text width is combo-width − 2.)
- **Borderless tinted dropdown — no Window.** The dropdown is a bare
  `Popup(List)`, distinguished from the content beneath it by a
  background *tint*, not a border — the modern autocomplete idiom, and it
  reclaims the border's 2 rows + 2 cols. The tint rides the shipped
  background-inheritance feature (`DECISIONS.md` `D-bg-inherit`):
  `overlay.bg_color = <tint>`, the `List` inherits it via
  `effective_bg_color`, and the fill-the-gaps bake tints the **filler rows
  too** — a solid panel, not the ragged half-shaded box the feature was
  created to kill. The cursor row still
  composes `active_bg_color` on top (distinct token → selection stays
  visible over the tint).
  - **Tint source = `theme.input_bg_color`** (default). It's an existing
    accent token — dark/light-aware, needs no app config, ties the
    dropdown to the field's own well, and pokes no new hole in the "no
    global bg token" stance (a dropdown is part of the input). A `nil`
    default would leave the borderless panel invisible against content —
    the ragged problem minus even a border — so a real token is the right
    default, not `nil`. (An app override knob can come later; YAGNI now.)
- **No placeholder** yet — empty value shows a blank field. Placeholder
  belongs on TextField generally, not here; add later.
- **Filter:** case-insensitive substring on `item_label(item).to_s`. No
  custom-filter override hook yet (add a `filter:` proc if a real need
  appears).
- **`value=` to an item not in `items`** is allowed — programmatic value
  is trusted; filtering is a separate concern.
- **Enter with no highlighted item** (empty result set) is a no-op /
  revert — no custom values (Vaadin's `allow_custom_value`, deferred: a
  custom value is a `String`, reintroducing the String/T tension at the
  value boundary).
- **`item_label` may return `String` or `StyledString`** — the field
  shows `.to_s`, the list shows the styled form.

## Keyboard / interaction

- Typing filters and opens the dropdown (if any match); ↓ opens it when
  closed.
- ↓/↑ move the list cursor while open (field keeps focus + caret —
  forwarded via `TextField#on_key`, works though the list is unfocused
  because dispatch gates on focus, not on the list).
- Enter commits the highlighted item → `value = items[idx]`, close popup.
- ESC closes the popup and reverts the query; a second ESC (popup already
  closed) falls through to `on_escape` (blur), per `TextInput`.
- Click an item commits it; click the field focuses.

## Popup sizing / anchoring

Width = field width (`left` = field left); desired height =
`min(items.size, ~10)`. ComboBox owns the flip:

- Measure room **below** the field row (`screen.height − (field.bottom + 1)`)
  vs. **above** (`field.top`).
- Fits below → place below, growing down from `field.top + 1`.
- Doesn't fit below → **flip above**, growing up so its bottom sits at
  `field.top − 1`.
- Fits neither → take the larger side, clamp height to it, let the `List`
  scroll the overflow.

Positioned via `Popup#size=` (`Size`) + the popup rect against
`Screen.instance.size` — the sampler's `anchor_overlay` logic, but with
the above/below flip (the sampler only anchors above the field; the combo
needs both directions).

## Implementation gotchas (for the build session)

- **Guard the programmatic-set path.** `value=` sets `@field.text`, which
  fires the field's `on_change` → refill → *opens the popup*. A
  programmatic `value=` (or a commit writing the label back) must **not**
  pop the dropdown open: set the field text behind a `@suppressing_filter`
  flag so the refill is skipped.
- Two `on_change`-ish listeners coexist without confusion: ComboBox uses
  the *field's* `on_change` internally for filtering; ComboBox's own
  `on_value_change` (the T seam) fires only on commit, from `value=`.
- `children => [@field]`; the popup is on the pane's popup stack when
  open, never a child of the combo.
- **Rebuild the tint on theme flip.** `overlay.bg_color` is a stored
  `Color` ivar read at paint time — a bare `theme=` flip does *not*
  restyle it. ComboBox overrides `on_theme_changed` (call `super`),
  re-setting `overlay.bg_color = screen.theme.input_bg_color` from the
  fresh theme, or the dropdown goes stale on a light/dark switch. This is
  the documented pattern for theme-derived `bg_color`.

## Dependency gate — build order

ComboBox **depends on background inheritance**, which has now shipped
(`DECISIONS.md` `D-bg-inherit`): `Component#bg_color` + the `List`
inheritance/bake, which the borderless dropdown relies on to separate from
content. That gate is now cleared, so ComboBox is unblocked. (A
Window-wrapped fallback would also work, but we've chosen the
tinted-borderless target.)

## On completion — graduate

Per AGENTS.md: reader-half → book (a "combo box / overlays" note, or fold
into whatever input-components chapter emerges); invariant-half →
AGENTS.md (the two-values rule + the suppress-filter guard); decision-half
→ DECISIONS.md (`D-combobox`: typed `value` via items+item_label,
filterable-first, commit-vs-query split). Retire this file.
