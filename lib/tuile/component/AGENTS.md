# `lib/tuile/component/` — AGENTS.md

The widget set: every `Tuile::Component::*` an app composes — fields, lists, overlays, text views.
Owns what holds across the *widgets*; the framework-wide seams (the tree, repaint, focus and keys,
the theme and background chains) are the root `AGENTS.md`'s and are not restated here. Per-symbol
truth is each class's rdoc and the argument is `design/decisions.md`; the box layouts' own rules
are `Box`'s rdoc and `D_box_layouts`.

## Invariants

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
- **A new field with a partial parse owes its report a *settling* decision** — `bad_input_settled?`
  is `true` by default, wrong where every prefix is bad input; it gates what is **shown**, the ink
  and `on_bad_input_change`, never the pull. See `D_date_field`.
- **The showable report is pushed by one sole writer, `sync_bad_input`** — a field wrapping an editor
  rides `handle_editor_change` and owes nothing; a latch or a relayed child's report owes the call
  from wherever *that* moves. See `D_bad_input`.
- **Bad input outranks a verdict in prose, and `shown_message` is where that is said** — a consumer
  painting the message reads it instead of merging the two channels itself. See `D_has_validation`.
- **A composite relays its guilty child's message *and* that child's latch**, and answers
  `wears_bad_input_ink?` `false` while the child holds the fault, so the well reddens where the fault
  happened. See `D_date_time_field`.
- **One not prefix-closed settles its *value* notice on those gestures too** — `notify_on_edit? = false`,
  since a prefix that *parses* (`1.1.2` for `1.1.2024`) is a value no `bad_input?` can flag; fire
  from your own `value=` as well. Gate the **push**, never the pull. See `D_date_field`.
- **A field paints no caption and no message**, so it must not include {Component::HasCaption} —
  the container owning those cells owns both ({Component::FormItem}), and the message notice is
  load-bearing because the field never invalidates them. See `D_caption_ownership`.
- **`items` is chrome; `value` is authoritative and may hold what `items` doesn't** — `items=` never
  touches `value` and fires nothing. No reconcile, no clamp, no silent drop. See `D_combobox`.

### Composition

- **A typed field subclasses {Component::AbstractWrappingField}** and defines only `value` /
  `value=`; the base owns the editor, focus forwarding, the one well and the commit. An
  *editor-shaped* knob is not forwarded. See `D_wrapping_field`.
- **{Component::HasContent} means "a *primary* child you populate"**, not "one child" — private
  machinery is owned outright, or exposed read-only (`CheckboxGroup#list`). See `D_has_content`.
- **Chrome around one field is a wrapper component, never a per-child map on the layout** —
  {Component::FormItem}: hiding the item takes its caption and message with it, and `content=` is
  the sole place the two notices re-subscribe. See `D_form_item`.
- **A form is a column of items and nothing else** — {Component::FormLayout}'s `add` wraps whatever
  it is handed, so non-uniform children never regrow the chrome-vs-app-children distinction at the
  layout level, and `rows:` is its per-child placement, never a property of the item. See `D_form_layout`.
- **A {Tuile::Component::Slot} is transparent in all three channels** — not focusable, mouse
  descends through it, `handle_child_removed` forwards to the parent. See `D_slots`.
- **What the buffer may hold is decided in `insert_text`, and nowhere else** — typing, the ENTER
  newline and a pasted clipboard all land there. See `D_input_filters`.
- **The filter tests the whole resulting buffer, not the fragment**, and only works while the
  grammar is prefix-closed; a date is not, so such a field *reports* bad input instead. A **partial**
  filter reads as a guarantee and isn't.
- **A group composes a `List` and owes four things** — install a `List::Cursor` (a bare `List` sits
  at `-1`), render the marker into the row through a `List#renderer`, re-render through
  `refresh_rows`, clamp the cursor when the items shrink. `radio_group.rb` is the model. See `D_radio_group`.
- **Duplicate rather than DRY a shallow shell** — `FloatField` is a deliberate near-copy; a
  **fourth** copy is when to re-argue it, three is not. See `D_float_field`.

### Lists and dropdowns

- **The renderer runs at paint time on any frame, so it is a pure, cheap function of its item** —
  work reaching a service belongs in the item. See `D_list_items`.
- **Search renders without memoizing** — don't move the scan onto the cached path; one failed
  scan would otherwise grow the cache to a row per item.
- **Every input to a row's geometry drops the row cache** — `items=`, `renderer=`,
  `handle_width_changed`, `scrollbar_visibility=`; a new one owes a `drop_row_cache` call.
- **`refresh_rows` is for a renderer whose *inputs* changed**, not a rebuild of every row; and **one
  item is one row** — a `\n` reaching the buffer corrupts the frame.
- **There are no appenders and no `lines` reader** — items are assigned whole so a lazy provider
  stays expressible; incremental append lives on `TextView`. See `D_list_items`.
- **There is no `:auto` scrollbar mode** — visibility would depend on `rect.height` while the
  cache rebuilds from width only; a bar drawing no handle is *ink*, not visibility. See `D_scrollbar_ink`.
- **`List` measures nothing for its own content, and a dropdown driver supplies its own `width:`** —
  `anchor_to` owns placement and the scrollbar toggle, never the measurement. See `D_select`.
- **{Tuile::Component::Select} claims Enter, Space, ESC, `MOVE_KEYS` and the press — nothing else**,
  so a form's `s`-to-save keeps working while it has focus. See `D_select`.
- **The `[x] ` / `[ ] ` glyphs are a documented convention, not constants.** See `D_boolean_fields`.

### Overlays

- **{Tuile::Component::Overlay} is the bare layer; {Tuile::Component::Popup} the modal subclass** —
  no `modal:` knob, `modal?` is a constant per class. See `D_overlay`.
- **`focusable?` and `modal?` move together** — a focusable non-modal overlay holds focus outside
  the key scope and every keystroke goes dead until Tab recovers.
- **An overlay never assigns its own rect** — it opens with a placement (`open(Overlay::At[rect])`,
  a default, `anchor_to`) and the pane's pass applies it; a size change calls `reposition`, which
  asks the pane rather than moving anything. See `D_relayout`.
- **A non-modal overlay is never focused into** — the router skips click-to-focus for one, since
  focus outside the key scope makes every keystroke go dead. See `D_overlay`.
- **`Overlay#on_close` fires from `handle_detached`, never `#close`**, so a `handle_detached` override must
  `super`; and an overlay is closed, not hidden — `visible=` is refused. See `D_visibility`.
- **Outside-click: snapshot the open popups *before* routing the press, close the misses *after***, as a fresh
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

## Module map

- `layout/` — `Absolute` (a fixed `Rect` per child) and the box layouts stacking children along one
  axis; the box rules are `Box`'s rdoc and `D_box_layouts`

Maintenance: the root `AGENTS.md`'s rules; cap 10 KB.
