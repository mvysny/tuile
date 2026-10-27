# Panel and Dialog — `Window` becomes `Panel`, `Popup` becomes a bordered `Dialog`

**Status:** owner-decided in outline (2026-10-26), reframed by the owner (2026-10-27): the root
cause is a hierarchy that encodes appearance, and the renames follow from fixing that. Not started.
Wait until `bottom-up-layout` merges so the rename doesn't get mixed into the
`Popup::ShrinkToContent` diff. **Scope: the component hierarchy only.** A configurable
look-and-feel is v2 (`look-and-feel.md`), and nothing here is designed for it.

**Problem:** the component hierarchy answers two questions at once, *what a component is* and *how
it looks*, and the second keeps winning. `Window` is the bordered, captioned container. Four classes
that are really dialogs (`ConfirmWindow`, `InfoWindow`, `PickerWindow`, `LogWindow`) extend it to
get its border. Then each grows an `open_in_popup` or a private `MeasuredPopup` to become the dialog
it was all along. `Notification` doesn't extend `Window`, but it holds one (`notification.rb:123`)
for the same reason: a component in its subtree whose only job is to paint a frame. So `Window` is
a class that is never a window. Tiled, it's a pane. Wrapped, it's a dialog. Inside a notification,
it's a frame.

The names are the visible symptom. `Window` is usually tiled (`file_commander`'s two panes,
`sampler`, `hello_world`) and floats only when a `Popup` wraps it. `Popup` is a centered, modal,
ESC-closable *dialog*. A "window" suggests something floating, movable and overlapping, under a
window manager. Tuile's floating box can't be moved and is always modal.

## The principle: a class says what a component is

- **The component hierarchy is the identity axis and nothing else.** A class, its superclass and
  its children say what the component *is* and does. `Dialog` is a modal, captioned overlay with one
  body. `Notification` is a passive, non-modal overlay. `Panel` is a captioned tile that sets itself
  apart from its neighbours.
- **Appearance is a second axis, orthogonal to the first**, and never a superclass. Whether a
  component has a border, and what that border looks like, is appearance.
- **Appearance can get into the identity axis three ways, and all three are out:**
  - a superclass inherited for its paint (`ConfirmWindow < Window`),
  - a child component held for its paint (`Notification`'s `Window`),
  - a mixin (`include Bordered` puts the look into `ancestors`, just as a superclass does).

  The first breaks `cop`'s "inherit to *be*, never to share". The other two break the same rule,
  with the inheritance spelled differently.
- **The test: imagine the border gone.** If the component still does the same job, the border is
  appearance. It belongs in the component's own `repaint`, not in its type or its subtree. A
  `Dialog` without a border is still a modal dialog. A `Notification` without one is still a
  notification.
- **A caption is identity; where it's drawn is appearance.** The caption is data (what the dialog
  is called), so `HasCaption` stays. Setting it into the top edge is the border's business.
- **Each of the three paints its own border** by calling a helper class (below). Nothing
  configures it.

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
- **`Panel`, `Dialog` and `Notification` each paint their own border, by calling one helper
  class.** It's the same border for all three. The helper is a utility, not a type: none of the
  three *is* a bordered thing, and none holds a child to get one.
- **The border is fixed and can't be removed.** There is no `border: false` and no per-instance
  style. A borderless modal (today's `Popup` with bare content) has no user anywhere, so it goes.
- **Names not chosen:**
  - `Frame`: in this project "frame" already means one rendered screen (the Promise line: "never
    writes a frame", "no per-frame rebuild"; also the README, CHANGELOG and specs), and AWT/Swing
    `Frame` means a top-level window, the opposite meaning.
  - `Popup` → `Window`: recycles a name that was just freed, and over-promises a window manager.
  - `Dialog` was declined in `D_overlay` only for the cut where `Popup` stayed the base and silently
    changed behaviour. A full rename makes `Popup` a `NameError`, which is loud.
- **Structures not chosen:**
  - A `Border` decorator component wrapping the content. That's what `Window` is today, and it's
    the problem: a node in the tree, in the focus chain and in focus repair, whose only job is ink.
  - A `Bordered` mixin: appearance in `ancestors` (see the principle above).

## Why: the downstream apps

Neither virtui nor pikuri-tui tiles a `Window` any more. Their redesign moved panes to borderless
`Layout::Vertical`s (virtui's decision on panes as layouts: "once the border goes, `Window` earns
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

**The helper is `Tuile::BorderDrawerInt`** (`lib/tuile/border_drawer_int.rb`, the owner's name).
It is Tuile-internal, marked `@api private` with the same "may change or vanish with no migration
note" line as `ComponentUtil`. The `Int` suffix says so at every call site. Apps don't call it, so
it gets no CHANGELOG line and no README row, and it isn't in `component_contract_spec`'s catalog,
because it isn't a component. It may hold state (the caption, the scrollbar flag, whatever is
convenient); its API is deliberately not settled, because the v2 look-and-feel redesigns it anyway.

It is a plain class, not a component, and owns **both the ink and the insets**. It
paints the border *and* answers the content rect inside it (`local_rect` shrunk by 1 on each side,
0 on the right while a scrollbar has that column). Each of the three components asks it for the
content rect in its `relayout`, and nobody hard-codes a `1`. That's for the three components'
sake: one answer for `relayout`, `repaint` and `measure_rows`. It is not groundwork for the v2
look-and-feel, which may reuse the helper or replace it.

## What moves where

- **`Panel`** keeps `caption`, `scrollbar=` and the focus-lit border. `footer=` was removed from
  `Window` ahead of this refactor, for having no user. `footer_text=` stays: virtui's five dialogs
  put their key hints there (`'q/ESC to close'`), so it moves to `Dialog`, and `BorderDrawerInt`
  paints it. Whether `Panel` keeps it too is `Q_panel_footer_text`.
- **`Dialog`** gains `Window`'s chrome: `caption`, `footer_text=`, `scrollbar=` and the focus-lit
  border. It keeps everything `Popup` has: `declared_size`, `ShrinkToContent`, `close_on_key`,
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

- **`Q_thin_dialog_subclasses`**: the identity test applies to the subclasses too. `ConfirmDialog`
  and `PickerDialog` are kinds of dialog: they have their own keys, buttons and result. But
  `LogDialog` is just a `Dialog` whose body is a `LogTextView`, and `InfoDialog` one whose body is a
  `TextView` or `List` built from data. Does each earn a class? Leaning: `InfoDialog` stays, since
  it takes domain data (`cop` rule 4: `InfoDialog.new("Help", text)`). `LogDialog` is open. Its
  only addition is `::IO`, and `LogTextView` already has one.
- **`Q_panel_footer_text`**: every `footer_text=` user is a dialog. Does `Panel` keep it, as cheap
  chrome `BorderDrawerInt` paints anyway, or drop it until a tiled pane asks?
- **`Q_dialog_bg`**: does `Dialog` inherit `Window`'s background/extent behaviour as-is, or does
  becoming an `Overlay` change what `D_bg_surface`'s "composer owes `bg.default_color` + `INHERIT`"
  pair means for it?
- **`Q_dialog_subclass_sizing`**: virtui's subclasses each carry a `SIZE` constant. Is that a
  `declared_size:` passed to `super`, or an overridden reader?

## Owed at graduation

- **Breaking CHANGELOG lines:** `Window` → `Panel`; `Popup` → `Dialog` (now bordered,
  `open_in_popup` gone); the four subclass renames.
- **`component_contract_spec`'s catalog, the README's Components table, rdoc, `sig/`** (the
  four-registration rule).
- **`D_` entries naming them**, most heavily: `D_overlay`, `D_popup_open`, `D_declared_size`,
  `D_confirm_window`, `D_info_window_body`, `D_slots`, `D_component_contract`; lighter:
  `D_notification`, `D_has_content`, `D_tree_api`, `D_combobox`, `D_tabs`, `D_key_dispatch`,
  `D_no_context_menu`, `D_no_hint_color`. A new `D_` records the principle (the identity axis and
  the appearance axis), the merge, and the names and structures not chosen above.
- **An invariant line**, probably in `lib/tuile/component/AGENTS.md`: a class says what a
  component is. Its border is its own paint, through `BorderDrawerInt`, and never comes from a
  superclass, a mixin or a child held for its ink.
- **The rest of the docs and code:**
  - `design/terminology.md` (caption, slot)
  - `lib/tuile/component/AGENTS.md`
  - the book (`07-components.md`, `05-focus.md` likely)
  - all three examples, plus their PTY specs
- **Downstream:** the `tuile` skill ("Window-frames-view composition"), then migrate virtui and
  pikuri-tui. Their wrapper `Popup` subclasses collapse into `Dialog` subclasses.
