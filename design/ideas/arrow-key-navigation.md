# Arrow keys move focus between fields — a behavior any layout opts into

**Status:** design sketch, nothing built. The argument is a ten-field form, not the sampler's
PasswordField pane that prompted it.

In a form, Up/Down moves focus between fields, beside Tab/Shift+Tab. Tab keeps its job (cycle every
tab stop in the scope, wrapping); arrows are *local* motion within one container and stop at its
edges.

## Why it needs no framework change

- **Rung 3 is the hook.** `ScreenPane#bubble_key` asks the focused widget, then each ancestor, so
  this is a `handle_key?` on a container — no dispatch phase, no gate (`D_key_dispatch`). That
  rule's "no gate, no predicate, no mode flag" constrains the ladder, not a component's own
  `handle_key?`.
- **`TextField` already declines Up/Down**: with `on_key_up` / `on_key_down` empty it returns
  `false` (`text_field.rb:156-162`).
- **Widgets that must keep the arrows already claim them and win**: `TextArea`, `TextView`, `List`
  (and the `RadioGroup` / `CheckboxGroup` built on it), the numeric, date and time fields, `ComboBox`.
- **`Tabs` left the vertical axis free on purpose** — it claims Left/Right and declines Up/Down so
  this feature can move focus out of it (`D_tabs`). The shape to copy for any one-axis widget.

## Prior art

| toolkit | arrows move focus? |
|---|---|
| FTXUI | yes — `Container::Vertical` *is* "navigated with up/down"; child asked first, container sees what it declined; arrows don't wrap (`MoveSelector`), Tab does (`MoveSelectorWrap`) |
| Midnight Commander | yes, arrows or Tab (the ncurses dialog lineage; only MC verified) |
| Bubble Tea | app-side only (`examples/textinputs`); no framework focus model |
| Textual, ratatui, Ink, Vaadin | no — the web/ARIA position: Tab between widgets, arrows within one |

## Shape: a knob on `Layout`, off by default

Any layout can be given the behavior; none has it by default, so virtui is untouched and a form
opts in. A layout without it **declines** the arrow, which bubbles to the next navigating ancestor —
so a nested `Absolute` inside a navigating `Vertical` is one opaque slot at any depth.

**Rejected: a `Layout::Form < Layout::Vertical` carrying the key behavior.**
- Vaadin's `FormGroup` coupled `Binder` to layouting and was abandoned for it; this couples a layout
  algorithm to a key behavior — the same mistake, smaller.
- A real form nests a `Horizontal` row or an `Absolute`; policy carried by a class is inherited by
  every subclass and unavailable to every non-subclass, so "does this container navigate?" stops
  being answerable. A setter is per instance.
- COP: `Layout::Vertical` is generic, so policy is injected, not subclassed.

`FormLayout` now exists as a *layout* (`D_form_layout`) and doesn't change this: it can opt in like
any layout, and its every child being one `FormItem` makes "walk direct children" exact there.

## Settled semantics

- **Walk direct children, not `walk_tree`** — in a `Horizontal` row inside a navigating `Vertical`,
  pre-order would send Down from the row's left field to its right one. The focused direct child is a
  parent-chain walk from `screen.focused`. (FTXUI indexes `children()` too.)
- **Skip children with no focusable descendant** (a `Label`, a spacer).
- **Don't wrap; decline at the edge** — nesting composes (inner box declines, outer moves on), and
  wrapping stays Tab's distinguishing job.
- **Descend via the focus cascade**: `screen.focused = sibling`, and `Layout#handle_focus`
  (`layout.rb:320`) forwards to its first tab stop.
- **Mouse and popups untouched** — the bubble is already scoped to the topmost modal popup.
- **Enter does not participate** (`dialog(1)` moves on Enter): `Checkbox`, `Button` and `TextArea`
  claim it, and book ch5 has the per-widget Enter table.

## The argument against

A partially live feature is worse than none: if arrows navigate in 80% of positions the user can't
build a model. Inside a form the exceptions are mostly the *tall* widgets, which reads as "arrows
move within a tall widget, between short ones" — learnable, and MC's story. The one-row steppers
break it (`Q_arrow_stepping_fields`).

## Open questions

- **`Q_arrow_nav_knob`** — the knob's shape:
  - (a) `navigation: :vertical | :horizontal | :both | nil` keyword + accessor on `Layout`
    (smallest);
  - (b) a strategy object, `layout.navigation = Layout::ArrowNavigation.new(…)` (per-instance
    config, app subclassing);
  - (c) a mixin, `Vertical.new.extend(Layout::ArrowNavigable)` (obscure, hard to document).
  - A general `on_key` interceptor is out: `D_no_key_interceptor`.
  - (b)/(c) need their own file under `lib/tuile/component/layout/`; any public signature change
    ships `rake sig`.
- **`Q_arrow_nav_axis`** — the axis can't come from the class if the behavior is layout-agnostic.
  Default `Vertical` → Up/Down, `Horizontal` → Left/Right, and require it on `Absolute`?
- **`Q_horizontal_nav`** — ship Left/Right at all? `AbstractStringField` always eats Left/Right for
  the caret, so a row of text fields never navigates while a row of buttons does. Uniform rule,
  selective-looking outcome. Vertical-only until asked?
- **`Q_absolute_order`** — inside an `Absolute`, declaration order may not match visual order.
  Document it, or sort direct children by `rect.top`, then `rect.left`, per keypress (cheap, correct)?
- **`Q_backwards_entry`** — `Layout#handle_focus` forwards to the *first* tab stop, so Up into a
  previous group lands on its first widget, not its last (FTXUI has the wart). A `last:` cascade
  variant, or accept?
- **`Q_arrow_stepping_fields`** — `IntegerField` / `FloatField` / `BigDecimalField`, `DateField` and
  `TimeField` step on Up/Down, are one row tall, and so break the tall-widget story silently:
  - (a) leave it and document;
  - (b) move stepping to Ctrl+Up/Down or PgUp/PgDn (breaking);
  - (c) opt-in stepping per field — a knob on the widget that has the ambiguity; a form field
    rarely wants a spinner.
- **`Q_list_edges`** — `List` clamps and returns `true`, so arrows never escape it, only Tab. Keep
  (MC agrees), or decline at the edges? Matters more for virtui than for a form.
- **`Q_down_opens`** — closed `ComboBox` (`combo_box.rb:181`) and `Select` (`select.rb:144`) eat
  Down to open but decline Up, so Up leaves while Down opens. Browsers eat both. Keep or fix?
- **`Q_tabs_down`** — the strip is a child of the `TabSheet`, so "direct children" sees the sheet
  and Down skips past the pane the user is looking at. Let `TabSheet` claim Down while its strip is
  focused (a second place binding an arrow), or have the walk descend into a child focused deeper
  than its first tab stop? Interacts with `Q_arrow_nav_knob`.
- **`Q_arrow_nav_name`** — `navigation` / `arrow_nav` / `key_navigation` / `focus_navigation`; not
  "form", which implies validation or submit.

## Graduation owes

- Book ch5 (the key and Enter tables): the user-facing half.
- AGENTS.md's *Focus, keys and paste*: the invariants.
- A `decisions.md` entry recording the `Layout::Form` rejection and the Vaadin `FormGroup`
  precedent — the reasoning most likely to be relitigated.

## Related

`D_key_dispatch`, `D_no_key_interceptor`, `D_tabs`, `D_form_layout`, `D_combobox`, `D_time_field`.
