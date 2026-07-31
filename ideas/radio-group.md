# Radio Group

**Status:** not started; design settled 2026-07-31. Batch-1 field component
(see `ideas/new-components.md`). Depends on nothing, but shares its items /
`item_label` vocabulary with {Tuile::Component::ComboBox}. The sibling
`CheckboxGroup` is **built** — read `DECISIONS.md` `D-checkbox-group` before
starting; it settled the shared vocabulary, and the 2026-07-31 revision below
closes the two questions it deliberately left open here (composition, and
whether the cursor *is* the selection).

## What it is

Single-select from a small, fully-visible set of typed items:

```
(*) Ascending
( ) Descending
( ) Unsorted
```

`value` is the **selected item** (of whatever type `items` holds), never
its label — same rule as ComboBox (`D-combobox`, `D-has-value`).

## Shape

`Component::RadioGroup < Component`, `include HasContent`, `include HasValue`,
with the ComboBox strategy pair:

```ruby
rg = Component::RadioGroup.new(items: %w[Ascending Descending Unsorted])
rg.item_label = ->(item) { item.name }   # default :to_s
rg.value                                  # => the selected item, or nil
rg.on_value_change = ->(item) { ... }
```

- `items=` — `Array` of anything; **chrome only, it does not touch `value`**
  (revised 2026-07-30 — it previously said "resets/clamps the selection"). It
  *does* clamp the **cursor**, which is chrome too — see below. Type-guard it
  (`raise TypeError unless Array`), as `CheckboxGroup#items=` does.
- `item_label=` — `item -> String | StyledString`, default `:to_s`.
  (Generic component ⇒ externalized rendering strategy, per COP.)
- `initialize(items: [], value: nil)` — take the selection as a ctor kwarg and
  **seed the ivar directly**, so no listener fires and assignment order doesn't
  matter to a future form helper. Straight copy of `CheckboxGroup#initialize`.
- `empty_value` needs no override: `nil` (HasValue's default) *is* "nothing
  selected", so `empty?`/`clear` come free.
- **Store the selected object, not an index** (revised 2026-07-30; this note
  previously said the opposite, and was the file out of step with the
  code). `ComboBox` stores the object and its rdoc states *"The value need not
  be in `#items`"*; the index in `D-combobox`'s identity rule is transient
  *resolution* at commit time (`@filtered[index]` → object), not storage. So an
  object absent from `items` **does not clear** — no row renders selected and
  the value survives, which is what keeps a form saved without edits from
  changing anything silently. `value = nil` is the only thing that clears.
  Duplicate *labels* still resolve correctly because a click/Space/Enter
  resolves by row index at that moment. `D-checkbox-group` carries the
  set-valued generalization of the same rule.

## Cursor roams; Space/Enter selects (revised 2026-07-31 — a reversal)

**This note previously argued the opposite** ("selection == cursor, no dual
state, Up/Down move the selection directly, Space/Enter are harmless no-ops
kept for muscle memory") on the strength of the desktop/HTML convention, where
arrow keys move focus *and* selection together. **Reversed.** The cursor roams
freely; **Space, Enter or a left click** marks the row under it, exactly as in
`CheckboxGroup`. Three reasons, the second being the one that actually decides
it:

1. **Framework consistency beats the desktop convention.** "A cursor roams,
   Enter chooses" is Tuile's idiom everywhere a list of things is presented
   ({List}, {ListDropdown}, {PickerWindow}), and `CheckboxGroup` already ships
   it for the *group* case. Two group widgets one Tab apart in the same form
   must not answer Down differently.
2. **Selection-follows-cursor fires `on_value_change` once per row
   traversed.** Arrowing from row 1 to row 5 fires four times — so a listener
   that re-sorts a list, refilters a pane or hits a DB does that work four
   times, three of them for selections the user never meant. HTML radio groups
   have this wart and apps debounce around it. Committing on Space/Enter fires
   exactly once, on intent.
3. **It deletes the whole pile of List-route friction** the old model created
   — each item below was an artifact of forcing one piece of state to be two
   things, and none survives the reversal:
   - the `on_cursor_changed` → `value=` → `lines=` → `notify_cursor_changed` →
     `on_cursor_changed` **re-entrancy loop** (terminated only by `HasValue`'s
     no-op guard, and needing a `@suppressing_filter`-style flag to be safe);
   - `List#handle_key`'s **PgUp/PgDn move the viewport, not the cursor**
     (`list.rb:203`), which under selection-follows-cursor scrolls the
     selection off-screen, while `^U`/`^D`/Home/End *do* move it and would fire
     a value change each;
   - **Enter is swallowed** by the inner list whenever `cursor_on_item?`
     (`list.rb:209`) whether or not anything is listening — a dead key under
     the old model, a *meaningful* one under this one;
   - `show_cursor_when_inactive` (defaults `false`, `list.rb:28`) had to be
     flipped so an unfocused group still showed its selection.

The cost is one extra keystroke, which is the TUI norm.

**What now carries what.** The `(*)`/`( )` glyph carries the *selection*, at
all times, focused or not; the themed row highlight carries the *cursor* and
correctly vanishes when the group is inactive — so `show_cursor_when_inactive`
stays at its `false` default. Two indicators for two pieces of state, which is
also what the sampler's `CheckboxGroup` pane already reads like.

### The cursor is chrome (settled 2026-07-31)

The cursor joins `items` on the **chrome** side of the chrome/value split
(`D-combobox`): presentation state, never value state. So the independence is
total and *symmetric* — a commit writes `value` and leaves the cursor where it
is, and **`value=` does not move the cursor**, neither on a programmatic write
nor from the `value:` ctor kwarg.

This isn't a new rule so much as a name for what `CheckboxGroup` already does:
its ctor installs a bare `List::Cursor.new` (position `0`) whatever the seeded
`value:` was, so a group opened with rows 2 and 5 checked still starts its
cursor on row 0. Naming it is what stops `RadioGroup` diverging by accident.

Two consequences, both accepted:

- **Nothing auto-parks the cursor on the selected row.** An app that wants
  that writes it — `rg.content.cursor = List::Cursor.new(position:
  rg.items.index(rg.value))` — since `content` is public on a `HasContent`
  composer (`D-integer-field`). Same line the items/value rule already draws:
  keeping two independent things in sync is the app's job, the framework has
  no reconcile step. (This deletes the earlier "does `value=` park the cursor,
  and how does it scroll into view?" question: nothing programmatic moves the
  cursor, so nothing can park it off-screen.)
- **On a group long enough to scroll, the selected `(*)` can be off-screen**
  with no on-screen indicator, and a form opened with a pre-set value shows
  the highlight on row 0 with the `(*)` elsewhere — so a reflexive Space picks
  row 0. Two indicators, two meanings; identical to `CheckboxGroup` with
  checked rows scrolled away, and a radio group is small by nature.

### `items=` clamps the cursor — the one place chrome touches chrome

Not tidiness; without it there is a window where Space *clears the selection*.
`List#lines=` does **not** clamp (`list.rb:140-148` — it re-notifies and
repaints, nothing more), so a shrinking `items=` strands the cursor out of
range: no highlight (`paintable_line` guards `index < @lines.size`), Enter dead
(`cursor_on_item?`), and it self-heals only on a **Down** press
(`go_down_by` clamps to `line_count - 1`) — Up merely decrements a stale index
and stays out of range. Press Space in that window and `@items[stale]` is
`nil`, so `self.value = nil` silently clears the selection *and* fires
`on_value_change(nil)`.

So clamp in `items=`, **and** keep `CheckboxGroup`'s
`return unless index.between?(0, @items.size - 1)` guard on the select path —
the guard is what covers empty `items` and `Cursor::None` at `-1`, which no
clamp can reach.

Watch the empty case in the clamp *you write here*: `pos.clamp(0,
new_items.size - 1)` **raises** `ArgumentError` when `new_items` is empty
(`clamp(0, -1)`, min > max). Write it as
`[pos, new_items.size - 1].min.clamp(0, nil)`, or return early. Assign through
`content.cursor = List::Cursor.new(position: …)`, which invalidates and
notifies (`list.rb:109`) — an app listening on `content.on_cursor_changed`
should see a clamp, it's a real move.

**This is not a latent bug in `List`** (checked 2026-07-31, don't re-open it):
every clamp in `list.rb` is deliberately *one-sided* — `clamp(0, nil)` at
`:388`/`:643`/`:683`, `clamp(nil, line_count - 1)` at `:378`/`:410` — so
min > max never arises, and the one two-sided call (`:656`) clamps against
`top_line_max`, itself floored at 0. All movement funnels through
`Cursor#go`'s closing `clamp(0, nil)`, so an empty list already floors the
cursor at 0 (verified: Down → 0, End → 0). The two-sided form above is
*our* hazard for having reached for the obvious expression; mirror `List`'s
idiom and it evaporates.

A clamped cursor and an absent value coexist without a reconcile step: after
`items=` the cursor is valid again while `value` may no longer be among the
rows, in which case nothing renders `(*)` and the value survives intact.

**No deselect gesture.** Space/Enter on the already-selected row is a no-op —
it re-assigns the same object, `HasValue#value=`'s guard returns early, and
there is no rebuild and no event. Radio semantics: only `value = nil` clears,
and only programmatically.

## Build on `List` — decided (compose)

Composing a {Tuile::Component::List} was the first proposal (2026-07-25), kept
open for the merits through the `CheckboxGroup` build. **Closed 2026-07-31:
compose.** The reversal above is what closes it — the paint-your-own fallback
existed to escape the friction in item 3, and that friction is gone. What
remains is `List` machinery we'd otherwise re-implement: the cursor, the
viewport, the scrollbar and the mouse arithmetic.

`RadioGroup` holds one via {Tuile::Component::HasContent}, exactly the composed-field
shape `D-integer-field` blessed and `D-checkbox-group` extended from "a field
composes a `TextField`" to "a field composes whatever widget already has the
interaction".

The wiring is `CheckboxGroup` minus the `Set` — four lines:

```ruby
list = List.new
list.cursor = List::Cursor.new                       # a bare List has none!
list.on_item_chosen = ->(index, _line) { self.value = @items[index] }
self.content = list
# + handle_key claiming " ", + rebuild_rows on items/item_label/value change
# + items= also clamps the cursor, + layout(list) = (list.rect = rect)
```

`on_item_chosen` covers Enter **and** click (`list.rb:209` and `:264`), so
there is no `handle_mouse` override; `handle_key` claims only `" "` and lets
everything else bubble. `rebuild_rows` maps items to
`StyledString.plain(selected ? "(*) " : "( ) ") + label_for(item)` — copy
`CheckboxGroup`'s private `label_for`, which `.to_s`es anything that isn't a
`StyledString`, because a custom `item_label` may return a domain object and
{StyledString#+} takes only a `String`/`StyledString` on the right.

Tab-stop bookkeeping follows the invariant: the wrapper is **not** a tab
stop (inherit `Component`'s `false`), the inner `List` is (it already
returns `true`). `HasContent#on_focus` forwards focus down.

**The two gotchas that cost time on `CheckboxGroup`** (both now also in
AGENTS.md's `HasValue` section): a bare `List` has `Cursor::None` at position
`-1`, so without `List::Cursor.new` the arrows, Enter and the highlight are all
silently dead; and `List` pads a one-column gutter, so rows paint at
`rect.left + 1` — that offset belongs in the `region_text` assertions.

## Painting

Rows paint through {Tuile::Component#draw_line} — inherited from `List`, which
already routes there, so an ancestor `bg_color` is honored (camp 2; no input
well here).

**Glyphs `(*)`/`( )`, ASCII, as literals — and no `glyphs=` knob in v1**
(revised 2026-07-31; this note previously specified the knob, and before that
defaulted to `(•)`). The ASCII default is settled by `D-ambiguous-width`:
U+2022 BULLET is East-Asian-Ambiguous, so of the batch-1 components this is the
one carrying a genuine *cell-count* risk — every row would mis-measure by a
column in an ambiguous-wide terminal. `password-field` ruled the same way for
the same character (`mask_char` defaults to `*`). (`checkbox` is unaffected —
`☑` is Neutral; its problem is font coverage and glyph bleed.)

The *knob* is dropped because it would be the first of its kind among the three
boolean components: `Checkbox` and `CheckboxGroup` both ship glyph **literals**
— a documented convention, three columns plus a space, not public constants
(`D-boolean-fields`' glyph-home ruling, re-declined in `D-checkbox-group`).
`D-ambiguous-width` blesses an opt-in knob but doesn't demand one, and adding
it here creates symmetry pressure for a `Checkbox#glyphs=` nobody asked for.
Add it when someone actually wants `•`, with `mask_char` as the template
(validate `display_width == 1` at assignment) — and then probably to all three
at once.

## Open questions

- ~~Where does the cursor start, and does `value=` move it?~~ **Answered
  2026-07-31** by the cursor-is-chrome ruling: it starts at 0 and nothing
  programmatic moves it except an `items=` clamp.
- Should the clamp be `List`'s job rather than every composer's? `lines=`
  stranding the cursor out of range is a general `List` sharp edge, not a
  radio-group one — `CheckboxGroup` has the same window today, saved only by
  its `between?` guard. More evidence: **Up** on an over-range cursor merely
  decrements it (from 5 on an empty list you get 4, not 0), so movement
  self-heals in one direction only. Harmless inside `List`, where every
  consumer guards on `cursor_on_item?`. Fixing it in `List#lines=` would help
  both composers, but it changes behavior for every existing list (a log
  window's cursor would move on truncation). Leaning: clamp locally here for
  v1, and file the `List` question separately if a third composer hits it.
- Left/Right as synonyms for Up/Down (some toolkits do, for horizontal
  groups)? Only matters if we ever add a horizontal orientation — Vaadin
  has one; skip it for v1.
- Should an empty `items` render nothing or a placeholder row? Nothing.
- `value = nil` (no selection) is representable — but is a radio group
  with nothing selected legitimate? Yes for v1 (it's the initial state);
  a `required` axis belongs to the deferred forms layer.

## Specs

`spec/tuile/component/radio_group_spec.rb`. Cover:

- initial `value` is `nil`; `value:` in the ctor fires no listener.
- **Arrowing across rows changes nothing** — `on_value_change` never fires
  (the regression guarding the 2026-07-31 reversal).
- Down then Space selects the second item and fires `on_value_change`
  **exactly once**; Space on the already-selected row fires nothing.
- Enter selects (List's choose gesture); a left click on a row selects it.
- `value=` with an object in `items` renders that row `(*)` and **leaves the
  cursor where it was**; a ctor-seeded `value:` still starts the cursor at 0
  (the cursor-is-chrome regression).
- `value=` with an object absent from `items` selects nothing visibly **but
  keeps the value**; `value = nil` clears.
- **`items=` clamps the cursor**: with the cursor on row 7, assigning three
  items leaves it on row 2 — and Space then selects that row rather than
  clearing the value to `nil` (the stranded-cursor regression).
- `items = []` neither raises (the `clamp(0, -1)` trap) nor lets Space do
  anything.
- **duplicate labels** — selecting the second of two equal-labeled items
  selects *that* one (the identity regression from `D-combobox`).
- `items=` leaves `value` untouched and fires no `on_value_change`; a
  non-`Array` raises `TypeError`.
- the rendered rows via `buffer.region_text(rect)` — remember the gutter,
  text starts at `rect.left + 1`.
- ancestor `bg_color` inheritance.

## Graduation

Sampler pane (a radio group driving something visible — sort order of an
adjacent list); book ch7 section, next to the `CheckboxGroup` one; AGENTS.md
class index line.

**A `DECISIONS.md` entry is warranted — but not for the reason this note used
to give.** It said an entry was owed *if we composed a `List`*, because that
would extend the composed-field taxonomy; `D-checkbox-group` has since recorded
exactly that extension, so composition is now the unremarkable path and needs
only the class-index line. What earns an entry is the **interaction reversal**:
diverging from the desktop selection-follows-arrows convention that every GUI
radio group implements, on the fire-once-per-row argument. That's a real
road-not-taken with a real counter-argument, and it currently has no durable
home — together with its corollary, that **the cursor is chrome** (which
`CheckboxGroup` already implements without having named it). Either a short
`D-radio-group`, or a paragraph grafted onto `D-checkbox-group` promoting its
cursor/selection split from "what this one component does" to "how Tuile's
group widgets behave" — decide at build time.
