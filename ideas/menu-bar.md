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
listeners, keyboard + mouse navigation (v1), and per-item mnemonics at every
depth ("F for File", then "Q for Quit", while the bar has focus — v2). Out, deferred indefinitely: checkable
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

**v2: mnemonics.** `mnemonic:` on `add_item` at *every* depth, the match in
`MenuBar#handle_key`, the underline cue with the
`StyledString#with_underline` it needs, and the bell that answers a miss
(`Ansi::BEL` + `Screen#beep`). Deferring costs *nothing structurally*:
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
| a mnemonic letter (**v2**) | match the top-level set: open that menu | match the **deepest open level only**, then drill or activate. No fallback to any shallower level, ever |
| Tab | never seen — rung 1 is absolute; focus leaves and `active=` closes the cascade, exactly as `Select` does | |
| any other printable | **bubbles** — the app's `s`-to-save keeps working | **swallowed**, and (**v2**) **beeps** — an open menu is a quasi-modal interaction, and firing an app key *behind* a visible menu is worse than a dead keystroke |

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

**Two in v1, two in v2.** All additive, none touching a foundation invariant.

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

4. **`Ansi::BEL = "\a"` + `Screen#beep`** — ✅ **built ahead of v2**
   (2026-08-24), the audible half of the swallow rule. It belongs on `Screen`,
   not on a component — terminal IO is the *service* half of the
   `Screen`/`ScreenPane` split, same reasoning that keeps `emit` there.
   `check_locked` like any other `Screen` entry point; `FakeScreen` inherits it
   and captures the byte in `prints` via its `print` override, so the PTY
   example test can assert it lands too.

   **It must write immediately, not ride the frame.** The tidy-looking version
   is a `@bell_pending` flag drained into the next `emit`, preserving Screen's
   one-write-per-tick property — and it is **broken here**, silently. `repaint`
   ends with `return unless did_paint` (`screen.rb:646`), and a swallowed
   keystroke invalidates *nothing*, which is exactly the case the bell exists
   for: the BEL would be dropped, then fire late attached to some unrelated
   repaint. So `beep` is a plain `print(Ansi::BEL)`. The one-write discipline is
   about *cell* output and tearing; a BEL changes no cells and cannot tear.

   **No `Screen#bell=` knob in v2.** Every terminal emulator already owns this
   preference — off, audible, or visual flash — and that is the right layer for
   it. Add the knob when someone actually complains, not before.

   Honest caveat, for the rdoc rather than the design: plenty of terminals ship
   the bell off, so for those users the swallow is silent. That does not change
   anything — the non-event *is* the feedback (the menu conspicuously did not
   move) and the BEL is the bonus where enabled. Do **not** build a visual-bell
   fallback: that is a flash-the-screen mechanism with its own timing and
   repaint story, for a mistyped keystroke.

   This is the one growth item that is a *general facility* rather than a
   value-type convenience — `MenuBar` is merely its first consumer, and a failed
   {Component::List#select_next} is the obvious second, later. Which is why it
   shipped early and on its own: it owes nothing to mnemonics, and `screen_spec`
   now pins the `did_paint` trap ("rings even when nothing was invalidated") so
   a later tidy-up into the frame goes red rather than silent.

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
case-insensitively. Available at **every depth**, not just the top level.
Consulted **only** by `MenuBar#handle_key`, against its own items: the top-level
set while closed, the deepest open level while open. A duplicate within one
sibling set raises `ArgumentError` at `add_item` — it is a programming bug and
notcurses' "all shortcuts should be distinct" is the precedent.

### Registration: what `add_item` validates, and why `mnemonic` is read-only

Three checks at `add_item`, all against the *sibling* set (`Item#add_item`
against its own `@items`, which covers the top level too since those are
`@root`'s children — one check site, no special case):

1. **A duplicate raises `ArgumentError`.** Programming bug; notcurses precedent.
2. **`mnemonic: " "` raises.** Space is Enter's twin in the key table, so binding
   it would shadow activation. Note this does *not* fall out of the printable
   guard below — `Keys.printable?(" ")` is `true` — so it is its own check.
3. **A mnemonic must be `Keys.printable?` *and* one display column wide.** The
   printable predicate already exists (`keys.rb:147`, `key.length == 1 &&
   !key.match?(/\p{C}/)`) and its `length == 1` clause gives the
   single-grapheme-cluster half for free; the width check is the extra line,
   because `"漢"` is length 1, printable, and two columns wide. See *The cue*
   for why a wide mnemonic is worth making unrepresentable rather than handling.

**`mnemonic` is `attr_reader`, not `attr_accessor`.** `on_click` is an accessor
because it guards no invariant; this one does — a writer walks straight past the
duplicate check, at a point where there is no good answer left. `caption` is
already read-only and the scope bans reordering, removal and dynamic items, so a
fixed mnemonic is the consistent choice rather than an arbitrarily strict one.

`Item#inspect` grows the mnemonic: which letter is bound where is otherwise
invisible, and `inspect` is where a debugging session looks.

### The live set — one lookup, one candidate set, no fallback

> A mnemonic is matched against exactly one set: the top-level items while the
> cascade is closed, the deepest open panel's items while it is open. Nothing
> else is consulted, ever. A printable matching nothing in the live set is
> swallowed while the cascade is open (with a bell) and bubbles while it is
> closed.

Everything below follows from that sentence; it is the one to put in
`D-menu-bar` and the rdoc.

**Cross-level collision is structurally impossible.** The worked example that
settled it: `File > Export` bound to `e`, *and* top-level `Edit` bound to `e`.
When File is open the live set is File's items, so top-level `Edit` is not a
candidate at all and `e` activates Export with nothing to arbitrate. The two
`e`s are never in the same lookup. This is the payoff of scoping to a *level*
rather than scanning a subtree — a subtree scan is both the thing AGENTS.md
deleted (`Component#key_shortcut` + the capture phase) and the thing that would
have created a collision needing a tie-break rule.

Three consequences worth stating out loud, because each one *looks* like it
needs a rule and doesn't:

- An item may carry the same mnemonic as its own parent. Different levels.
- `ff` = File → Find, if File's menu has a `f`-bound Find. Unambiguous.
- The `ArgumentError` fires **only within one sibling set** — which is precisely
  the only scope where two mnemonics can ever race.

**A miss must not fall back upward.** Cascade open on Edit, user types `f`,
nothing in Edit matches: swallow, do not jump to the File menu. Falling back
would mean a mistyped letter silently tears down the open menu and opens a
different one. It also keeps the rule stateless — one live set, one lookup, no
chain walk. And swallowing is not a dead end: Left/Right step File→Edit
directly while open, and ESC-then-`f` works too, so the user who genuinely wants
the other menu has two obvious routes.

Prior art agrees exactly: in Windows/GTK/Qt menus, letters never switch
top-level menus while one is open — only the arrows do.

### The bell, and what it is *not* attached to

Beep is tied to **swallow**, and swallow only ever happens while the cascade is
open:

| | unmatched printable |
|---|---|
| cascade closed | bubbles to the app — `s`-to-save still works. **No bell** (it is not a miss, it is someone else's key) |
| cascade open | swallowed. **Bell** |

That asymmetry is not new policy; it is the audible form of the key table's one
deliberate divergence from `D-select` ("a *closed* bar is as transparent as a
`Select`, an *open* one is not"). The bell landing exactly on the existing rule
is the sign it is in the right place.

**The beep is guarded by `Keys.printable?`, at the swallow site.** The swallow is
`Cascade#handle_key`'s fall-through `true` (`cascade.rb:92`) and the beep goes
*there* — the site that swallows owns the signal, rather than `MenuBar` trying to
infer it after the fact. But the fall-through catches more than printables: HOME,
function keys, and — the real problem — junk, since {Keys.getkey} gulps a fixed
five bytes after a leading `\e`, so an unrecognized sequence arrives as a
multi-byte garbage "key". Beeping at terminal noise is both annoying and
unattributable by the user. A printable is a deliberate, visible act; everything
else is silence. (Space never reaches this site — the cascade claims it for
activate — so the printable predicate's acceptance of `" "` is harmless here.)

Two boundary cases are ruled **out** of the bell, to stop it metastasizing:

- **A matched-but-inert item does not beep.** An item with neither children nor
  an `on_click` is legal (decision #4 — the app's bug, not the framework's). It
  matched; silence.
- **A clamped Left/Right does not beep.** Tempting, since nothing visibly moved
  — but if the rule becomes "beep when nothing happened" you now owe an audit of
  every no-op path in the widget. Keep it strictly `beep ⇔ swallowed`, which is
  one branch on `Cascade#handle_key`'s fall-through.

### Dispatch order: the match must be hoisted above the cascade

v1's shape makes this a change to the *order* inside `MenuBar#handle_key`, not
just a new `when` branch. Today `handle_key` delegates to the cascade first
(`menu_bar.rb:207`) and `Cascade#handle_key` swallows every unrecognized key
while open (`cascade.rb:92`) — so a printable letter never reaches the bar with
a menu open. v2 tests the mnemonic **before** `@cascade.handle_key(key)`,
guarded to a single printable, non-space character so ENTER / space / arrows /
ESC / `MOVE_KEYS` keep their current path. The guard is also why
`mnemonic: " "` must raise at registration alongside the duplicate check.

### The cue: always drawn, memoized on the `Item`, and the column trap

**Cues are always visible** — on the strip whether or not the bar has focus, and
in every panel row. Windows hides menu underlines until Alt is pressed; Tuile
cannot copy that (no Alt), so the choice is binary and discoverability wins: a
mnemonic nobody can see is a mnemonic nobody uses. The cost is a fourth kind of
ink on a strip that decision #5 deliberately kept quiet — but panel rows only
exist while a menu is open, so the only *ambient* ink is the top strip's three
to five items, one underlined column each. Much smaller than the separator or
background row that decision already rejected.

The considered alternative was cues on the strip only while the bar is focused,
mirroring how the highlight already behaves. Rejected for now on the grounds
that it is both louder in code and quieter than it should be in use: always-draw
is one unconditional memoized method, focused-only needs two variants plus
`active?` threaded through the cue path. **Revisit in a later session if the
strip reads as noisy** — the change is localized to that one method, which is
what makes deferring it cheap.

#### One home for the arithmetic: `Item#cued_caption`

There are **two** paint sites — the strip's `segment_text` builds
`pad + item.caption + pad` (`menu_bar.rb:307`), and the panel rows come from
`Cascade#renderer_for`'s lambda (`cascade.rb:186`). Both need the same
slice-and-underline, so it lives on the `Item` as a memoized `#cued_caption` and
neither paint site does arithmetic.

Memoizing is safe here and does *not* breach the never-cache rules: caption and
mnemonic are both fixed at `add_item`, and `underline` is a plain attribute with
no `Screen`, theme or `bg_color` dependency. `#caption` keeps returning the raw
value — a caller asking for the caption should not get chrome back.

**The trap it exists to contain:** {StyledString#slice} measures in **display
columns** (`styled_string.rb:486`, via `slice_text_by_columns`), while finding
the mnemonic in a caption yields a *character* index. Those agree only for
one-column glyphs — precisely AGENTS.md's index-vs-column trap, and `"Café"` with
`mnemonic: "é"` is enough to trip it. Registration's width-1 rule keeps the
mnemonic itself from being wide, but the *prefix* before it still has to be
measured rather than counted.

Two collisions that could have needed handling and don't:

- **Highlight.** `segment_text` highlights with `with_bg`, which preserves every
  other attribute — so an underlined mnemonic survives being highlighted. Worth
  a spec, needs no code.
- **Ellipsis.** The renderer does `item.caption.ellipsize(label_width)`. Apply
  the cue to the caption *first* and the underline rides along; if the ellipsis
  cuts the mnemonic off, the cue vanishes on its own and the mnemonic still
  fires. The "absent character draws no cue" rule below falls out instead of
  needing a second branch.

#### Which occurrence, and the absent character

Underlining means slicing the caption at the mnemonic, so two rules the v1
design didn't need:

- **Which occurrence.** `"Save As"` with mnemonic `a` has two candidates. Rule:
  match downcased, but pick the cue position by preferring an **exact-case**
  hit, falling back to the first case-insensitive one. So `mnemonic: "A"`
  underlines the *As* and `mnemonic: "a"` underlines the *a* in *Save*. Three
  lines, and it hands the app a way to say *which* one without reintroducing the
  rejected `~F~ile` marker.
- **The character need not appear in the caption, and an absent one must not
  raise.** The motivating case is real: a recent-files menu with mnemonics
  `1`…`9` over captions like `~/work/tuile/README.md`. No cue is drawn, the
  mnemonic still fires, and an app that wants the digit visible puts it in the
  caption itself. (Raising here would also sit badly with the marker rejection
  below, which turns on captions being buildable from data.)

### Why this is legal, what it costs, and the rejected marker

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

**A paste can never fire a mnemonic, for free.** Pasting `"fq"` into a focused
bar does nothing: paste rides its own path beside the key ladder and `MenuBar`
does not override `handle_paste`. That is the same principle as
`D-bracketed-paste`'s "never replay pasted text as keys", holding with no code —
so it wants one rdoc sentence, mostly so nobody later "fixes" it.

**Shadowing, the sharper version of that cost.** A mnemonic shadows every
*ancestor's* binding for the key too, not just the app's global habits: put a
`mnemonic: "q"` on a `MenuBar` inside a `Popup` and rung 3 bubbles up from the
focused bar, so the bar wins and `Popup`'s `q`-to-close is dead while the bar
holds focus. Correct, and exactly what the bubble is for — but it is the version
of the sentence a reader will actually hit, so it is the one the rdoc should
carry.

### Prior art on submenu mnemonics — near-universal, one holdout

Checked because "type `f` then `q` to hit File > Quit" sounds like a feature
someone must have banned for a reason. Nobody has:

| Lineage | Submenu mnemonics? |
|---|---|
| Win32 / GTK / Qt | Yes, level-scoped, `&File` / `_File`. `Alt+F, X` to exit since Windows 3.0 |
| Turbo Vision | Yes, `~F~ile` at every level |
| Terminal.Gui v2 | Yes, `_File`, `HotKey` on `MenuItem` at every level |
| notcurses | Yes — and the source of the "shortcuts should be distinct" raise precedent |
| **macOS** | **No menu mnemonics at all** |

macOS is the only holdout and its reason is historical, not a hazard: the Mac
never had an Alt-activates-the-menubar model, so there was no key to hang
mnemonics off and the HIG pushed everything onto ⌘-accelerators. Tuile has a
focusable bar, so the argument does not transfer. What this buys is better than
novelty — a Windows-raised user will *try* `f`, `q` unprompted, and it works.

### Two adjacent features deliberately left out of v2

- **First-letter type-ahead** ("type `s` in an open menu to jump to the first
  item containing s") is nearly free here, and that is the trap:
  {Component::List#select_next} already does substring, case-insensitive,
  cursor-ordered-with-wrap search (`list.rb:285`, `:635`), so it is a handful of
  lines through the panel's `List`. Keep it out — it competes with explicit
  mnemonics for the same keystroke, so it immediately owes a precedence rule
  *and* a ruling on whether a unique match fires or merely highlights (Windows
  fires on unique, cycles on ambiguous). That is a second feature wearing v2's
  clothes. **v3 candidate**, with the `select_next` pointer recorded here.
- **The `fq` *chord*** — typed fast with no menu ever appearing — is the thing
  that genuinely is rare, and should stay out. It needs either a type-ahead
  buffer with a timeout (and this codebase has a standing argument against
  timeout-based key reading — {Keys.getkey}'s rdoc, and the PTY key-pacing rule
  in AGENTS.md) or suppression of the intermediate paint. Real accelerators
  (`Ctrl+Q`) exist for that job and are unambiguous. And the *sequence* already
  delivers the feel: `f` opens File visibly, `q` fires Quit, and a user typing
  fast experiences it as one gesture anyway.

**Global-shortcut activation (F10, Alt+F) stays deferred**, and not only by
decree: `Keys` has no function keys and no Alt at all, and
`register_global_shortcut` rejects printables by design. So the feature needs
`Keys` to grow first, which is its own decision.

It is worth naming what that deferral costs, though, because it is the one gap
in the picture above: with no Alt, the only way to *reach* the bar is Tab.
Windows' `Alt+F` is what makes `Alt+F, X` feel like an accelerator rather than a
Tab-hunt, so this is the piece that decides whether mnemonics land as a power
feature or a curiosity. Not a reason to hold v2 — mnemonics are strictly better
than no mnemonics for a bar you tabbed to — but the follow-up is now identified.

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

### v2 rulings (2026-08-24, after v1 shipped)

Opened by one question — "can submenus have mnemonics, and what happens when
`File > Export` and top-level `Edit` both bind `e`?" — which turned out to
answer itself and take six more with it. Folded into *Mnemonics — v2* above;
this is the ledger.

7. **Mnemonics at every depth, matched against one live set.** The top-level
   items while closed, the deepest open panel's items while open, nothing else
   ever. Cross-level collision is therefore *structurally impossible* — the
   `Export`/`Edit` example has nothing to arbitrate — and `f`,`q` for
   File > Quit falls out with no new mechanism. Near-universal in the lineages;
   macOS is the only holdout and for a reason that doesn't transfer.
8. **A miss does not fall back to a shallower level** — swallow, don't jump.
   Left/Right and ESC are the routes to another menu; a mistyped letter must not
   silently tear one down and open another. Matches Windows/GTK/Qt.
9. **The bell, tied strictly to the swallow** — ✅ *the facility shipped
   2026-08-24, ahead of v2; only the wiring is left.* `Ansi::BEL` + `Screen#beep`,
   written immediately rather than folded into the frame (`return unless
   did_paint` would drop it in exactly the case it exists for). No bell when the
   cascade is *closed* — a bubbled key is not a miss. No bell for a
   matched-but-inert item or a clamped arrow: `beep ⇔ swallowed`, or the rule
   metastasizes into an audit of every no-op path. No `Screen#bell=` knob; the
   terminal owns that preference.
10. **The mnemonic match is hoisted above the cascade delegation** in
    `MenuBar#handle_key`, guarded to a single printable non-space character.
    v1's cascade swallows unrecognized keys, so without the hoist no letter ever
    reaches the bar with a menu open. `mnemonic: " "` raises at registration.
11. **Cue rules:** prefer an exact-case occurrence, else the first
    case-insensitive one; a mnemonic *absent* from the caption is legal and
    simply draws no cue (recent-files `1`…`9` is the motivating case, and
    raising would sit badly with the marker rejection's own premise that
    captions get built from data).
12. **Type-ahead search and the `fq` chord are both out** — the first is a
    second feature competing for the same keystroke (v3 candidate, with
    `List#select_next` already in place), the second needs a timeout this
    codebase argues against and is subsumed by the sequence anyway.

**Implementation rulings, settled after reading v1's paint code:**

13. **Registration validates three things** — duplicate-in-sibling-set, `" "`,
    and `Keys.printable?` plus display-width 1. The existing predicate's
    `length == 1` gives the single-cluster half for free; only the width check is
    extra. `mnemonic` is `attr_reader`: it guards an invariant `on_click` doesn't.
14. **The cue is a memoized `Item#cued_caption`**, because there are *two* paint
    sites (the strip's `segment_text`, the cascade's `renderer_for` lambda) and
    the index→column conversion must live in exactly one of them. Safe to
    memoize — no theme, `Screen` or `bg_color` input. `#caption` stays raw.
15. **Cues are always drawn.** Discoverability beats quiet, and always-draw is
    also the simpler code, so there is no tension to manage. Focused-only is the
    named fallback if the strip reads noisy; the change is one method.
16. **The beep is guarded by `Keys.printable?` and lives at the swallow site**
    (`Cascade#handle_key`'s fall-through), not up in `MenuBar`. Unguarded it
    would ring at HOME, function keys and the five-byte junk `Keys.getkey`
    returns for an unrecognized escape sequence.
17. **Two freebies, worth an rdoc line each so nobody "fixes" them:** a paste can
    never fire a mnemonic (paste is off the ladder, `handle_paste` unoverridden),
    and `with_bg` preserves attributes so an underlined mnemonic survives being
    highlighted. `Item#inspect` grows the mnemonic.

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
  click-outside wart, and (v2) the live-set sentence, the no-fallback rule, the
  `beep ⇔ swallowed` rule, the cue rules, and the mnemonic cost incl. the
  ancestor-shadowing case.
- `DECISIONS.md` `D-menu-bar` — the cascade-not-single-frame fork, the
  bar-holds-focus architecture, the rejected modal popup, the `Tabs`-look ruling
  with its two divergences, the `Popover` trigger restated, and (v2) the rung-3
  mnemonic legality argument plus the level-scoping ruling (which is *why* there
  is no cross-level collision to tie-break) and the swallow-not-fallback choice.
- (v2) `Ansi::BEL` / `Screen#beep` own their rdoc — including why the bell is
  written immediately rather than deferred into the frame, which is the trap a
  future tidy-up will otherwise walk into.
- `CHANGELOG.md`: one `Add` sentence per release.
- README **Components** table: one row, grouped with `Tabs` / `Select`.
- Book ch7: a section, plus a row in the widget-choice table (menu bar vs. tabs
  vs. select — Vaadin's "don't navigate with a menu bar" belongs there).
- `TERMINOLOGY.md`: *cascade*, *submenu* — one line each; *mnemonic* with v2
  (defining it as *level-scoped*, since that is the whole of its semantics here).
- `spec/tuile/component/menu_bar_spec.rb` and
  `spec/tuile/component/menu_bar/cascade_spec.rb`, additions to
  `list_dropdown_spec` for
  `anchor_beside` / `cursor_row_rect`, a sampler pane, and a PTY example test
  that paces its keys.
- (v2) specs for the rulings that are invisible in the code and silent under
  test: the `Export`/`Edit` same-letter case landing on Export, a miss *not*
  falling back to a shallower level, no beep while the cascade is closed, no
  beep for a swallowed *non*-printable, the exact-case cue preference, a cue
  surviving the highlight's `with_bg`, and a wide-glyph caption
  (`"Café"`/`mnemonic: "é"` — rejected at registration, but a multi-column
  *prefix* before an ASCII mnemonic still has to place the underline right).
  Plus `styled_string_spec` for `with_underline`.
  ✅ `beep` itself is already covered in `screen_spec`, including the
  `did_paint` trap.
- `rake sig`, committed in the same commit — CI gates `sig/` drift.
