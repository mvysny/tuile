# Menu Bar — a focused strip driving a cascade of `ListDropdown`s

**Status:** design **settled** 2026-08-24, nothing built. Supersedes the
one-line hunch in `ideas/new-components.md` ("Menu Bar | `ListDropdown::Menu` +
Popover") — the Popover half turns out to be avoidable, see *What the framework
must grow*. The five open questions this file opened with were answered the same
day; they are recorded under *Decisions taken* and folded into the sections
above it, so what remains is a spec to build against.

**This file stays open until v2 ships.** It is a two-stage build (below), and
AGENTS.md's graduation pipeline retires an `ideas/` note only once the idea is
"implemented and stable" — which is after v2 here, not after v1. The *decision*
half may graduate to `DECISIONS.md` `D-menu-bar` with v1 regardless: the
pipeline explicitly allows an entry recorded when the decision was made, ahead
of implementation.

**Scope as set.** In: nested submenus to arbitrary depth, per-item click
listeners, keyboard + mouse navigation (v1), and per-item mnemonics ("F for
File" while the bar has focus — v2). Out, deferred indefinitely: checkable
items, disabled items, items reachable from a global shortcut, reordering,
removal, dynamically computed items. Separators are out too (see *Roads not
taken* — a `List` has no unselectable row, so they aren't free). Context Menu is
a later session; this file records where the seam for it is without building it.

## Scope — v1 and v2

**v1: the mechanics, the API, and a sampler pane.** `Component::MenuBar`,
`MenuBar::Item`, the private `MenuBar::Cascade`, the two `ListDropdown`
additions, specs, and a sampler demo. Full cascade behaviour and the whole key
map minus mnemonics.

### v1, as built (2026-08-24)

Shipped as designed — `MenuBar` + nested `Item` in `menu_bar.rb`, `Cascade` in
`menu_bar/cascade.rb`, `D-menu-bar`, book ch7 "Menus", a sampler pane, 53 new
specs. Five deltas the design didn't predict, all small:

1. **A third `ListDropdown` addition:** `on_cursor_changed=`. The design counted
   two (`anchor_beside`, `cursor_row_rect`) and forgot that the pass-through the
   truncate-on-highlight-move rule needs didn't exist yet.
2. **`MenuBar#on_detached` closes the cascade.** The panels are the pane's
   children, not the bar's, so removing the bar would otherwise strand them —
   which the sampler hits directly, since swapping demos detaches the pane (the
   slash-menu demo has to close its overlay by hand in `load_entry`; this one
   doesn't).
3. **Only a *changed* rect closes the cascade.** `Component#rect=` early-returns
   on an equal rect but the caller's line still runs, and `Layout::Box`
   re-assigns an equal rect on every child mutation — so the naive
   `super; close` dismissed menus for no reason.
4. **A childless *top-level* item fires its listener** rather than opening an
   empty menu, so a single "About" needs no one-item submenu. Implied by
   "children win", not spelled out; Vaadin does the same.
5. **Stepping must not activate** — found in review, not in design. The key
   table above says Left-at-the-top / Right-on-a-leaf "step to the sibling menu
   and reopen there", and the first implementation did that by calling the same
   `open_highlighted` the Enter path uses. On a *top-level button* that fired the
   listener and left the previous panel standing over whatever the action
   produced. Stepping now shows the neighbour's menu or closes the cascade, and
   never fires; the table's row needed the leaf case spelled out.
6. **`keyboard_hint` is implemented but invisible in a tiled pane.**
   `Screen#refresh_status_bar` sources the tiled hint from `active_window` — the
   innermost active `Window` — and `Window` doesn't forward to its content, so
   `Tabs#keyboard_hint` and `Select#keyboard_hint` are equally dead there. Not
   introduced here and not fixed here: it is a change to the hint plumbing, and
   it wants its own decision.

**v3 (noted, not scoped): the sampler's own shell.** Once the widget exists,
`examples/sampler.rb`'s side nav list is a candidate to become a real `MenuBar`
at the top row — which would also give the widget its honest demo, a bar where
one actually lives. Explicitly *not* v1 or v2: v1's pane demo must stand on its
own first, and refactoring the sampler's shell is a change to the demo harness
every other pane depends on.

**v2: mnemonics.** `mnemonic:` on `add_item`, the match in
`MenuBar#handle_key`, and the underline cue with the
`StyledString#with_underline` it needs. Deferring costs *nothing structurally*:
`add_item(caption, &on_click)` grows to
`add_item(caption, mnemonic: nil, &on_click)`, which is a purely additive
keyword — no call site changes, no rename, no behaviour change for an app that
doesn't pass it. That is the whole reason this is a clean split rather than a
half-built feature.

## Prior art

### Vaadin 25.2 (verified via the docs MCP, not memory)

```java
menuBar.addItem("View", listener);            // leaf, returns MenuItem
MenuItem share = menuBar.addItem("Share");    // no listener
SubMenu sub = share.getSubMenu();             // the intermediary
MenuItem social = sub.addItem("On social media");
social.getSubMenu().addItem("Facebook", listener);   // depth 3, unlimited
```

Four things to take, one to drop:

- **The item *is* the submenu holder.** Unlimited depth falls out of it, and
  `ContextMenu` reuses the very same `MenuItem` / `SubMenu` types through a
  `HasMenuItems` interface (`MenuBar`, `ContextMenu` and `SubMenu` all implement
  it). That interface is the mixin this file defers.
- **Per-item click listeners, not a command bus** (contrast Turbo Vision below).
- **The keyboard map**, which is worth copying verbatim because it is also the
  ARIA menubar pattern and every TUI lineage agrees with it:

  | | |
  |---|---|
  | Left / Right | between top-level items |
  | Down / Space / Enter | open the top-level menu |
  | Up / Down | between items in a drop-down |
  | Right / Space / Enter | open a submenu |
  | Space / Enter | trigger an item *without* a submenu |
  | Left | return to the previous menu |
  | ESC | close the drop-down |

- **"Menu Bar shouldn't be used for navigation — use Tabs"**, and the reverse:
  a one-item MenuBar is the idiomatic drop-down *button*. Both belong in the
  book's widget-choice table next to the `Tabs` / `Select` rows.
- **Drop:** `getSubMenu()`. It exists because a Vaadin `MenuItem` is a DOM
  component and `SubMenu` is its overlay's container. Tuile's item is a plain
  handle, so `item.add_item(…)` can be the whole API — which is also what
  ratatui's `tui-menu` does ("a `MenuItem` with children is called a group").

### TUI lineages

- **Turbo Vision / Free Vision** (`TMenuBar` / `TMenuBox` / `TSubMenu`) — the
  origin of the look. Two ideas, both rejected below: mnemonics marked *inside*
  the caption (`"~F~ile"`), and activation as an **integer command code**
  dispatched through `handleEvent` rather than a per-item callback. F10 opens
  the bar from anywhere.
- **Terminal.Gui v2** (`MenuBar` / `MenuBarItem` / `MenuItem`) — closest living
  relative. Mnemonics as `"_File"`, `Action` delegates per item, and cascading
  sub-sub-menus that "pop out of the sub-menu frame (either to the right or
  left, depending on where the sub-menu is relative to the edge of the screen)"
  — the exact placement rule below. It also ships the drill-down alternative as
  a flag, `UseSubMenusSingleFrame`, which draws every level in *one* frame; see
  *Roads not taken*.
- **notcurses** (`ncmenu`) — sections of items, **one level only**, a
  `struct ncinput shortcut` per section and per item ("all shortcuts should be
  distinct"), and `ncmenu_offer_input` handling exactly the key set in Vaadin's
  table. Precedent for raising on a duplicate mnemonic.
- **Midnight Commander** — F9 opens the bar, letters pick, arrows navigate.
  `ncurses-st-menu` (okbob) is the extracted "CUA look" version of the same.
- **FTXUI, ratatui core, Bubble Tea, tview, Textual** — no menu bar at all.
  Textual's position is the explicit web one: menus aren't a TUI idiom, use a
  command palette. Worth a sentence in the book: Tuile disagrees because a
  file-manager-shaped app (`examples/file_commander.rb`) is the motivating case.

**Signal across all of them:** the keyboard map is settled, the item-is-a-group
shape is settled, and *cascade vs. single frame* is the one real fork.

## The proposed API

```ruby
bar = Component::MenuBar.new

file = bar.add_item("File")
file.add_item("New")   { new_document }
file.add_item("Open…") { open_dialog }
recent = file.add_item("Recent")                 # no block ⇒ a submenu holder
recent.add_item("notes.txt") { open("notes.txt") }
archive = recent.add_item("Archive")             # …and so on, no depth limit
archive.add_item("2025.zip") { open_zip }
file.add_item("Quit") { screen.close }

edit = bar.add_item("Edit")
copy = edit.add_item("Copy")
copy.on_click = method(:copy)                    # the non-block form
```

- `add_item(caption, &on_click) → Item`, on **both** `MenuBar` and
  `MenuBar::Item`, with the same signature — the one function the user's sketch
  asked for. `caption` is coerced by `StyledString.parse` like every other
  caption; `on_click` is a **no-arg** callable, exactly `Button#on_click`'s
  contract, so a menu item and a button are the same promise to the app. v2
  adds `mnemonic:` between them, additively.
- **One implementation, not two.** `MenuBar` holds a captionless private root
  `Item` and delegates: `def add_item(...) = @root.add_item(...)`,
  `def items = @root.items`. So the recursion is uniform (level 0 *is*
  `@root.items`), and there is no duplicated 6-line method to keep in sync.
  Vaadin's `HasMenuItems` mixin stays deferred with, usefully, nothing to
  extract: the shared method already exists exactly once.
- `Item` readers: `caption`, `items` (children, read-only by convention like
  `Component#children` and `Tabs#tabs`), `submenu?` (`!items.empty?`), and
  `on_click` as an `attr_accessor`. `mnemonic` joins them in v2.
  - **`items` is the right word despite `D-has-value`'s "`items` is chrome;
    `value` is authoritative" rule** — that rule governs items-*plus*-value
    components, and a `MenuBar` has no value to be authoritative against. These
    are structural handles, like `Tabs#tabs`, and `items` is simply what pairs
    with `add_item`.
- **An `Item` with neither children nor an `on_click` is legal and inert.**
  It highlights, Enter "activates" it, nothing happens, and the cascade closes
  like any other leaf activation — activation stays uniform rather than growing
  a do-nothing branch, and an item that looks live but is dead is the app's
  programming error to fix, not the framework's to raise on. An item with
  *both* is legal too and **children win**: `submenu?` decides, and the block on
  a parent is silently dead. (Vaadin allows the same, and its key table even
  lists "trigger top-level item with a menu" — but that is a *web* menu bar,
  where a top-level item doubles as a button. On a TTY strip it has nowhere to
  put the distinction.)
- **`Item` is a pure handle** — caption, children, `on_click`, and no
  machinery whatsoever. Not a `Component`: no rect, no paint, no place in the
  tree; the rows are painted by the `List` inside each dropdown. Unlike
  `Tabs::Tab` it needs no detach/`check_attached` machinery either, because
  removal is out of scope — there is no way to make a handle stale. All the
  machinery is in `Cascade`.
- **Both nested types live under `MenuBar`, in two different files, and the
  house has a precedent for each.** `MenuBar::Item` goes *inside* `menu_bar.rb`
  like `Tabs::Tab` and `List::Cursor` — a small handle belongs beside the
  component that mints it. `MenuBar::Cascade` gets its own
  `menu_bar/cascade.rb` like `TextArea::WrappedText`, because it is a
  substantial private class with its own specs. Zeitwerk is happy with both
  (one top-level constant per file; nested constants inside are fine).
- **No `on_item_selected` on the bar.** Each item carries its own listener
  (Vaadin, Terminal.Gui, ratatui all do this); a single bar-level callback
  would force every app into a `case` over captions, which is the Turbo Vision
  command-code design with worse typing.
- Not `HasValue`: a menu has no value. Same ruling as `Tabs` in `D-tabs` — an
  open menu is transient view state, and a `MenuBar` in a forms layer's value
  iteration would be nonsense.

## The mechanism

Four objects; two of them public API.

```
MenuBar          < Component   the strip: paints captions, owns the tab stop,
                               owns the root Item, holds @highlighted_index
MenuBar::Item                  public handle: caption, children, on_click.
                               No machinery. In menu_bar.rb, like Tabs::Tab
MenuBar::Cascade               private plain object: the stack of open
                               dropdowns, drill / pop / activate, key
                               forwarding. Own file, like TextArea::WrappedText
ListDropdown                   unchanged in kind — one per open level,
                               non-modal, non-focusable, driven from outside
```

**Focus lives on the bar, always.** This is `Select`'s architecture extended to
N levels: the dropdowns are overlays the bar *owns but does not parent* (like
`Select`'s `@overlay`), they are non-modal so they never take focus, and every
key arrives at `MenuBar#handle_key` because the bar is `Screen#focused`. Nothing
in the key ladder changes; no dispatch phase, no gate, no framework hook.

**The strip hit-tests like `Tabs` and is deliberately painted *unlike* it.**
One row, ` File  Edit  View `: one space of padding either side of each caption,
no separator, so two columns fall between neighbours. The padding belongs to the
segment — the highlight covers it and a click on it opens the menu.
`MenuBar#extent` is one row of `painted_width` columns, so a click on the blank
tail focuses the bar and opens nothing, and the extent must not vary with
`bg_color`. No solid background row: captions sit on the inherited background,
and an app wanting the classic reverse-video bar writes
`bar.bg_color = Theme.ref(:input_bg_color)` — free via `D-bg-inherit`.

Three divergences from `Tabs`, and the reason they are wanted rather than
tolerated: **a menu bar and a tab strip are otherwise the same picture** — one
row of captions, one highlighted segment — and a reader should not have to work
out which control they are looking at. So:

- **No separator.** `Tabs` joins segments with `│` because its segments are
  parts of one control and it lines up with a surrounding `Window`'s border.
  A menu bar's items are independent buttons; every lineage surveyed above
  paints them bare, and the two blank columns read as a gap between buttons
  rather than a ruled division.
- **No bold.** `Tabs` bolds its selected caption *always*, and its rdoc argues
  that specifically from persistence — the strip must still say where you are
  once focus has moved on. A menu bar has nothing to persist: close the menu and
  nothing is selected. So the highlight is `Theme#active_bg_color` on
  `@highlighted_index` while the bar is on the focus chain, and nothing at all
  when it isn't. Bold would be a channel with no signal on it.
- **No persistent highlight.** Follows from the same fact, and is what makes an
  unfocused bar read as a row of labels rather than as a control mid-selection.

The arithmetic is a near-copy of `Tabs`' private
`segments` / `painted_width` / `tab_at` trio, and it is the **second** copy, so
per AGENTS.md's "duplicate rather than DRY a shallow shell" it stays duplicated
— a third caption strip is when to argue for extraction. The copy is not
gratuitous even so: this strip needs each segment's full `Rect` (to anchor a
dropdown under it) and highlights a transient index rather than a persistent
selection. Overflow **clips** like `Tabs`, and Vaadin's
collapse-into-an-overflow-menu is deferred (it needs the same measure-then-fold
logic plus a synthetic `…` item; additive later).

**The cascade.** `Cascade` holds `@levels`, an array of `[Item, ListDropdown]`
pairs, in depth order. `cascade.open_below(segment_rect, item)` opens level 0 —
**one entry point, not two.** An earlier draft had the driver supply level 0's
placement so a context menu could pass a point instead; with `ContextMenu` out
of scope that is speculative generality, and the seam is one method away if it
is ever wanted. Levels 1..N are the cascade's own business: it anchors each one
*beside* its parent's highlighted row.

**Why `Cascade` exists at all, now that reuse is not the reason.** On
cohesion: `MenuBar` would otherwise do two unrelated jobs — paint a caption
strip, and manage a stack of overlays with their own key routing and
lifecycle — in one ~350-line class. Splitting on that seam is the COP move
(encapsulate the complexity in a self-sufficient piece), and it is what makes
the cascade testable without a strip. That argument stands on its own; any later
sharing is a bonus, not the justification.

**It is provisional, and there is a falsifiable test for it.** The split gets
re-judged against the real code once v1 exists, and the criterion is *the size
of the interface `MenuBar` needs*, not the size of the class: at roughly
`open_below` / `handle_key` / `close` / `open?` it is a genuine boundary, but if
it grows past ~7 methods and they are accessors exposing the level stack
(`depth`, `deepest_list`, `item_at(level)`) then `MenuBar` is X-raying it and the
"class" was only ever a seam — inline it back. Deciding this now, in the
abstract, is exactly the judgement that reads better in a design note than in a
diff.

Per level it wires two `List` callbacks, and the order matters:

- `on_item_chosen → activate_at(level, item)` — truncate the stack to `level`,
  then **drill if `item.submenu?`, else fire `item.on_click` and close
  everything**. Truncating first is what makes a mouse click on a *shallower*
  still-visible panel correct: `ScreenPane#handle_mouse` routes the click to the
  topmost popup whose rect contains the point, which for a shallower panel is
  that panel, and the deeper ones must go.
- `on_cursor_changed → truncate to that level` — moving the highlight closes the
  submenu that belonged to the row you left. GUI menus reopen the new row's
  submenu after a hover delay; Tuile has no timers on this path and shouldn't
  grow one, so the highlight moves and the user presses Right.

**Trap:** both callbacks also fire from `List#items=` and `List#cursor=`, so a
level must be fully populated *before* its callbacks are attached, or pushing a
level re-enters `truncate`. Wire last, and spec it.

**Keys.** `MenuBar#handle_key` first offers the key to the cascade, which claims
only what it can answer locally, then handles the rest itself — the same
division of labour as `ListDropdown#move` leaving ESC/Enter to its driver.

| Key | Cascade closed (bar focused) | Cascade open |
|---|---|---|
| Left / Right | move `@highlighted_index`, clamping | depth ≥ 2: Left pops one level. Otherwise → bar: step to the sibling top-level menu and reopen there (Right on a leaf included — the ARIA rule) |
| Down / Enter / Space | open the highlighted menu | `MOVE_KEYS` → the deepest list; Enter/Space → drill or activate |
| Right | (nothing; Left/Right move) | on a `submenu?` row: drill |
| Up | (nothing) | → the deepest list |
| PgUp/PgDn, ^U/^D | (nothing) | → the deepest list, via `ListDropdown#move` |
| ESC | unhandled → bubbles | pop one level; at depth 1, close (focus stays on the bar) |
| a mnemonic letter (**v2**) | open that top-level menu | match the **deepest** level only, then drill or activate |
| Tab | never seen — rung 1 is absolute; focus leaves and `active=` closes the cascade, exactly as `Select` does | |
| any other printable | **bubbles** — the app's `s`-to-save keeps working | **swallowed** — an open menu is a quasi-modal interaction, and firing an app key *behind* a visible menu is worse than a dead keystroke |

That last row is the one deliberate divergence from `D-select`'s "claim the
minimum": a *closed* bar is as transparent as a `Select`, an *open* one is not.
It is also the honest reading of what a menu is.

**Mouse.** Click a segment: focus the bar, open that menu (or close it if it's
the open one). Click a row: `List` already moves its cursor and fires
`on_item_chosen`, so drill/activate falls out. Open-on-hover (Vaadin's
`setOpenOnHover`, and every GUI menu) is **impossible today** — Tuile runs X10
mode 1000, press-only, no motion — and is gated on infrastructure item 5 in
`new-components.md`.

**Resize closes the cascade.** AGENTS.md's second non-modal-overlay trap says a
*derived* overlay position needs its own handling, or it sits at a stale column
after a SIGWINCH — off-screen entirely if the terminal narrowed. Every position
in the cascade is derived: level 0 from a segment rect, level *N* from its
parent's highlighted row. `Select` answers this by re-anchoring from its
`rect=`; a cascade would have to re-anchor *every* level in depth order, which
is more code and more failure modes than the case deserves. So `MenuBar#rect=`
**closes** the cascade instead. A resize is a deliberate act by the user, every
GUI dismisses open menus on one, and closing is unambiguous where re-anchoring a
three-level cascade is fiddly. Worth an rdoc sentence precisely because it
diverges from `Select`.

**The click-outside wart.** A non-modal overlay blocks nothing, so a click
outside the cascade reaches the tiled content and *acts*. Mitigation, which
covers nearly everything: `MenuBar#active=` closes the cascade when the bar
leaves the focus chain (copied from `Select#active=`), and any click on a
focusable component moves focus. A click on pure decoration leaves the menu
open. This wart is shared with `Select` and the sampler's slash menu; the honest
fix is a framework-level "outside click" notice for non-modal overlays, and it
is not worth inventing for this.

## What the framework must grow

**Two in v1, one in v2.** All additive, none touching a foundation invariant.

1. **`ListDropdown#anchor_beside(anchor, rows:, width:, max_rows:)`** — place
   the panel to the *right* of `anchor` (a one-row rect), flipping to its left
   when the right has no room, and **sliding** vertically (not flipping) so the
   panel's first row lines up with the anchored row where possible. `width:` is
   required and has no default: the caller measured it, per `D-select`'s
   "a dropdown driver supplies its own width" rule. Vertical slides while
   `anchor_to` flips, for the same reason `anchor_to` flips vertically and
   slides horizontally: never cover the thing being chosen from.

   **This is where the Popover question landed — settled: the method, on
   `ListDropdown`.** `new-components.md` named Menu Bar as blocked on extracting
   `Popover` from `ListDropdown#anchor_to`, with the trigger written as "the
   second *kind* of anchoring (a point; a right edge that flips)" — and a
   side-anchor is exactly that. It is still a sibling *method* rather than a
   class, because both callers wrap a `List`, so a `Popover < Popup` would move
   code without a second kind of *content*. Revisit in an upcoming session; the
   trigger to write into `D-menu-bar` is whichever comes first of the first
   non-`List` content wanting anchoring (Tooltip, a date-picker grid) and
   `ContextMenu` adding `anchor_at(point)`, which would make three placement
   methods on one class.

2. **`ListDropdown#cursor_row_rect → Rect | nil`** — the highlighted row's rect
   (`list.rect.top + cursor.position - list.scroll_top_row`), `nil` when the
   cursor is off-content. This is what level *N* anchors against, and it belongs
   here rather than in the cascade because `ListDropdown` owns the list's
   geometry and the cascade must not reach through it to `@list`.

3. **`StyledString#with_underline(underline: true)`** — **v2 only**, with
   mnemonics, and only for the visual cue. `Style` already carries an `underline` field and
   the parser already round-trips SGR 4; there is simply no `with_*` for it. Six
   lines mirroring `with_bold`, whose rdoc's "no `under_bold`" reasoning applies
   verbatim. Underlining *one* character means slicing the caption at the
   mnemonic and restyling that slice, which is why per-span `with_bold`-style
   application is enough.

**Nothing else.** No new key-dispatch phase, no `Component#visible?`, no
bottom-up sizing (the dropdown widths are measured caller-side, third copy of
the `Select` pattern that `D-select` explicitly sanctions), no `ScreenPane`
change, no `Popup` change.

**Glyphs.** The submenu affordance is `▸` (U+25B8), matching `Select`'s `▾`
(U+25BE): both are East-Asian **Neutral**, measured 1 under
`ambiguous_as_wide` too, so they are outside `D-ambiguous-width`'s bet and need
no ASCII opt-in. The obvious `▶` / `▼` (U+25B6 / U+25BC) *are* Ambiguous —
verified, not assumed:

```
▸ U+25B8 ambiguous_as_wide=1     ▶ U+25B6 ambiguous_as_wide=2
▾ U+25BE ambiguous_as_wide=1     ▼ U+25BC ambiguous_as_wide=2
```

**Right-aligning the arrow needs no width plumbing.** The renderer pads each
label to the *widest label in that submenu* — a number the cascade already
computed to size the panel — so the arrows line up without asking the `List`
how wide it ended up. The same column generalizes to a future accelerator-text
column (`Ctrl+S`), which is the shape "activated via global shortcuts" would
need if it ever comes back.

**One arrow, not two.** The `▸` on a submenu row is the whole affordance:
top-level bar items get **no** `▾` and no open/closed indicator. Every TUI
lineage above does it this way, the open menu is its own indicator (the panel is
right there), and Vaadin's `dropdown-indicators` is opt-in even on the web.

## Mnemonics — v2

Deferred out of v1 as a clean additive keyword (see *Scope*), and cheap enough
that the design is settled now rather than re-derived later.

`add_item("File", mnemonic: "f")`. A single character, stored downcased, matched
case-insensitively. Consulted **only** by `MenuBar#handle_key`, against its own
items: the top-level set while closed, the deepest open level while open. A
duplicate within one sibling set raises `ArgumentError` at `add_item` — it is a
programming bug and notcurses' "all shortcuts should be distinct" is the
precedent.

**Why this is legal.** AGENTS.md deleted `Component#key_shortcut` and the
capture phase that scanned a scope subtree, and forbids reintroducing them — but
its re-grow rule sanctions exactly this: *"bring it back as sugar over an
ancestor's `handle_key` (e.g. a `mnemonics` hash on `Layout`), never as a
dispatch phase and never with a gate."* A focused `MenuBar` consulting its own
item tree in its own `handle_key` is rung 3, unregistered, unscanned, and
invisible to every other component. Say this out loud in `D-menu-bar`, because
it is the first thing a reviewer will (correctly) flag.

**Marker-in-the-caption is rejected.** `"~F~ile"` (Turbo Vision) and `"_File"`
(Terminal.Gui) are compact, but a Tuile caption is a `StyledString` parsed from
possibly-styled text, and a magic marker would make it non-literal — a caption
containing a real underscore or tilde would need escaping, and the mnemonic
would be unrepresentable in an app that builds captions from data. A keyword
argument keeps the caption a value.

**The cost to state.** A `mnemonic: "s"` eats the app's `s`-to-save *while the
bar has focus*. That is what a mnemonic means, but it needs one rdoc sentence.

**Global-shortcut activation (F10, Alt+F) stays deferred**, and not only by
decree: `Keys` has no function keys and no Alt at all, and
`register_global_shortcut` rejects printables by design. So the feature needs
`Keys` to grow first, which is its own decision.

## Roads not taken

- **A single drill-down frame** instead of a cascade — one dropdown that
  re-renders as you descend, with Left going back. Real prior art
  (Terminal.Gui's `UseSubMenusSingleFrame`), and it would need *no*
  `anchor_beside` and no stack at all. Rejected: it is not what a menu bar looks
  like, it loses the "where am I in the hierarchy" readout that is the cascade's
  whole point, and it can't be the default with the cascade added later — the
  cascade is the harder mechanism and building it second means building it
  against a shape that assumed one panel.
- **A modal level-0 popup**, which would give real modality: keys scoped, clicks
  outside blocked, the click-outside wart gone. Rejected on a hard mechanical
  fact: `ScreenPane#add_popup` **centers** every modal popup and focuses it, so
  an anchored modal is impossible without changing `ScreenPane` — and this
  design is otherwise entirely additive. It would also invert ownership (the
  popup, not the bar, would hold focus and handle keys) and split the key logic
  across two classes.
- **Focusable dropdowns**, focus descending as you drill. Rejected: AGENTS.md's
  "Non-modal overlays — two traps" says a non-modal overlay that takes focus
  puts focus outside the key scope and kills *every* keystroke until Tab
  recovers. This is that trap, N times over.
- **A command-code bus** (Turbo Vision's `cmOpen` + `handleEvent`). Rejected:
  per-item callables are the modern consensus and Ruby has closures.
- **`item.submenu` as a separate object** (Vaadin's `getSubMenu()`). Rejected:
  it exists for DOM reasons Tuile doesn't have; `item.add_item` is one hop
  shorter and `tui-menu` shows the flattened shape works.
- **A `HasMenuItems` mixin now** (Vaadin's shared `MenuBar` / `ContextMenu` /
  `SubMenu` interface). Not needed and not designed for: the root-`Item`
  delegation above already means there is exactly *one* `add_item`
  implementation, so a future sharing exercise starts from one method rather
  than from two that drifted.
- **Separators.** `add_separator` looks free and isn't: a `List` has no
  unselectable row, so `Cursor` would step onto the separator and Enter would
  activate nothing. It needs either a skip-list cursor or a `Cursor` subclass
  that hops non-selectable positions — a real `List` change, and the honest
  place to argue it is a `List` decision, not this one.
- **Mutable captions.** `Item#caption=` (a "Save •" dirty marker) is left out of
  v1 to keep `Item` a write-once handle; it is additive later, needing
  `invalidate` on the bar and `List#refresh_rows` on an open level — which is
  precisely what `refresh_rows` exists for.

## Decisions taken (2026-08-24)

The five questions this file opened with, answered. Each is folded into the
sections above; this is the ledger, not a second copy of the reasoning.

1. **`anchor_beside` lives on `ListDropdown`** — a sibling method, not a
   `Popover` extraction. To be revisited/refactored in an upcoming session; the
   extraction trigger is recorded under *What the framework must grow*.
2. **Mnemonics slip to v2**, underline cue and `StyledString#with_underline`
   with them. v1 is mechanics, API and a sampler pane. The `mnemonic:` keyword
   is purely additive, so nothing is half-built by waiting — and **this file
   stays open until v2 lands**.
3. **`MenuBar::Item`** — nested, house style (`Tabs::Tab`, `List::Cursor`),
   *reverting* an intermediate call to promote it to `Component::MenuItem`. The
   promotion was priced against a breaking rename once `ContextMenu` names the
   type; that price is zero, because **no Tuile release ships between now and
   `ContextMenu`**. With the cost gone, the default wins: settle `MenuBar` as one
   coherent component, then argue unification with the second implementation in
   hand rather than against a guess about it. **`ContextMenu` is out of scope for
   this file from here on** — every "and `ContextMenu` reuses this" note below is
   an observation, never a constraint.
4. **An item may carry children *and* a block; children win.** Both missing is
   legal too — the item is inert, and that is the app's programming error to
   fix, not the framework's to raise on.
5. **`Tabs`' click bounding, but not quite `Tabs`' look.** Extent-not-rect hit
   testing, one space of padding either side, no solid background row — and
   **no separator** and **no bold**. The clinching argument is not the lineage
   survey (though every framework agrees): a menu bar and a tab strip are both
   one-row caption strips with one highlighted segment, so if they *also* look
   alike a reader has to work out which control they are looking at. Three small
   divergences compound into "these are different things at a glance", which is
   worth more than house uniformity here.

**One more settled while writing this up:** the `▸` on submenu rows is the only
arrow. No `▾` on top-level bar items, no open/closed indicator.

## Registration checklist (when it graduates)

Per AGENTS.md's graduation pipeline — a new component owes more than a file. The
build is two-staged, so **the docs land with v1 and the `ideas/` note is retired
after v2** (with v2's mnemonic rows folded into the same `D-menu-bar` entry and
the same book section rather than new ones — `DECISIONS.md` carries one
coherent, mutable entry per live decision).

- `lib/tuile/component/menu_bar.rb` (holding `MenuBar` and its nested `Item`)
  and `lib/tuile/component/menu_bar/cascade.rb`; the AGENTS.md **Layout** list
  gets two rows.
- rdoc carrying the whole local technical truth: the key table, the
  `Item`-is-the-submenu shape, the inert-item rule, the resize behaviour, the
  click-outside wart, and (v2) the mnemonic cost.
- `DECISIONS.md` `D-menu-bar` — the cascade-not-single-frame fork, the
  bar-holds-focus architecture, the rejected modal popup, the `Tabs`-look ruling
  with its two divergences, the `Popover` trigger restated, and (v2) the rung-3
  mnemonic legality argument.
- `CHANGELOG.md`: one `Add` sentence per release.
- README **Components** table: one row, grouped with `Tabs` / `Select`.
- Book ch7: a section, plus a row in the widget-choice table (menu bar vs. tabs
  vs. select — Vaadin's "don't navigate with a menu bar" belongs there).
- `TERMINOLOGY.md`: *cascade*, *submenu* — one line each; *mnemonic* with v2.
- `spec/tuile/component/menu_bar_spec.rb` and
  `spec/tuile/component/menu_bar/cascade_spec.rb`, additions to
  `list_dropdown_spec` for
  `anchor_beside` / `cursor_row_rect`, a sampler pane, and a PTY example test
  that paces its keys.
- `rake sig`, committed in the same commit — CI gates `sig/` drift.
