# AGENTS.md — `lib/tuile/component/`

The widget set's must-not-break list, loaded beside the root file when work touches this
directory. One-line invariants and pointers only — the per-symbol truth is each class's rdoc, the
argument is `design/decisions.md`. Root seams are not restated here; `Box` constraints are in
`layout/AGENTS.md`. Cap 10 KB.

## Seams

### The value seam

- **`caption` is chrome, `text` is value** — two mixins because a component may carry both; read
  through `caption`, never `@caption`.
- **{Component::HasValue} is the input-field mixin, not just a value seam** — it carries
  `focusable?` but deliberately **not** `tab_stop?`: exactly one stop per widget, so a wrapper
  composing a field claims none. A `value` that isn't a *field* stays out ({Tuile::Component::ProgressBar}).
  See `D_has_value`, `D_progress_bar`.
- **A value is typed, and the field is named after its value's Ruby class** — `Integer` →
  `IntegerField`. Model-mapping is a layer above; *empty* is per-component, declared in
  `empty_value`. See `D_float_field`.
- **A field whose parse can fail includes {Component::HasBadInput}, and empty input is never bad
  input** — derived on read, never cached, and a form asks `bad_input?` *before* `empty?`. See `D_bad_input`.
- **A rule's verdict is a different channel with a different writer** — the field never writes
  `error_message`; the validator is sole writer and owes *set or clear on every pass*. See `D_has_validation`.
- **A new field with a partial parse owes the red well a *settling* decision** —
  `bad_input_settled?` is `true` by default, wrong where every prefix is bad input; gate the **ink**
  only, never the pull. See `D_date_field`.
- **A field paints no caption and no message**, so it must not include {Component::HasCaption} —
  the container owning those cells owns both, and the message notice is load-bearing because the
  field never invalidates them. See `D_caption_ownership`.
- **`items` is chrome; `value` is authoritative and may hold what `items` doesn't** — `items=` never
  touches `value` and fires nothing. No reconcile, no clamp, no silent drop. See `D_combobox`.

### Composition

- **A typed field subclasses {Component::AbstractWrappingField}** and defines only `value` /
  `value=`; the base owns the editor, focus forwarding, the one well and the commit. An
  *editor-shaped* knob is not forwarded. See `D_wrapping_field`.
- **{Component::HasContent} means "a *primary* child you populate"**, not "one child" — private
  machinery is owned outright, or exposed read-only (`CheckboxGroup#list`).
- **A {Tuile::Component::Slot} is transparent in all three channels** — not focusable, mouse
  descends through it, `on_child_removed` forwards to the parent. See `D_slots`.
- **What the buffer may hold is decided in `insert_text`, and nowhere else** — typing, the ENTER
  newline and a pasted clipboard all land there. See `D_input_filters`.
- **The filter tests the whole resulting buffer, not the fragment**, and only works while the
  grammar is prefix-closed; a date is not, so such a field *reports* bad input instead. A **partial**
  filter reads as a guarantee and isn't.
- **A group composes a `List` and owes four things** — install a `List::Cursor` (a bare `List` sits
  at `-1`), paint from `rect.left + 1`, re-render through `refresh_rows`, clamp the cursor when the
  items shrink. `radio_group.rb` is the model. See `D_radio_group`.
- **Duplicate rather than DRY a shallow shell** — `FloatField` is a deliberate near-copy; a
  **fourth** copy is when to re-argue it, three is not. See `D_float_field`.

### Lists and dropdowns

- **The renderer runs at paint time on any frame, so it is a pure, cheap function of its item** —
  work reaching a service belongs in the item. See `D_list_items`.
- **Search renders without memoizing** — don't move the scan onto the cached path; one failed
  scan would otherwise grow the cache to a row per item.
- **Every input to a row's geometry drops the row cache** — `items=`, `renderer=`,
  `on_width_changed`, `scrollbar_visibility=`; a new one owes a `drop_row_cache` call.
- **`refresh_rows` is for a renderer whose *inputs* changed**, not a rebuild of every row; and **one
  item is one row** — a `\n` reaching the buffer corrupts the frame.
- **There are no appenders and no `lines` reader** — items are assigned whole so a lazy provider
  stays expressible; incremental append lives on `TextView`. See `D_list_items`.
- **There is no `:auto` scrollbar mode** — visibility would depend on `rect.height` while the
  cache rebuilds from width only; a bar drawing no handle is *ink*, not visibility. See `D_scrollbar_ink`.
- **`List` measures nothing for its own content, and a dropdown driver supplies its own `width:`** —
  `anchor_to` owns placement and the scrollbar toggle, never the measurement. See `D_select`.
- **{Tuile::Component::Select} claims Enter, Space, ESC, `MOVE_KEYS` and the mouse — nothing else**,
  so a form's `s`-to-save keeps working while it has focus. See `D_select`.
- **The `[x] ` / `[ ] ` glyphs are a documented convention, not constants.** See `D_boolean_fields`.

### Overlays

- **{Tuile::Component::Overlay} is the bare layer; {Tuile::Component::Popup} the modal subclass** —
  no `modal:` knob, `modal?` is a constant per class. See `D_overlay`.
- **`focusable?` and `modal?` move together** — a focusable non-modal overlay holds focus outside
  the key scope and every keystroke goes dead until Tab recovers.
- **A *derived* position needs its own `reposition`, or closes on resize** — the base is a no-op;
  {Tuile::Component::MenuBar} takes the closing answer deliberately.
- **An overlay that insets its content *replaces* `handle_mouse`, never `super`s** — the default
  forwards only when the content's rect contains the point.
- **`Overlay#on_close` fires from `on_detached`, never `#close`**, so an `on_detached` override must
  `super`; and an overlay is closed, not hidden — `visible=` is refused. See `D_visibility`.
- **Outside-click: snapshot the open popups *before* routing, close the misses *after***, as a fresh
  array — either half reversed breaks opening or closing a `Select` by mouse. See `D_outside_click`.
- **A new overlay that is *part of* another owes an `Overlay#owner`**, set to the *driver* at
  construction; forget it and a click on the panel dismisses its host. See `D_outside_click`.
- **{Tuile::Component::TabSheet} keeps unselected panes out of the tree** — deliberately: the
  lifecycle hooks on every switch are the feature.

### Text inputs

- **A `TextField` subclass painting something other than `text` overrides `display_text`, never
  `repaint`** — one display character per `text` character, in order, enforced by nothing but a
  spec. See `D_text_field_axes`.
- **The wrap is a value and the viewport is not part of it** — an outside caller gets a forwarding
  reader on `TextArea`, never the `WrappedText`, which is a cache nilled on every change. See `D_text_area_rows`.

## Files

- `abstract_string_field.rb` — abstract String-valued base of both text inputs
- `abstract_wrapping_field.rb` — abstract typed face owning and hiding one editor
- `big_decimal_field.rb` — typed `BigDecimal`/nil; the lazy optional gem
- `button.rb` — captioned one-row action; `on_click`
- `checkbox.rb` — one-row boolean input
- `checkbox_group.rb` — multi-select over a `List`; `Set`-valued
- `combo_box.rb` — filtering dropdown: a `TextField` plus a `ListDropdown`
- `confirm_window.rb` — confirm/alert dialog and its three factories
- `date_field.rb` — typed `Date`/nil; lenient in, strict out
- `float_field.rb` — typed `Float`/nil; `IntegerField`'s deliberate copy
- `has_bad_input.rb` — mixin: the bad-input report
- `has_caption.rb` — mixin: the caption seam (chrome text)
- `has_content.rb` — mixin: one *primary* child, named `content`
- `has_placeholder.rb` — mixin: the empty-well hint
- `has_validation.rb` — mixin: the verdict slot
- `has_value.rb` — mixin: the value seam plus `focusable?`
- `info_window.rb` — read-only body: prose wraps, rows truncate
- `integer_field.rb` — typed `Integer`/nil over a `TextField`
- `label.rb` — static styled text
- `layout.rb` — `Layout` + `Absolute`; nests the constraints, `Insets`
- `layout/` — the box layouts; see `layout/AGENTS.md`
- `list.rb` — items plus a renderer, lazily rendered (+ the cursors)
- `list_dropdown.rb` — Overlay-over-List (+ `Menu`); owns placement
- `log_text_view.rb` — auto-scrolling log view; any-thread `#log`, a `Logger` IO
- `log_window.rb` — a `Window` framing a `LogTextView`
- `menu_bar.rb` — caption strip driving a submenu cascade (+ `Item`)
- `menu_bar/cascade.rb` — private: the stack of open panels
- `notification.rb` — corner toast; `show` is the only ctor
- `overlay.rb` — the bare floating layer: mount/dismiss, owner
- `password_field.rb` — `TextField` masking via `display_text`
- `picker_window.rb` — single-keystroke option picker
- `popup.rb` — the modal dialog: centers, focuses, scopes keys
- `progress_bar.rb` — display-only fill over a Range
- `radio_group.rb` — single-select over a `List`; the group model
- `select.rb` — the enum field: own-painted face over a `ListDropdown`
- `slot.rb` — a one-child region; the tree-native swappable slot
- `tab_sheet.rb` — a `Tabs` strip plus the selected pane
- `tabs.rb` — caption strip, one selected; owns no content (+ `Tab`)
- `text_area.rb` — multi-line editor over a wrap and a viewport
- `text_area/wrapped_text.rb` — private wrap snapshot; index↔row/column
- `text_field.rb` — horizontally scrolling one-line input
- `text_view.rb` — read-only scrollable prose; the append mutators
- `time_field.rb` — typed `Time`/nil on a fixed epoch; `step` is the precision
- `window.rb` — border plus a content slot and a footer
