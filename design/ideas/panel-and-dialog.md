# Panel and Dialog — `Window` becomes `Panel`, `Popup` becomes a bordered `Dialog`

**Status:** owner-decided in outline (2026-10-26); not started. Wait until `bottom-up-layout` merges
so the rename doesn't get mixed into the `Popup::ShrinkToContent` diff.

**Problem:** the names are the wrong metaphors. `Window` is a bordered, captioned container. It is
usually tiled (`file_commander`'s two panes, `sampler`, `hello_world`) and floats only when a
`Popup` wraps it. `Popup` is a centered, modal, ESC-closable *dialog*. A "window" suggests something
floating, movable and overlapping, under a window manager. Tuile's floating box can't be moved and
is always modal.

## The decision so far

- **`Window` → `Panel`**: the tiled bordered container. The demo apps still need it. Vaadin 8's
  `Panel` (caption + border + one content) is the closest precedent.
- **`Popup` → `Dialog < Overlay`**: modal and centered as `Popup` is today, but **it paints the
  border itself**, so it is no longer an overlay holding a `Window`.
- **The dialog-shaped subclasses extend `Dialog`, not `Panel`:**
  - `ConfirmWindow` → `ConfirmDialog`
  - `InfoWindow` → `InfoDialog`
  - `PickerWindow` → `PickerDialog`
  - `LogWindow` → `LogDialog`
- **Three components paint the same border, `Panel`, `Dialog` and `Notification`, and share the
  code that paints it.** Sharing goes through composition (a painter they call), never a common
  base class (`cop`: inherit to *be*, never to share code).
- **The border is fixed and can't be removed.** There is no `border: false` and no per-instance
  style. A borderless modal (today's `Popup` with bare content) has no user anywhere, so it goes.
- **Names not chosen:**
  - `Frame`: in this project "frame" already means one rendered screen (the Promise line: "never
    writes a frame", "no per-frame rebuild"; also the README, CHANGELOG and specs), and AWT/Swing
    `Frame` means a top-level window, the opposite meaning.
  - `Popup` → `Window`: recycles a name that was just freed, and over-promises a window manager.
  - `Dialog` was declined in `D_overlay` only for the cut where `Popup` stayed the base and silently
    changed behaviour. A full rename makes `Popup` a `NameError`, which is loud.

## Why: the downstream apps

Neither virtui nor pikuri-tui tiles a `Window` any more. Their redesign moved panes to borderless
`Layout::Vertical`s (virtui's `D_panes_are_layouts`: "once the border goes, `Window` earns
nothing"). What's left is always half of a pair, a `Window` subclass plus the `Popup` that wraps it:

- virtui: `CpuFlagsWindow`, `HealthWindow`, `VMInfoWindow` and `DiskResizeWindow` each hand-roll
  `Popup.new(content: new(...), declared_size: SIZE).open`, and `ProgressWindow` adds a private
  `MeasuredPopup`.
- pikuri-tui: `GitDiffPopup` and `Shared::Log::Popup` exist only to wrap a long-lived
  `GitDiffWindow` / `LogWindow`, and `LeaderMenu::CancelPopup` wraps a `PickerWindow`.
- Tuile itself does the same: `ConfirmWindow` has its own `MeasuredPopup`, and `InfoWindow` /
  `PickerWindow` build one in `open_in_popup`.

Merged, each pair is one object: `HealthDialog.new(...).open`. `open_in_popup` goes away, and
`#open` is `Overlay`'s (`D_popup_open`'s `#open` returning `self` carries over).

## The shared border

What `Window` paints today, and all three would get:

- the box,
- the `caption` set into the top edge (clipped and ellipsized by display width),
- the focus-lit border (`active?`; on a `Dialog` it dims while another dialog is stacked on top),
- giving the right border column to a content scrollbar (`scrollbar=`).

The helper owns **both the ink and the insets**: it paints the border *and* answers the content
rect inside it (`local_rect` shrunk by 1 on each side, 0 on the right while a scrollbar has that
column). Each of the three components asks it for the content rect in its `relayout`, and nobody
hard-codes a `1`. That keeps the later look-and-feel change to one site.

**Later, not now: a pluggable look-and-feel.** It would define, per component kind, how a border
looks (glyphs, which edges, caption placement) and how big its insets are. The helper is the seam
it would plug into. Today there is exactly one border and nothing configures it.

## What moves where

- **`Panel`** keeps `caption`, `scrollbar=` and the focus-lit border. Whether `footer=` /
  `footer_text=` survive is `Q_panel_footer`.
- **`Dialog`** gains `Window`'s chrome: `caption`, `scrollbar=` and the focus-lit border. It keeps
  everything `Popup` has: `declared_size`, `ShrinkToContent`, `close_on_key`,
  `close_on_outside_click`, modal, and the `focusable?`/`modal?` pair both true (`D_overlay`'s
  coupling).
- **`ShrinkToContent` / `measure_rows`**: today the popup asks its content (a `Window`) for its
  rows, and that answer includes the border rows. Now the `Dialog` asks its *body* and adds the
  helper's insets itself. `ConfirmWindow#measured_width` likewise adds the side insets.
- **`Notification`** stops building a `Window` (`notification.rb:123`) and paints the border with
  the helper. That is one fewer component in its subtree, and it stays a non-modal `Overlay`.
- **`LogDialog`**: a tiled log pane is already `LogTextView` plus `LogTextView::IO` (virtui does
  exactly this), so `LogDialog` only frames one. `LogWindow::IO` → `LogDialog::IO`, or delegate to
  the view's.
- **`InfoDialog`** loses `InfoWindow`'s "usable tiled or as a popup" dual use. The tiled form is a
  `Panel` around a `TextView` / `List` (`D_info_window_body`'s two presentations stay).
- The popup stack keeps its name (`ScreenPane#popups`, `Screen#add_popup`): it holds every
  `Overlay`, and once no class is called `Popup`, "popup" is a fine everyday word for anything on
  the stack. `D_overlay` already declined renaming it.

## Open

- **`Q_border_helper_shape`**: what is the shared code? A painter object each component holds (a
  `Border` value: `paint(canvas, rect, caption:, active:, scrollbar:)` plus
  `content_rect(local_rect, scrollbar:)`), a `Canvas` method, or a module? A module is the closest
  thing to "inherit to share" and is the one to argue against. `HasCaption` is a module, but it is
  an attribute, not ink.
- **`Q_panel_footer`**: `footer=` / `footer_text=` have no user in Tuile's `lib/`, virtui or
  pikuri-tui. Drop them from `Panel`, give them to `Dialog`, or keep them? `Slot` keeps a user
  either way (`ConfirmWindow`'s body slot), but its rdoc example (`Window#footer`) needs replacing,
  and so does `D_slots` / `terminology.md`'s "slot" line.
- **`Q_dialog_bg`**: does `Dialog` inherit `Window`'s background/extent behaviour as-is, or does
  becoming an `Overlay` change what `D_bg_surface`'s "composer owes `bg.default_color` + `INHERIT`"
  pair means for it?
- **`Q_laf_vs_theme`**: when the look-and-feel arrives, is it part of `Theme` (which today carries
  accents only: `D_bg_inherit`, `D_no_hint_color`) or a sibling object? Not for this change, just
  don't let the helper's signature assume either.
- **`Q_dialog_subclass_sizing`**: virtui's subclasses each carry a `SIZE` constant. Is that a
  `declared_size:` passed to `super`, or an overridden reader?

## Owed at graduation

- **Breaking CHANGELOG lines:** `Window` → `Panel`; `Popup` → `Dialog` (now bordered,
  `open_in_popup` gone); the four subclass renames; the footer (whatever `Q_panel_footer` decides).
- **`component_contract_spec`'s catalog, the README's Components table, rdoc, `sig/`** (the
  four-registration rule).
- **`D_` entries naming them**, most heavily: `D_overlay`, `D_popup_open`, `D_declared_size`,
  `D_confirm_window`, `D_info_window_body`, `D_slots`, `D_component_contract`; lighter:
  `D_notification`, `D_has_content`, `D_tree_api`, `D_combobox`, `D_tabs`, `D_key_dispatch`,
  `D_no_context_menu`, `D_no_hint_color`. A new `D_` records the merge and the names not chosen
  above.
- **The rest of the docs and code:**
  - `design/terminology.md` (caption, slot)
  - `lib/tuile/component/AGENTS.md`
  - the book (`07-components.md`, `05-focus.md` likely)
  - all three examples, plus their PTY specs
- **Downstream:** the `tuile` skill ("Window-frames-view composition"), then migrate virtui and
  pikuri-tui. Their wrapper `Popup` subclasses collapse into `Dialog` subclasses.
