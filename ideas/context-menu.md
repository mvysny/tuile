# Context Menu — the same item tree, at a point, with no strip to hold focus

**Status: ICED INDEFINITELY, decided 2026-08-24 the same day this file was
written.** Nothing built, and nothing is expected to be. The ruling and its
three reasons live in `DECISIONS.md` `D-menu-bar`'s closing update — the short
version is that right-click is the least reliable input Tuile has, no host asks
for the widget, and it would cost two new framework concepts to serve nobody.
`Context Menu` was dropped from `ideas/new-components.md` outright rather than
demoted, so this file is the only surviving design record.

**Why it is kept rather than deleted.** The research below is cheap to keep and
expensive to redo, and one finding outlived the widget: an outside click on an
open overlay notifies nobody, which `Select`, `MenuBar` and the sampler's slash
menu all feel today. That was split out to `ideas/outside-click-dismiss.md` and
is *live*. Also worth remembering if this ever thaws: no refactoring was done
for it. `MenuBar::Item` and the private `MenuBar::Cascade` stayed where they
are, and `D-menu-bar` now records the nested name as *settled* rather than
deferred — a revival pays a rename or an alias then, instead of the codebase
paying speculative generality now.

**Everything below this line is as written before the ruling**, kept in the
present tense on purpose: it is a design that was taken far enough to be sure it
was buildable, not a plan.

**The two questions this file exists to answer.** Everything else is
bookkeeping.

1. **How is it opened from the keyboard?** A menu bar is reachable by Tab
   because it is a component in the tiled tree. A context menu is not in the
   tree at all, and a terminal sends no "context menu" event — so the platform
   gives us nothing for free, where a browser hands Vaadin `contextmenu` from
   Shift+F10 and the Menu key without the component knowing. If the answer is
   "no keyboard", the widget is mouse-only, which for a TUI toolkit is close to
   a rejection.
2. **How much of `MenuBar` is reused, and where does the reused part live?**
   `MenuBar::Item`, `MenuBar::Cascade`, both, or neither — and if either moves,
   `D-menu-bar`'s deferred naming decision (`Component::MenuItem`, the
   `HasMenuItems` mixin) comes due, because the second implementation it was
   waiting for is this one.

**Scope, provisionally.** In: an item tree with nested submenus (the same one
`MenuBar` grows), per-item click listeners, mnemonics, right-click activation,
keyboard activation, ESC/arrow navigation. Out, matching `MenuBar`'s deferrals
for the same reasons: separators (a `List` has no unselectable row), checkable
and disabled items, removal/reordering/dynamic rebuild, icons, open-on-hover and
long-press (Tuile runs X10 mode 1000 — press only, no motion, no timing),
tooltips-on-items (competes with the status-bar hint idiom).

## Prior art

**Vaadin 25.2** (verified via the docs MCP, 2026-08-24). `ContextMenu` is *not*
a menu you place: you attach it to a target (`menu.setTarget(component)`, or
`grid.addContextMenu()`), and it opens on right-click or long-press.
`setOpenOnClick(true)` switches it to left-click for targets where left-click is
otherwise idle. Items come from the same `addItem(caption, listener)` shape as
`MenuBar`, sub-menus via `item.getSubMenu()`, and the docs' own "Related
components" table pairs it with `Popover` ("a generic overlay whose position is
anchored to an element"). The grid flavour (`GridContextMenu<T>`) hands the
listener the **target row** — the menu knows what was clicked. Best-practice
note worth copying into the book if we build this: a context menu is a
*shortcut*, never the only route to an action.

The keyboard story is the interesting part: Vaadin doesn't have one, because it
doesn't need one. The browser fires `contextmenu` for Shift+F10 and the Menu key
as well as for the mouse, so the component sees one event either way. **Tuile
has no such layer.** Whatever we do here, we invent.

**Desktop lineages** (from memory — verify before quoting in a decision):
Windows and GTK/Qt all bind Shift+F10 and the Menu/Apps key, and open the menu
at the *focused/selected item*, not at the mouse pointer, when invoked that way.
That split — mouse opens at the point, keyboard opens at the selection — is the
one piece of prior art that maps cleanly onto Tuile, and it decides the API
shape below (two openers, not one).

**TUI lineages** (from memory, unverified): mc has no context menu at all (F9
opens the menu bar instead); Turbo Vision has none; Terminal.Gui has
`ContextMenu` with a `Shift+F10` default and a `Position` point; notcurses has
no menu widget beyond its own. So the TUI world is thin here, and mostly says
"the menu bar is the menu" — which is itself an argument to check that this
widget earns its place (see *Open questions*, Q0).

## What the framework already gives us (verified)

- **A right-click already reaches the component under it.**
  `Layout#handle_mouse` (`lib/tuile/component/layout.rb:196`) forwards the event
  to *every* child whose rect contains the point, for any button;
  `HasContent#handle_mouse` (`has_content.rb:14`) does the same for its one
  child. `Component#handle_mouse` (`component.rb:159`) is where the button is
  finally filtered — it focuses on `:left` only. So a `:right` press descends
  the whole chain today and every component on it gets a look, **ancestor first,
  deepest last**. There is no claim protocol: `handle_mouse` returns `void`, so
  a container cannot know whether a descendant answered.
- **`:right` parses.** `MouseEvent.parse` maps X10 button code 2 to `:right`
  (`mouse_event.rb:53`), and mode 1000 (`start_tracking`) reports button
  presses.
- **A popup can only hold focus if it is modal.** `ScreenPane#handle_key` scopes
  delivery to `modal_popup || @content` (`screen_pane.rb:177`), so a *focused
  non-modal* popup is outside the scope and **every key goes dead** — the trap
  AGENTS.md spells out under *Non-modal overlays*. There is no third option: a
  self-driving context menu is modal, or it doesn't hold focus.
- **Modality already does most of what a context menu wants.**
  `ScreenPane#add_popup` (`screen_pane.rb:71`) snapshots the prior focus,
  focuses the popup and centers it; `remove_popup` restores that focus.
  `cycle_focus` (`screen.rb:710`) scopes tab stops to `modal_popup`, so **Tab is
  inert inside a modal popup with no tab stops** — no focus can escape a menu.
  Clicks outside a modal are blocked from the content
  (`screen_pane.rb:208-212`).
- **An empty-rect component paints nothing**: `Component#repaint` returns early
  on `rect.empty?` (`component.rb:116`).
- **`Cascade` is nearly reusable as-is.** Its public surface is
  `open_below(anchor, item)` / `handle_key` / `handle_mnemonic` / `close` /
  `open?` / `depth`; levels 1..N anchor themselves beside the parent's
  highlighted row and measure their own widths. Only the level-0 entry point is
  menu-bar-shaped — and the retired note already anticipated this exact seam:
  *"An earlier draft had the driver supply level 0's placement so a context menu
  could pass a point instead; with `ContextMenu` out of scope that is
  speculative generality, and the seam is one method away if it is ever
  wanted."*

And two things it does **not** give us:

- **A modality-blocked click notifies nobody.** `ScreenPane#handle_mouse` routes
  to the topmost popup *containing* the point, else to `@content` only when no
  modal is open — so a click outside an open modal is silently dropped. A
  context menu must dismiss on that click; today nothing can hear it.
- **A right-click does not move a `List` cursor.** `List::Cursor#handle_mouse`
  (`list.rb:448`) acts on `:left` only, and *"ignores non-left mouse buttons"*
  is specced in three places. So right-clicking row 7 of a file list leaves the
  cursor on row 3, and a naive "act on the selection" listener acts on the wrong
  row. See Q5.

## Four candidate designs

Every design shares the item tree; they differ in *who holds focus while the
menu is open*, which is the only structural question here.

### A — target-driven, no new machinery (`MenuBar`'s model, minus the strip)

`ContextMenu` is a plain object (not a `Component`): an item tree plus a
`Cascade`. The host component wires three things:

```ruby
def handle_mouse(event)   = @menu.open_at(event.point) if event.button == :right
def handle_key(key)       = @menu.handle_key(key) || super
def active=(flag)         = ... # close the menu when focus leaves
```

Focus never moves; the host keeps it and forwards. Framework growth: one method
(`Cascade#open_at`) plus `ListDropdown#anchor_at`.

**Why it's tempting.** It is the exact architecture `D-menu-bar` argued for, it
touches nothing, and it matches D-key-dispatch's "an app wanting `1`/`2`/`3` to
jump between panes writes a `handle_key` on its content layout".

**Why I think it loses.** `MenuBar` encodes five invariants *once* because it is
a component: close on focus loss (`active=`), close on detach (`on_detached`),
close on resize (`rect=`), swallow keys while open, and forward the mouse. In
design A every host re-encodes all five, and forgetting `on_detached` strands
panels on the pane with nothing to take them down. That is a framework invariant
leaked into N app classes — and the class of bug (an orphaned overlay) is
exactly what AGENTS.md's non-modal-overlay section exists to prevent.

### B — a modal *grab*: the cascade is the whole menu (recommended)

`ContextMenu < Popup(modal: true)` with a **zero-size rect that paints
nothing**. It is not a picture; it is a *grab* — focus holder, key scope,
lifecycle owner, outside-click sink — playing exactly the role `MenuBar`'s strip
plays. Every visible panel, level 0 included, is a `Cascade` level, so `Cascade`
is reused **verbatim** apart from one new entry point.

```ruby
menu = Component::ContextMenu.new
menu.add_item("View", mnemonic: "v") { view(row) }
menu.add_item("Delete") { delete(row) }
export = menu.add_item("Export")            # submenus nest as in MenuBar
export.add_item("PDF") { ... }

# from a host's handle_mouse:
menu.open_at(event.point)      # mouse: at the pointer
# from anywhere, incl. a global shortcut:
menu.open_below(list.rect)     # keyboard: anchored to what has focus
```

What we get for free, and it is a lot: focus save/restore
(`@popup_prior_focus`), Tab inert (no tab stops in scope), keys scoped to the
menu, mnemonics at every level (`Cascade#handle_mnemonic` already works on "the
deepest open panel"), clicks on panels routed correctly (each panel is a later,
non-modal popup, so `reverse_each.find` reaches it before the grab), clicks
elsewhere blocked.

Costs, all small but real: a *new concept* — an invisible modal popup as a pure
grab; `Popup`'s `q`/ESC must be overridden (`q` has to be usable as a mnemonic,
and ESC must pop one level before closing); and the outside-click notice has to
exist (below).

### C — the level-0 panel *is* the modal popup

`ContextMenu < Popup(modal: true)` wrapping the level-0 `List` itself; a
`Cascade` handles levels 1..N. No invisible component. Cost: level 0 is now
structurally unlike every deeper level, so the panel-driving logic (`MOVE_KEYS`
→ highlight, Enter → drill-or-fire, mnemonic → match, cursor moved → truncate
deeper) exists twice — once in `ContextMenu`, once in `Cascade` — for panels
that look identical on screen. `Cascade` also needs a public
`open_beside(row_rect, item)` so the menu can hand it an anchor from a panel it
doesn't own. **This is the asymmetry `D-menu-bar` warned about** in rejecting
the single-frame drill-down ("building it second means building it against a
shape that assumed one panel"), and it buys only the deletion of B's zero-size
rect.

### D — recursive modal popups, one per level, no `Cascade` at all

Each level is an ordinary modal `Popup` wrapping a *focusable* `List`; drilling
opens another one; `Popup`'s own ESC/`q` closes a level; the focus chain
restores itself level by level. Genuinely tiny — arrows, Enter and the mouse are
just a focused `List` doing its job, and none of the non-modal traps apply.

**Rejected on the smell, not the size:** it is a *second* menu mechanism. Item
trees, mnemonics, submenu arrows, per-level width measurement and the key map
all get a second implementation, and Tuile would ship two widgets that look
identical and share nothing. If D is right, then `MenuBar` is wrong, and that is
a much bigger conversation than this file.

**Recommendation: B.** It is the design where "a menu" means one thing in the
codebase. The two rulings it needs are the outside-click notice and the naming
of the shared parts — both worth having on their own.

## The keyboard answer

**Not mouse-only, and not a framework keybinding either.** Three layers, in
order of how sure I am:

1. **The framework ships a keyboard-shaped opener.** `open_below(rect)` (which
   is just `ListDropdown#anchor_to`, already built) anchors the menu under the
   component that has focus, which is what Windows/GTK do for a keyboard-invoked
   menu. `open_at(point)` is the mouse's. Two openers, because the desktop
   lineages are unanimous that these are two different placements — this is the
   one prior-art finding I'd defend.
2. **The app picks the key.** Rung 3 of the ladder is the sanctioned home for a
   scope-wide key (`D-key-dispatch`), and `Screen#register_global_shortcut`
   takes a Ctrl-key today. So `Ctrl+G`-opens-the-menu is a two-line app change
   and needs *nothing* from the framework. There is deliberately no
   `Component#context_menu=` slot checked inside `Component#handle_key`: almost
   no widget calls `super` from its own `handle_key` (`List` doesn't —
   `list.rb:252`), so the slot would work for ancestors-that-don't-override and
   silently not for focused leaves. Half a feature is worse than none.
3. **The conventional key needs `Keys` to grow — and one of the two doesn't
   fit.** Shift+F10 is *the* standard, and it is **unreadable today**:
   `Keys.getkey` gulps at most 5 bytes after `\e` (`keys.rb:151`, and the
   comment explains why 6 would over-read), while xterm's Shift+F10 is
   `\e[21;2~` — 6 tail bytes. The `~` would leak as a printable keypress. The
   **Menu/Apps key** (`\e[29~`, 4 tail bytes) *does* fit, as do plain F1–F12.
   So: growing `Keys::MENU` (+ the F-keys `D-menu-bar` already wants for
   global-shortcut activation) is a separate, independently useful piece of
   work; Shift+F10 additionally needs a `getkey` change and should not be
   promised. **Verify what terminals actually send for the Menu key before
   building anything on it** — and note some emulators swallow right-click for
   their own menu, which is the mouse half of the same risk.

## Reuse and naming — the decision `D-menu-bar` deferred

`D-menu-bar` reverted `Component::MenuItem` on an explicit price: *"the
promotion was priced against a breaking rename once `ContextMenu` names the
type, and that price is zero, since no release ships in between"*. **That is
still true: `MenuBar` sits in `CHANGELOG.md`'s `[Unreleased]` — 0.12.0 shipped
2026-08-17, before it existed — so no released version has ever named
`MenuBar::Item`, the rename is still free, and this is the session it was
deferred to.** Options:

1. **`ContextMenu` names `MenuBar::Item`.** Cheapest, and reads wrong at every
   call site: a context menu that has no bar returning bar items.
2. **Promote both under a `Component::Menu` namespace** — `Menu::Item`,
   `Menu::Cascade`, with `Component::Menu` itself the *collaborator both widgets
   compose*: the captionless root item plus the cascade, exposing `add_item` /
   `items` / `open_at` / `open_below` / `handle_key` / `close` / `open?`.
   `MenuBar` becomes "paint a strip + delegate"; `ContextMenu` becomes "grab
   focus + delegate". This is `D-menu-bar`'s rejected `HasMenuItems` **done as
   composition instead of a mixin**, which is the COP answer (`add_item` already
   exists exactly once, on the root `Item` — the mixin was rejected partly
   because that was already true). It also settles `Cascade`'s provisionality in
   the direction `D-menu-bar` set as the test: with two owners its interface
   stays small and it earns the class. **Its price:** `ListDropdown::Menu`
   already exists (the non-focusable `List` subclass, `list_dropdown.rb:42`), so
   `Component::Menu` and `Component::ListDropdown::Menu` would coexist and
   shadow each other inside `ListDropdown`. Rename that one (`Rows`? `Panel`?)
   as part of the move — also free right now, for the same reason.
3. **Promote only `Item`** (`Component::MenuItem`) and leave `Cascade` where it
   is, reaching into `MenuBar::Cascade` from `ContextMenu`. Half a move; the
   private machinery ends up owned by the widget that needs it least.

Leaning 2, but it is the biggest single call in this file and it is exactly the
"argue unification with the second implementation in hand" that `D-menu-bar`
asked for.

## What the framework must grow (if B)

All additive; none touches a foundation invariant.

1. **`ListDropdown#anchor_at(point, rows:, width:, max_rows:)`** — placement #3:
   the panel's top-left *is* the point, flipping up when there is no room below
   and left when none to the right, clamped to the screen. `width:`
   caller-supplied, as `D-select` requires. **This trips `D-menu-bar`'s recorded
   Popover trigger**, verbatim: *"a third placement method on `ListDropdown`
   (`ContextMenu`'s `anchor_at(point)`)"*. So the extraction must be ruled on,
   not sleepwalked past (Q3).
2. **`Cascade#open_at(point, item)`** — the second level-0 entry point, the seam
   the retired note left one method away.
3. **A modality-blocked click must notify the modal.** One line in
   `ScreenPane#handle_mouse`: `clicked ||= modal_popup`. Safe for existing
   modals — `Component#handle_mouse`'s focus grab is guarded by `active?`, and a
   modal popup is always on the focus chain, so the default stays inert; a plain
   dialog ignores it exactly as it does today. `ContextMenu` overrides
   `handle_mouse` to close. This is the *"framework-level outside-click notice"*
   `D-menu-bar` named as the honest fix for the wart `Select`, `MenuBar` and the
   sampler's slash menu all share, so it pays for itself twice. **Alternative
   considered:** a full-screen glass-pane grab that receives the click without a
   `ScreenPane` change — rejected as the more delicate of the two (a full-rect
   popup that must be taught to paint nothing, and that interacts with
   `Popup#rect=`'s `needs_full_repaint` escalation).
4. **`ContextMenu` overrides:** `reposition` (a modal `Popup` recenters every
   layout pass — `popup.rb:137`), or simply **close on resize**, which is
   `MenuBar#rect=`'s precedent and what AGENTS.md sanctions for a derived
   position; `handle_key` (ESC pops a level, `q` is a mnemonic candidate, not a
   close); `keyboard_hint` (`Popup`'s says "q Close"); `close`/`on_detached`
   (close the cascade first, or the panels outlive their key scope).

## Traps and rulings a build would hit

- **Two menus on one click path.** A right-click reaches ancestor *then*
  descendant, so two hosts on one chain both open. Proposed rule: `open_at`
  closes any other open `ContextMenu` found in `screen.popups` — cheap, follows
  `D-notification`'s "the singleton lives in the popups stack, never in a class
  ivar", and makes **deepest-wins** fall out of the existing call order for
  free. Reopening an already-open menu re-anchors rather than stacking.
- **`q` and ESC.** ESC pops one level and closes at depth 1 (as `MenuBar`); `q`
  must *not* inherit `Popup`'s close, or `q` can never be a mnemonic. Both are
  overrides, both need a spec.
- **The right-clicked row.** See Q5 — this is the one place the widget touches
  `List` semantics.
- **Type-ahead search** stays out, for the reason `D-menu-bar` gives (it
  competes with mnemonics for the same keystroke and owes a precedence rule).
- **Sampler pane.** A `ContextMenu` demo needs a host with rows worth acting on;
  the existing `List` panes or the file-commander example are the honest hosts,
  and the PTY test's key-pacing rule applies to every key including the right
  click.

## Open questions — the point of this file

- **Q0. Does it earn its place at all?** A TUI's mouse is optional, right-click
  is intercepted by some emulators, and the TUI lineages mostly answer "the menu
  bar is the menu". Is the real customer here `file_commander` (act on the row
  under the pointer), or is this completeness-driven? If there's no host that
  wants it, this file should say so and stop.
- **Q1. Design A, B, C or D?** i.e. does the menu hold focus (B/C/D, modal) or
  does the host (A)? I recommend B; A is the only one that costs the framework
  nothing, and its price is five invariants copied into every host.
- **Q2. Naming/reuse:** option 1, 2 or 3 above — and if 2, does
  `ListDropdown::Menu` get renamed in the same commit?
- **Q3. `Popover`:** `anchor_at` makes three placement methods on
  `ListDropdown`, which is the trigger `D-menu-bar` wrote down. Extract now, or
  record that the trigger fired and was consciously declined (all three callers
  still wrap a `List`, which was the original reason to decline)?
- **Q4. The blocked-click notice** (growth item 3): in scope here, or split out
  as its own idea since it fixes `Select`/`MenuBar`/slash-menu too? Splitting it
  makes this widget depend on a second unbuilt thing.
- **Q5. Does a right-click move a `List` cursor?** Three answers: (a) no — the
  app moves it, which means the app needs `event.y - rect.top + scroll_top_row`,
  an arithmetic it shouldn't have to know; (b) `List` grows a public
  `item_index_at(point)` and the app calls `select`; (c) `Cursor#handle_mouse`
  moves on `:right` too, which is what every file manager does and would break
  the specs that assert the opposite on purpose (`list_spec.rb:1367`, `:1736`).
  (b) looks right, and it is independent of menus — the same shape as
  `D-menu-bar`'s `List#select(index)` gap.
- **Q6. `Keys::MENU` + F-keys:** its own idea file (with the `getkey` 5-byte
  gulp finding, which constrains more than menus), or a line item here?
- **Q7. Does a keyboard-opened menu anchor to the focused component's `rect`, or
  to its highlighted *row*** (a `List`'s `cursor_row_rect`, which is what the
  action is about)? The second is friendlier and needs the app to supply the
  rect — which `open_below(rect)` already allows, so this may be a book
  question, not an API one.

## Registration checklist (on graduation)

rdoc on `ContextMenu` (+ whatever `Item`/`Cascade` become); a `D-context-menu`
entry, or an amendment to `D-menu-bar` if the two end up one mechanism (they
should); book ch7 "Menus" gains a section, and ch5's key table gains its keys;
the README **Components** table gains a row; `CHANGELOG.md` `Add` entries — one
per public symbol, one sentence each; `AGENTS.md` gets a **pointer line** in the
Layout list and, if B is built, whatever the grab/outside-click notice turns out
to owe the *Non-modal overlays* and key-dispatch sections; `rake sig`; a sampler
pane; and this file retires.
