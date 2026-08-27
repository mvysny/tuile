## [Unreleased]

## [0.13.0] - 2026-08-25

Tuile grows the navigation chrome an app builds its shell from — a `MenuBar`
driving a cascade of submenus, and `Tabs` / `TabSheet` — and gives up the last
row it reserved for itself: the framework status bar is gone, so `content`
fills the terminal and an app builds its own status line. A paste also stops
being a burst of keystrokes, arriving as one `Component#handle_paste` instead
of one keystroke per character.

- Add `Screen#on_focus_changed=` — a no-arg callback fired after the focused component *changes*, including to and from `nil` and on the focus repair a closing popup runs. Edge-triggered, so re-focusing what already has focus fires nothing. See `DECISIONS.md` `D_status_bar` and book ch5.
- Add `mnemonic:` to `Component::MenuBar#add_item` and `MenuBar::Item#add_item` — a letter that activates the item, underlined in its caption, matched level-scoped with no fallback, so only siblings can clash (which raises). See `DECISIONS.md` `D_menu_bar` and book ch7.
- Add `Component::List#select` and `Component::ListDropdown#select` — moves the cursor to an item by index, scrolling it into view and firing `on_cursor_changed`; the positional member of the `select_next` / `select_prev` family.
- Add `Component::MenuBar` — a one-row strip of menu captions, each dropping a cascade of submenus that nests without limit, built from `MenuBar::Item` handles minted and nested by `#add_item`, each carrying an optional no-arg `on_click`. See `DECISIONS.md` `D_menu_bar` and book ch7.
- Add a `MenuBar` shell to `examples/sampler.rb` — the side nav list becomes a menu bar grouped like the README's Components table, plus a `ComboBox` jump box at its right end, and the demo window fills everything below.
- Add a *MenuBar* pane to `examples/sampler.rb` — a three-deep File menu, an Edit menu, a top-level leaf that acts as a button, and a status line naming the last activated item.
- Add `Component::ListDropdown#anchor_beside` — places a panel against a row's right edge, flipping left when there is no room and sliding vertically, which is the cascading-submenu counterpart of `#anchor_to`.
- Add `Component::ListDropdown#cursor_row_rect` and `#on_cursor_changed=` — the highlighted row's rect, and the highlight-moved pass-through a cascading driver needs to drop the panels below the row it left.
- Add `Component::Tabs` — a one-row strip of captions with one selected: Left/Right switch immediately, a click selects, `#on_tab_selected` reports every change (`nil, nil` once the last tab goes), and tabs are `Tabs::Tab` handles minted by `#add_tab`. See `DECISIONS.md` `D_tabs` and book ch7.
- Add horizontal scrolling to `Component::Tabs` and `Component::MenuBar` — a strip narrower than its captions now scrolls to keep the selected or highlighted caption whole in view, instead of clipping it.
- Add a *TabSheet* pane to `examples/sampler.rb` — three tabs over a form, a `List` and a `TextView`, with a status line reporting every pane's state on each switch, so a hidden pane keeping its scroll position is visible rather than asserted.
- Add `Component::TabSheet` — a `Tabs` strip on its top row plus the selected tab's pane below it, added with `#add_tab(caption, pane)`; unselected panes are *detached* rather than hidden by a flag, so they keep their state and stay out of the Tab cycle. See `DECISIONS.md` `D_tabs`.
- Add `Screen#beep` and `Ansi::BEL` — rings the terminal bell for a keystroke that went nowhere. It writes immediately rather than riding the next frame, since the keys worth beeping at are precisely the ones that invalidate nothing.
- Add `StyledString#with_underline` — applies underline to every span, preserving each span's colors and other attributes; the underline counterpart of `#with_bold`. Slice and rejoin to underline part of a string, as a one-character mnemonic cue does.
- Add `StyledString#with_bold` — applies bold to every span, preserving each span's colors and other attributes; the bold-attribute counterpart of `#with_fg` / `#with_bg`. There is no `under_bold`, since bold has no inherited-unset state.
- Add `Component#handle_paste` — pasted text, whole and `\n`-normalized, delivered down the focus chain like a key but off the key ladder; the default returns false and `AbstractStringField` inserts at the caret in one mutation. See `DECISIONS.md` `D_bracketed_paste` and book ch5.
- Add `Screen#run_event_loop(bracketed_paste:)` — on by default, mirroring `capture_mouse:`; pass false for a terminal that mishandles mode 2004.
- Add `Keys::BRACKETED_PASTE_ON` / `_OFF`, `Keys::PASTE_START` / `PASTE_END`, `Keys.read_paste` and `Keys.normalize_paste` — the terminal-layer half: markers, a raw drain to the terminator, and CR/CRLF-to-`\n` plus a UTF-8 scrub.
- Add `EventQueue::PasteEvent` — the whole clipboard as one frozen event, posted by the key thread.
- Add `FakeScreen#paste` — normalizes and dispatches like the real key thread, so a spec can hand it the CR line endings terminals actually send.
- Add `Component::AbstractStringField#preprocess_paste` — the paste-side input filter; the base drops the C0 controls a text buffer cannot hold and `TextField` also flattens newlines to spaces and trims to `max_text_length`.
- Add a *Paste* pane to `examples/sampler.rb` — a submit-on-Enter prompt with submit/paste counters, so the distinction is visible (and PTY-testable).
- Add `Component::Popup#close_on_outside_click?` — a left click outside an open popup now closes it, modal or not (default true; `Component::Notification` opts out). Fixes dropdowns and menu cascades stranded by a click on inert decoration. See `DECISIONS.md` `D_outside_click`.
- Add `Component::Popup#owner` — names the component an overlay is part of, so a click inside it doesn't dismiss the popup hosting it. `ComboBox`, `Select` and each `MenuBar` cascade panel set it; an overlay without one is independent.
- Add `Component::Popup#on_close` — a no-arg callback fired once the popup has left the screen, however it left; for a driver keeping its own record of what is open.
- **Fix:** `Component::TabSheet` no longer holds a removed tab's pane against re-use — `Tabs::Tab#remove` bypasses `TabSheet#remove_tab`, and the stale mapping made `add_tab` reject that pane as still in use.
- **Fix:** a container whose children exactly tile its rect no longer swallows the repaint cascade — content under it survives an ancestor's `clear_background` instead of vanishing until the next unrelated repaint (visible in the sampler as rows blanking when focus moved). See `DECISIONS.md` `D_repaint_cascade`.
- **Fix:** a multi-line paste into a `Component::TextArea` subclass that rebinds ENTER no longer fires that binding once per pasted line ([#4](https://github.com/mvysny/tuile/issues/4)).
- **Fix:** `Component::TextArea`'s rdoc had the two line-break bytes backwards — a pasted break arrived as `\r`, not `\n`.
- **Fix:** `Component::TextView#handle_key` no longer refuses every key while the view is unfocused — a vestigial `active?` guard that 0.8.0's dispatch overhaul dropped from every other widget — so hand-feeding it a scroll key scrolls, as with any other component. See `DECISIONS.md` `D_text_view_scroll_verbs`.
- **Breaking:** `Component::TextField#left_column` is now private — the horizontal scroll offset was internal state with no caller outside the field. A spec asserting the scrolling reads it through `send(:left_column)`.
- **Breaking:** the framework status bar is removed — `ScreenPane#status_bar` is gone and the pane no longer reserves the bottom row, so `content` now fills the whole terminal. Build a status line into your own layout and fill it from `Screen#on_focus_changed=`; `examples/hello_world.rb` and `examples/file_commander.rb` show the shape. See `DECISIONS.md` `D_status_bar`.
- **Breaking:** `Component#keyboard_hint` is removed, along with its overrides on `Popup`, `PickerWindow`, `MenuBar`, `Tabs`, `Select`, `ComboBox` and `Notification` — four of them were unreachable in every configuration. Keep the method on your own window classes and call it from your status line; nothing in Tuile consults it now.
- **Breaking:** `Screen#register_global_shortcut` no longer takes `hint:` — the registry runs actions, it does not describe them. Drop the argument and write the hint into your own status line, next to the registration.
- **Breaking:** `Screen#active_window` is removed — it existed only to pick the component the status bar asked for a hint. Walk up from `Screen#focused` instead, which is the direction a key actually bubbles.

## [0.12.0] - 2026-08-17

`Component::List` becomes a list of *items* rather than of pre-rendered rows: it
holds objects of any type plus a `renderer`, renders only what is on screen, and
hands your callbacks the item itself. The five components that compose a list are
folded onto it. The framework also settles its scrolling vocabulary in one
pass: `row` is the terminal grid unit everywhere, `line` means exactly what
`String#lines` returns, and `items` are the domain objects a widget renders.

- Add `Component::List#items` / `#items=` and `#renderer` — the list holds typed items, one row each, and a renderer turns an item into its row. See `DECISIONS.md` `D_list_items` and book ch7.
- Add `Component::List#refresh_rows` — re-renders every row when the renderer's *inputs* changed (a group's selection) while the items and the renderer did not.
- Add `Component::List#build_lines` — the verb-named builder that `#lines`'s block form used to be: it yields a growing `Array` and assigns it through `#lines=`.
- Add `Component::ListDropdown#items` / `#items=` / `#renderer=`, forwarding to its list.
- Add `Component::Notification` — the corner toast: `Notification.show("Saved")` floats a non-modal box in the top-right for three seconds, stacking a burst into one box that drains one message every tick. See `DECISIONS.md` `D_notification` and book ch7.
- Add `Component::TextArea#caret_row` and `#row_count` — the two readers that answer "has Up/Down anywhere left to go?", so a subclass can claim the key at the text's edge and delegate elsewhere. See `DECISIONS.md` `D_text_area_rows`.
- Add `Component::TextView#scroll_half_page_up` / `#scroll_half_page_down` — the programmatic form of `Ctrl+U` / `Ctrl+D`, for a host paging a view it does not focus. See `DECISIONS.md` `D_text_view_scroll_verbs`.
- Add `TERMINOLOGY.md` — a glossary of Tuile's house words, looked up by term; the rules live in `AGENTS.md`'s *Nomenclature* section and the reasoning in `DECISIONS.md` `D_scroll_nomenclature`.
- `Component::List` now renders lazily: only the rows in the viewport, memoized until `items=`, `renderer=` or a width change. A renderer therefore runs at paint time and must stay pure and cheap.
- `Component::List#lines=` is unchanged and stays supported: it splits on `\n` and stores the resulting `StyledString`s *as* the items, so a line-populated list behaves exactly as before.
- `Component::List::Cursor`'s count parameters are renamed `item_count` and `viewport_rows` (a cursor indexes items; only the paging half counts rows). They are positional, so no caller changes — a `Cursor` subclass overrides against the new names.
- `Component::Popup#open` now returns `self`, so construct-and-mount is one expression: `Popup.new(content: window).open`.
- **Fix:** `Component::TextView`'s half page is floored at one row, so `Ctrl+U` / `Ctrl+D` also move in a one-row viewport.
- **Fix:** `examples/file_commander.rb` navigates again — Enter on a directory called `Rainbow.uncolor` on a `StyledString` and raised.
- **Breaking:** `Component::List#on_item_chosen` and `#on_cursor_changed` now receive `(index, item)` rather than `(index, line)`. A list populated by `lines=` is unaffected (its items *are* the `StyledString` rows); one populated by `items=` must expect its own objects.
- **Breaking:** `Component::List#lines` (the reader) is removed — it returned the items, and the name lies once a `renderer` is set. Read `#items`; for the block form call `#build_lines`; to assert what a list *shows*, assert the painted buffer.
- **Breaking:** `Component::ListDropdown#lines=` / `#lines` are removed — use `#items=` with a `#renderer=`. See `DECISIONS.md` `D_list_items`.
- **Breaking:** `Component::List#add_line` and `#add_lines` are removed — an append is a statement about a collection the list owns, which a lazily-sourced provider has nothing to mutate. Keep your own array and assign it whole (`list.items = mine`); for incremental append use `Component::TextView`. See `DECISIONS.md` `D_list_items`.
- **Breaking:** `Component::Popup.open` (the class method) is removed — it hardcoded `Popup.new`, so every subclass inherited a factory that silently built a bare `Popup`. Write `Popup.new(...).open`, which now returns the popup. See `DECISIONS.md` `D_popup_open`.
- **Breaking:** `Buffer#set_line` is now `#set_text` and `Component#draw_line` is now `#draw_text` — both write a `StyledString` starting at `(x, y)` and never filled a row. Rename the calls; behavior is unchanged.
- **Breaking:** `Component::List#top_line`/`=` and `Component::TextView#top_line`/`=` are now `#scroll_top_row`/`=`, and `Component::TextArea#top_display_row` is now `#scroll_top_row`. Rename the accessors.
- **Breaking:** `VerticalScrollBar.new(line_count:, top_line:)` is now `.new(row_count:, scroll_top_row:)`. Rename the keywords.

## [0.11.0] - 2026-08-12

- Add `Component::Select` — a one-row enum field that drops open a `ListDropdown` of its typed `items`; `value` is the selected item, and Enter, Space or Down opens it. It claims no printable key but Space, so a form's own letter bindings keep working while it has focus. See `DECISIONS.md` `D_select` and book ch7.
- Add `Component::Layout::Vertical` and `Component::Layout::Horizontal` (on the abstract `Component::Layout::Box`) — declarative 1-D layouts where a caller *declares* each child's extent (`Fixed` / `Percent` / `Expand`, plus box-global `spacing`, `padding` and a per-child `align:`) instead of computing it. See `DECISIONS.md` `D_box_layouts` and book ch3.
- Add `Component::BigDecimalField` — the money field: the shape of `IntegerField`/`FloatField` with an exact `BigDecimal` (or `nil`) value, where assigning a `Float` raises rather than converting. See `DECISIONS.md` `D_bigdecimal_field`.
- Add `Component::FloatField` — the `IntegerField` twin whose `value` is a `Float` (or `nil`), accepting a single `.` and stepping by `1.0` on Up/Down; `value=` raises on a NaN or infinity. See `DECISIONS.md` `D_float_field`.
- Add `Component::ListDropdown#anchor_to(anchor, rows:, width:, max_rows:)` — placement now lives on the dropdown: below the driver, flipped above when the rows won't fit beneath, and slid left to stay on screen. Width stays a caller decision.
- `bigdecimal` is Tuile's first optional dependency and is deliberately not in the gemspec: only an app naming `Component::BigDecimalField` loads it, and doing so without the gem raises `LoadError` with the fix in the message. A Bundler app on Ruby 3.4+ must name `bigdecimal` in its own `Gemfile`.
- `examples/sampler.rb` gains `Select`, `FloatField` and `BigDecimalField` panes, and its demo panes are ported to the box layouts.
- **Fix (behavior):** `StyledString#wrap` no longer eats a **first-line** indent, so indented text is displayable at all (every `Component::TextView` line goes through `wrap`). `plain("   ").wrap(5)` is now `["   "]` rather than `[""]`; continuations still start at column 0. See `DECISIONS.md` `D_wrap_leading_space`.
- **Fix (behavior):** a `Component::ListDropdown` that scrolls now shows a scrollbar — `List`'s `scrollbar_visibility` defaults to `:gone` and the dropdown never changed it, so an 11-match `ComboBox` looked identical to a 10-match one.
- **Fix:** `Component::ComboBox` no longer hands its inner `TextField` a one-row rect when its own rect is zero-height — a child painting outside its parent, which a box layout can provoke by starving an over-subscribed child.
- **Breaking:** `Component::ComboBox::MAX_VISIBLE_ROWS` moved to `Component::ListDropdown::MAX_VISIBLE_ROWS`. Update the constant reference.
- **Breaking (behavior):** `Component::Checkbox` now toggles on **Enter** as well as Space, matching a checkable row inside a `List`. A focused checkbox therefore consumes Enter, so an ancestor's Enter-to-submit must move to a key no focused field claims. See `DECISIONS.md` `D_boolean_fields`.

## [0.10.0] - 2026-08-02

- Add `Component::Checkbox` — a one-row boolean input (`[x] Enable syslog forwarding`) toggled by Space or a left-click, whose `value` is always `true`/`false`, with `checked?`/`checked=`/`toggle` as the domain-word face over it. See `DECISIONS.md` `D_boolean_fields`.
- Add `Component::CheckboxGroup` — multi-select over typed `items` whose `value` is a **frozen** `Set` of the selected items, iterating in toggle order (use `items & value.to_a` when order matters). See `DECISIONS.md` `D_checkbox_group`.
- Add `Component::RadioGroup` — single-select over typed `items` whose `value` is the selected item; it composes a `List`, so the cursor roams without selecting and Space, Enter or a click commits the row under it. See `DECISIONS.md` `D_radio_group`.
- Add `Component::IntegerField` — a single-line input whose `value` is an `Integer` (or `nil`), accepting only digits and a single leading `-`, with Up/Down stepping by one; it composes a `TextField` rather than subclassing one.
- Add `Component::PasswordField` — a `TextField` painting one mask glyph per character (`mask_char=`, default `*`) with a `revealed=`/`revealed?` toggle; while masked, word-jumps collapse to the ends of the buffer so the mask can't leak word boundaries.
- Add `Component::TextField#display_text` — the protected seam a subclass overrides when it paints something other than `text`, since the caret, the scroll window and click-to-position all measure it. The contract is one display character per `text` character, in order.
- Add `Component::ProgressBar` — a display-only fill over a `Range` with `fraction`/`percent` readers and an `indeterminate` mode owning a 5 fps ticker; it stays deliberately outside `Component::HasValue`. See `DECISIONS.md` `D_progress_bar` and `D_color_slots`.
- Add `Component#on_attached` / `on_detached` — lifecycle hooks fired once per component per transition, letting a component own a mounted-lifetime resource. They are hooks, not destructors: a process exiting without `Screen#close` fires nothing. See `DECISIONS.md` `D_attach_hooks`.
- Add `Component::HasCaption` — the caption seam included by `Button` and `Window`, coining the naming split (**caption** is app-authored chrome, **text** is the user-editable value) and making `is_a?`-plus-caption tree lookups possible.
- `Component::HasValue` now carries `focusable? = true` (overridable). `tab_stop?` is deliberately not folded in: it stays `true` on the leaf `AbstractStringField` and `false` on the composing wrappers, whose inner field carries the stop.
- `Component::ComboBox` and `Component::IntegerField` compose their inner field via `Component::HasContent` instead of hand-rolling `children`/`rect=`/`on_focus`, so their `content`/`content=` are consequently public.
- `Component::Window#caption` and `Component::Button#caption` accept a `String | StyledString | nil` and are built, clipped and ellipsized by **display** width, so a CJK/emoji caption no longer overruns the frame or the rect.
- `Screen#close` now unmounts the component tree (via `ScreenPane#detach_all`), so teardown fires `on_detached` across it.
- `items=` is chrome on `ComboBox` and on both group components: it never touches `value`, so an absent value renders as nothing selected and survives intact, with no reconcile step, clamp or silent drop.
- `examples/sampler.rb` gains panes for `ProgressBar`, `RadioGroup` and `CheckboxGroup`.
- Fix the caret stepping by *character* rather than by grapheme cluster: LEFT/RIGHT, BACKSPACE and DELETE now move over and delete exactly one cluster, and the caret is boundary-locked so a mid-cluster position is unrepresentable. See `DECISIONS.md` `D_cluster_caret`.
- Fix `Component::TextArea` hanging the UI thread on text containing `\r`, `\v` or `\f` — the word-scan measured zero and the wrap loop never advanced, so `area.text = File.read(crlf_file)` was enough to lock up an app. See `DECISIONS.md` `D_text_area_columns`.
- **Breaking:** `Component#children` is final, and reparenting goes through the protected `add_child(child, at:)` / `remove_child(child)` / `detach_child(child)`. A custom container must stop overriding `children` or hand-wiring `child.parent = …`; named slots become readers over the array. See `DECISIONS.md` `D_tree_api`.
- **Breaking:** `Component#attached?` is now the one-axis type test `root.is_a?(ScreenPane)` — it consults no `Screen`, so it never raises and a tree can be assembled with no screen in the process. See `DECISIONS.md` `D_tree_first`.
- **Breaking:** the UI-thread guard is rewritten — `EventQueue#locked?` becomes `#running?` plus `#on_loop_thread?`, the internal `@pretend_ui_lock` and `FakeScreen#check_locked`'s bypass are gone, and `Screen#state` is added. A spec mutating UI from a *spawned* thread now raises exactly as an app would. See `DECISIONS.md` `D_screen_lifecycle`.
- **Breaking:** `Component#key_shortcut` and `#find_shortcut_component` are removed, along with `ScreenPane#handle_key`'s capture phase and `Window`'s `[k]-Caption` border prefix. Migration: `w.key_shortcut = "1"` becomes a `case` in the containing layout's own `handle_key`. See `DECISIONS.md` `D_key_dispatch`.
- **Breaking:** `Screen#register_global_shortcut` now also rejects `Screen::EDITING_KEYS` — `ENTER`, `BACKSPACE`, `DELETE` and the arrows — which silently broke `TextArea` newlines app-wide. Bind those on an ancestor's `handle_key` instead; `HOME`/`END`/`PAGE_UP`/`PAGE_DOWN` stay legal.
- **Breaking:** `Component::TextInput` is renamed `Component::AbstractStringField` (file `text_input.rb` → `abstract_string_field.rb`). Only code referencing the constant directly must update.
- **Breaking:** `Component::Button#caption` and `Component::Window#caption` return a `StyledString`, not a `String`. Measure with `caption.display_width` and recover the plain text with `caption.to_s`.
- **Breaking (behavior):** all glyph measurement is now per grapheme cluster under one emoji policy (`:rgi`), so `"👍🏽"` measures 2 columns rather than 4 and no longer overruns its cell. Custom components measuring with `String#length` or iterating `each_char` must move to `StyledString#display_width` / `slice` / `ellipsize`. See `DECISIONS.md` `D_cluster_width`.
- **Breaking (behavior):** `Component::TextField` separates the caret's character index from its terminal column and **scrolls horizontally** instead of being capped by its own width. `max_text_length` is now an explicit, settable cap defaulting to `nil` (unbounded) rather than the derived `rect.width - 1`. See `DECISIONS.md` `D_text_field_axes`.
- **Breaking (behavior):** `Component::Button#handle_mouse` fires `on_click` only within the button's painted **extent**, not anywhere in its `rect`, and `Component::Checkbox` follows the identical rule. A click on the blank tail still focuses the button but no longer activates it.

## [0.9.0] - 2026-07-05

Layout is now strictly top-down: a parent assigns each child's `rect`, and components no longer advertise how big they want to be. The book's chapter 3 is the long-form rationale.

- Add `Tuile::Fraction` (`HALF` / `FULL`, int-coercing, floor-at-1 `resolve`) — the one relational sizing primitive, scoped to `Popup#size=`.
- Add optional `Component::Label.new(text = nil)` — constructor symmetry with `Window.new(caption)`, reusing the `text=` coercion path. Purely additive; `Label.new` still works.
- Add `EventQueue#tick_fps(fps)` = `tick(1.0 / fps)` for the frames-per-second animation idiom; lands on both the real and fake queues.
- `Component::Popup#size=` accepts a `Size` (clamped to the screen) or a `Fraction` (re-resolved on every layout pass, so it tracks resize), default `Fraction::HALF`; popups no longer auto-size to their content.
- `Component::Window`: the single footer slot splits into `footer_text=` (a `StyledString` embedded into the bottom border line, mirroring `caption` on top) and `footer=` (a focusable component spanning the full inner width of the bottom row), the latter hiding the former.
- Fix `Buffer#flush` corrupting the left neighbour of a wide glyph: a dirty continuation cell no longer opens a flush run, so an adjacent change no longer blanks the glyph (an emoji vanishing, persisting across tmux window switches).
- Memoize display-width measurement in `Buffer` and measure each grapheme once per paint: a full-screen 160×50 repaint drops from ~29.5ms to ~5.8ms (~5×). Adds `rake benchmark`.
- **Breaking:** the eager bottom-up sizing channel is deleted — `Component#content_size` / `content_size=` / `on_child_content_size_changed`, plus 0.8.0's `popup_min_height` / `popup_max_height`. A custom component that advertised a size must move that logic into its parent's `rect=`.
- **Breaking:** `Tuile::Sizing` (`FILL` / `WRAP_CONTENT` / `Sizing.fixed`) and `Window#footer_sizing`, both added in 0.6.0, are removed — a bottom-row `footer=` widget is always FILL by construction.
- **Breaking:** `EventQueue#tick(seconds)` now takes an interval in **seconds**, not frames-per-second. `tick(4)` used to mean "4 times a second" and now means "every 4 seconds"; use the new `tick_fps(fps)` for the animation mental model.

## [0.8.0] - 2026-06-11

- Render through a back buffer: `Screen#buffer` is now a `Tuile::Buffer` cell grid, and `Screen#repaint` flushes only the cells that changed since the last frame in one synchronized-output batch — flicker-free on **any** terminal, since an unchanged cell is never rewritten.
- Add non-modal popups (`Component::Popup.new(modal: false)`) — they paint on top but don't center, grab focus, capture keys or block clicks, which is the building block for autocomplete menus anchored to a caret. `ScreenPane#modal_popup` is the topmost *modal* popup, through which all modal-owner reads now route.
- Add `Component::TextInput#on_key` — an interceptor consulted before the input's own key handling (a truthy return consumes the key), letting app code layer Up/Down/Enter/ESC onto a field without subclassing.
- Add `Component#popup_min_height` / `popup_max_height` — content components can advise a wrapping `Popup` of preferred height bounds, which `Component::LogWindow` uses to grow from half-screen to full-screen as the log fills.
- Add an `examples/sampler.rb` "Slash menu" demo: a `TextArea` whose `on_change` refills a non-modal `Popup`-wrapped `List` anchored to the caret, with focus and caret staying in the field throughout.
- `Component::LogWindow` now renders through a `TextView`, so long log lines wrap instead of being ellipsized.
- **Breaking:** components paint into `Screen#buffer` via `set_line` / `fill` / `set_char` instead of writing escape sequences through `screen.print`. Custom components that drew via `screen.print(move_to, ansi)` must migrate to the buffer API.
- **Breaking:** key dispatch is centralized into a capture + bubble model in `ScreenPane#handle_key`, and a component's `handle_key` now acts on the key alone rather than gating on its own `active?` state. `Layout`/`Window`/`HasContent#handle_key` are removed and the `active?` guards in `TextInput`/`List`/`Button` are dropped.

## [0.7.0] - 2026-06-09

- Lower the Ruby floor to 3.3 (was 3.4): replaced the `it` implicit block parameter (3.4+) with `_1` throughout, and added 3.3 to the CI matrix.
- Fix `Component::Popup#close` raising `Tuile::Error` when the popup was not open — it is now the documented no-op (also covering a double `close`). `Screen#remove_popup` guards on `has_popup?`; `ScreenPane#remove_popup` keeps its strict internal assertion.

## [0.6.0] - 2026-06-07

- Add `Tuile::Theme` — semantic color tokens for the accents built-in components paint (`active_bg_color`, `input_bg_color`, `active_border_color`, `hint_color`) with `DARK`/`LIGHT` presets, living at `Screen#theme`; everything that isn't an accent keeps inheriting the terminal's own default fg/bg.
- Add `Tuile::ThemeDef` — an app's dark/light `Theme` pair. Assigning `Screen#theme_def=` is the durable way to theme an app, where a bare `theme=` is transient; construction validates that both members declare the same custom key set.
- Add `ThemeDef.default` — the definition newly-constructed screens start from. Reassign it once in `spec_helper.rb` and every `Screen.fake` carries the app's custom tokens, instead of repeating `theme_def=` in each `before` block.
- Add app-specific theme tokens: `Theme#custom` (`Hash{Symbol => Color}`), looked up fail-fast via `Theme#[]` and rendered via the generic `#fg`/`#bg` helpers. Subclass `Theme` to add one coloring function per custom token — `Data#with` preserves the subclass.
- Add `Component#on_theme_changed` — fired pre-order across the attached tree on every theme change, so apps can rebuild styled content whose colors came from the old theme. Override it (calling `super`) or assign the `on_theme_changed=` proc.
- Add `Color.hex` — a 24-bit RGB color from a CSS-style hex string (leading `#` optional, case-insensitive, 3-digit shorthand expands as in CSS). Alpha forms are rejected: SGR has no alpha channel.
- Add `Tuile::Sizing` (`FILL` / `WRAP_CONTENT` / `Sizing.fixed(n)`) and `Window#footer_sizing` — the footer slot is sized per policy against the inner width, and is excluded from `Window#content_size` since decoration must not drive window size.
- Name the 256-color palette: a constant per standard xterm chart name for indices 16..255 (`Color::CADET_BLUE`, `Color::GREY37`, …), listed in `Color::PALETTE_NAMES`; indices 0..15 keep the symbolic constants, which respect the terminal's own scheme.
- Auto-detect the light/dark terminal background at startup: `Screen.new` queries the terminal via OSC 11 (`COLORFGBG` fallback, dark when inconclusive) and picks the matching preset.
- Follow OS light/dark appearance flips live via mode 2031 (kitty, foot, contour, ghostty, …): the screen re-picks the matching theme and repaints everything.
- `Component#content_size` is now maintained eagerly via the protected `content_size=` setter, which fires `parent.on_child_content_size_changed(self)` only on a real change; this fixes an open `Popup` not re-sizing when its content grew.
- **Breaking:** `rainbow` is no longer a runtime dependency (nothing under `lib/` uses it). Apps that style text with Rainbow must add it to their own Gemfile.

## [0.5.0] - 2026-05-21

- Add `Tuile::Color` — a value type wrapping the four color forms ANSI understands (named Symbol, 256-color Integer, RGB Array, or `nil`), with constants for the 16 named ANSI colors and a `Color.coerce` that accepts raw forms transparently.
- Add `Component::TextView::Region` — an opaque handle to a contiguous run of hard lines, so apps can stream into logical sections without tracking line indices across sibling mutations; create with `view.create_region`, and detached handles raise on every reader and mutator.
- Add `Component::TextView#replace(range, str)` and `#insert(at, str)` for mid-buffer hard-line splices (Integer or Range, empty range == insertion, `begin == hard-line count` valid for end-insertion).
- Add `EventQueue#tick(fps) { |n| ... }` returning a `Ticker` backed by `Concurrent::TimerTask`; it fires on the event-loop thread with a 0-based monotonic counter and auto-cancels on raise.
- Add `FakeEventQueue#tick` and `FakeTicker` — a synchronous test double that drives ticks deterministically.
- `Component::Label`: add a `bg` accessor applying a background color uniformly across every painted row — text, trailing pad, and blank rows past the last line.
- `Component::TextView`: incremental wrap via a per-hard-line row-count cache — a mid-buffer mutation now re-wraps only the affected slice instead of the whole buffer, speeding up the LLM streaming path.
- **Breaking:** `StyledString::Style#fg` and `#bg` now return `Color` (or `nil`) instead of the raw `Symbol`/`Integer`/`Array`. `Style.new` and `#merge` continue to accept the raw forms via `Color.coerce`.
- **Breaking:** `StyledString::Style::COLOR_SYMBOLS` is removed — it moved to `Color::COLOR_SYMBOLS`.
- **Breaking:** `EventQueue#run_loop` now yields submitted `Proc` events to its consumer block instead of dispatching them inline, so a raise from a `submit{}` block routes through `Screen#on_error`. Custom `run_loop` consumers must `call` Procs in their case statement.

## [0.4.0] - 2026-05-20

- Add `Screen#register_global_shortcut` for app-level hotkeys; registered shortcuts surface in the status bar via `hint:`.
- Add `Keys::CTRL_A..CTRL_Z` constants and `Keys.printable?` (extracted from `TextField`/`TextArea`/`Screen`).
- Extract `Component::TextInput` as the shared base of `TextField` and `TextArea`; add `#empty?`.
- `TextField`/`TextArea`: default `on_escape` to clear focus.
- `Screen#run_event_loop` accepts `capture_mouse:` (default `true`); pass `false` to skip xterm mouse tracking so the terminal's native select-to-copy keeps working.
- `StyledString`: add `#with_fg`, mirroring `#with_bg`.
- `Component::TextView`: add `#<<`, `#add_line`, `#empty?`, and `#remove_last_n_lines` for streaming-tail retraction.
- `MouseEvent`: map buttons 66/67 to `:scroll_left`/`:scroll_right`.
- `Component::LogWindow`: extract `#log` helper.
- `Component::List`: skip `auto_scroll` when rect is empty; re-snap on width change; snap cursor to last line on `auto_scroll`.
- Document `Component#repaint`'s attached-only call contract.
- Document keyboard input dispatch order and testing (`FakeScreen`, PTY system tests) in the README.
- **Breaking:** `Component::TextView#append` is now verbatim — chunks concatenate onto the current last hard line, embedded `\n` becomes hard breaks, and no implicit newline is inserted (aliased as `<<`). The old "add a new entry" behavior is now `Component::TextView#add_line`.
- **Breaking:** `MouseEvent.parse` raises on malformed input instead of silently truncating.
- Fix: `Component` gates `invalidate` and `repaint` on `attached?`, dropping the negative-rect relic.
- Fix: `Popup` recomputes size from content on every `#open`.
- Fix: `Keys.getkey` reads 5 trailing bytes after ESC, not 6.
- Fix: `Component::List#add_line` rejects `nil`.

## [0.3.0] - 2026-05-18

- Add `Component::TextView` — read-only scrollable wrapped prose with word wrap, incremental append, and a lazy text reader.
- Add `Tuile::StyledString` for span-modeled ANSI styling, with `#wrap` (span-preserving word wrap), `#ellipsize` (width-bounded truncation), `#with_bg`, and an `EMPTY` shared instance.
- Model `Label`, `List`, and `TextView` text as `StyledString`; pre-pad clipped/physical lines.
- Extract `Tuile::Ansi` for shared ANSI helpers.
- `Window#scrollbar=` accepts any content that exposes `scrollbar_visibility=`.
- Document `TextView` in the README and `examples/sampler.rb`.
- Remove `Tuile::Wrap` (superseded by `StyledString#wrap`).
- Remove `Tuile::Truncate` (superseded by `StyledString#ellipsize`).

## [0.2.0] - 2026-05-15

- Add `Component::TextArea` with multi-line editing, word navigation, and VT220-style Home/End handling.
- Add `Component::Button`.
- Add Tab / Shift+Tab focus cycling.
- Add Ctrl+arrow word navigation to `Component::TextField`.
- Add `Component::List#on_cursor_changed`.
- Add `examples/sampler.rb`.
- Paint `TextField` with a colored background.
- Buffer `Screen#print` into a per-frame buffer during repaint, and release it on exception.
- Join the key thread after killing it in `run_loop`'s ensure block.
- Auto-clear gappy children in `Component#repaint`.
- Inline a minimal truncation helper and drop the `strings-truncation` dependency.
- Lower the Ruby floor to 3.4; pin CI head to 4.0; fix Ruby 3.4 compatibility.
- Bump `minitest` to 6.0.
- Document `TextField` SGR constants; refresh `sig/tuile.rbs`.

## [0.1.0] - 2026-05-02

- Initial release
