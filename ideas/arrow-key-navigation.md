# Arrow keys move focus between fields — as a *behavior*, not a layout class

**Status:** design sketch, 2026-08-12. Nothing built. Started from the
sampler's PasswordField pane ("Up/Down between the three fields would be
friendlier"), but that pane is a *demo* of the feature, not an argument for
it — the argument is a ten-field form. Open questions at the bottom are the
point of this file.

## What is being proposed

In a form, Up/Down moves focus between fields, in addition to Tab/Shift+Tab.
Tab keeps its current job (cycle every tab stop in the scope, wrapping);
arrows do *local* motion within one container and stop at its edges.

## Why it's plausible at all: Tuile already has the whole mechanism

Two findings from the survey, both load-bearing:

1. **`TextField` already declines Up/Down by design.** `text_field.rb:134-140`:
   `on_key_up` / `on_key_down` are nil by default and the nil branch is
   `return false`, with rdoc reading "when nil, UP falls through to the parent
   (default behavior)". The clash we feared was already resolved in the
   direction that enables this.
2. **Rung 3 of the key ladder is exactly the right hook.** `bubble_key` asks
   the focused widget, then each ancestor. AGENTS.md already names this as the
   sanctioned home for scope-wide keys ("a layout's one-key jumps to its
   panes"). So this is a `handle_key` on a container — no dispatch phase, no
   gate in `Screen#handle_key`, no framework change.

   Worth stating explicitly for a future reader: the key ladder's "no gate, no
   predicate, no mode flag" rule constrains `Screen#handle_key`, **not** a
   component's own `handle_key`. Adding behavior at rung 3 is sanctioned; a
   per-instance switch on a *component* is not the thing that rule forbids.

Everything that must keep the arrows already claims them and wins for free:
`TextArea`, `TextView`, `List`, the three numeric fields, `ComboBox`.

## Prior art

Splits by lineage, not by age:

- **FTXUI** — closest to Tuile architecturally, and does exactly this.
  `Container::Vertical` is *defined* as "navigated vertically using up/down
  arrow keys"; `Container::Horizontal` gets left/right. Dispatch is our shape:
  active child asked first, container only sees what the child declined
  (`container.cpp`, `OnEvent`). Arrows do **not** wrap (`MoveSelector`); Tab
  wraps (`MoveSelectorWrap`).
- **Midnight Commander** — "to move between the widgets use the arrow keys or
  the Tab key". The ncurses form-dialog lineage generally (`dialog`, newt)
  behaves this way; only MC was verified.
- **Bubble Tea** — the canonical `examples/textinputs` cycles focus on
  up/down/tab/shift+tab, but app-side; the framework has no focus model.
- **Textual, ratatui, Ink, Vaadin** — no. Textual is the explicit web/ARIA
  position: Tab between widgets, arrows only *within* a composite widget.

## The shape: a behavior on a layout, not a `Layout::Form`

`Layout::Form < Layout::Vertical` was the first sketch and is **rejected**.
Reasons, in order of force:

- **Vaadin's FormGroup precedent.** It coupled `Binder` to layouting and was
  abandoned for it. `Form` here would couple a layout algorithm to a key
  behavior — a smaller version of the same mistake.
- **It breaks the moment the layout is insufficient.** A real form needs a
  nested `Horizontal` row, or an `Absolute` for a capped-proportion split. Now
  the behavior is attached to the *outer* class and the nested layouts are
  arbitrary, so "does this container navigate?" stops being answerable from
  the class. Policy carried by a class is inherited by every subclass and
  unavailable to every non-subclass; policy carried by a setter is per
  instance and never inherited.
- **COP says so.** `Layout::Vertical` is a *generic, domain-agnostic*
  component, and the skill's rule for those is to externalize policy via
  injected strategies — not to subclass per policy. A `Form` whose only
  divergence is one `handle_key` is precisely the "shallow divergent
  scaffolding — duplicate or inject, don't fold into a base" case.

So: **any layout can be given the behavior; none has it by default.** virtui
gets nothing and stays exactly as it is; a form opts in. The sampler's `form`
helper (`sampler.rb:832`) becomes the one place the demo opts in.

Concretely, the nesting story this buys — and it is the whole reason for the
shape: a layout without the behavior **declines** the arrow key, so it bubbles
to the next ancestor that *does* have it. An inner `Absolute` inside a
navigating `Vertical` is therefore one opaque slot: focus anywhere inside it,
Down moves to the next slot of the outer box. No inheritance, no surprise, and
the answer is the same at any nesting depth.

## Semantics that already look settled

Recorded here so the open questions below stay narrow.

- **Walk direct children, not `on_tree`.** A `Horizontal` row nested in a
  navigating `Vertical`: flattened pre-order would make Down from the row's
  left field jump to the row's *right* field, which is geometrically wrong.
  Direct children makes Down go to the next row. (FTXUI indexes `children()`
  for the same reason.) "Which direct child holds focus" is a parent-chain
  walk from `screen.focused`, so depth doesn't matter.
- **Skip children with no focusable descendant** (a `Label`, a spacer).
- **Don't wrap; decline at the edge.** Two payoffs: nesting composes (an inner
  box at its edge declines and the outer box moves to the next sibling group),
  and wrapping stays Tab's distinguishing job. Same split FTXUI landed on.
- **Descend via the existing focus cascade** — set `screen.focused` to the
  sibling and let `Layout#on_focus` (`layout.rb:203`) forward to its first tab
  stop. See open question on backwards entry.
- **Mouse is untouched.** Popups are untouched — the bubble is already scoped
  to the topmost modal popup.
- **{Tuile::Component::Tabs} already left the vertical axis free for this.**
  The strip claims Left/Right and *declines* Up/Down specifically so that this
  feature can move focus out of it vertically while Left/Right keep switching
  tabs inside it (`D_tabs`). It composes for nothing: the strip declines, the
  key bubbles, the navigating ancestor moves. That is also the shape to copy
  for any future one-axis widget — claim one axis, leave the other.

## The honest argument against

A *partially* live feature is worse than an absent one: if arrows navigate in
80% of positions the user can't build a model. Inside a form the exception set
is mostly coherent — `TextArea` / `TextView` / `List` swallow arrows, and
they're the *tall* widgets, where a user already expects arrows to move
*inside* the box. That reads as "arrows move within a tall widget, between
short ones", which is learnable and is the story MC tells.

The three numeric fields break that story and are the real problem (see Q6).

## Open questions

**Q1 — What exactly is the knob?** Candidates, roughly in order of how much
API they add:

  a. keyword + accessor on `Layout`: `navigation: :vertical` / `:horizontal` /
     `:both` / `nil` (default `nil`).
  b. a strategy *object*: `layout.navigation = Layout::ArrowNavigation.new(...)`,
     leaving room for per-instance config and app subclassing.
  c. a module the app mixes in: `Vertical.new.extend(Layout::ArrowNavigable)`.
     Composable with any layout without touching `Layout`, but `extend` on a
     singleton class is obscure and hard to document.
  d. a general `Component#on_key` interceptor hook (the shape
     `AbstractStringField#on_key` already has), with the framework shipping a
     ready-made callable to assign. Most decoupled — touches `Layout` not at
     all — but adds a general hook whose merits should be argued on their own,
     not smuggled in under this feature.

  (a) is the smallest thing that works; (d) is the most COP-pure. Not decided.

**Q2 — Where does the axis come from?** If the behavior is layout-agnostic it
can't be derived from the class. `Vertical` → up/down and `Horizontal` →
left/right are natural defaults, but `Absolute` has none. Does the knob always
carry an explicit axis, or default per class and require it on `Absolute`?

**Q3 — Should `Horizontal` / left-right navigation exist at all?**
`AbstractStringField` *always* consumes Left/Right for the caret, so a row of
text fields will never arrow-navigate while a row of Buttons/Checkboxes will.
The rule stays uniform (widget wins); the outcome looks selective. Ship both
axes, or vertical-only until someone asks?

**Q4 — Ordering inside an `Absolute`.** Declaration order is all that's
available and may not match visual order — the original worry that killed the
idea of putting this on every layout. Options: document "declaration order is
yours to get right"; or sort direct children geometrically per keypress (by
`rect.top`, then `rect.left`), which is cheap and actually correct, and would
make `Absolute` a first-class citizen here. Is geometric ordering worth it?

**Q5 — Backwards entry into a multi-widget sibling.** `Layout#on_focus` always
forwards to the *first* tab stop, so arrowing **Up** into a previous group
lands on its first widget rather than its last. FTXUI has the same wart. Fix
with a `last:` variant of the cascade, or accept it?

**Q6 — The numeric fields.** `IntegerField` / `FloatField` / `BigDecimalField`
consume Up/Down to step by ±1, and they are *one row tall* — so they break the
"arrows move within tall widgets" story silently, with nothing on screen
explaining why. This is the sharpest concrete collision. Options:

  a. leave it; document the exception,
  b. move stepping to `Ctrl+Up/Down` or `PgUp/PgDn` (breaking, but the fields
     are young),
  c. make stepping opt-in per field (`step = 1` / `nil`) — a knob, but on the
     widget that actually has the ambiguity, and a numeric field in a form
     usually doesn't want spinner behavior anyway.

**Q7 — `List` at its edges.** It clamps and returns true, so arrows can never
escape a focused list; only Tab does. Keep clamping (a list is a list, and MC
agrees), or have it decline at its edges so arrows escape? Note this is
exactly virtui's shape, so the answer matters more there than in a form.

**Q8 — `ComboBox` is asymmetric.** Closed, it eats Down to open the menu
(`combo_box.rb:181`) but declines Up. So Up would jump out of a closed combo
while Down opens it. Browsers eat both. Deliberate choice or accident to fix?

**Q12 — Down out of a `Tabs` strip: to the pane, or past the whole
`TabSheet`?** The strip is a child of the sheet, not of the navigating layout,
so "walk direct children" sees the *sheet* holding focus and would move to the
sheet's next sibling — skipping the pane the user is looking at. Entering the
pane is almost certainly what a user means by Down here. Options: let a
`TabSheet` claim Down when focus is on its strip (a `handle_key` on the sheet,
no framework change, but a second place that binds an arrow); or have the
navigating walk descend into a child that holds focus deeper than its first
tab stop. Interacts with Q1's placement question.

**Q9 — Naming.** "Form" is the wrong word for the behavior — it's *focus
navigation*. `navigation` / `arrow_nav` / `key_navigation` /
`focus_navigation`? Whatever it is, it must not imply validation or submit,
which Tuile has no notion of.

**Q10 — Does Enter participate?** `dialog(1)` moves to the next field on
Enter. Almost certainly out of scope — `Checkbox`, `Button` and `TextArea` all
claim Enter already, and book ch5 has the per-widget Enter table — but worth
rejecting explicitly rather than by omission.

**Q11 — Where does the code live?** Zeitwerk wants one top-level constant per
file. If Q1 lands on (b) or (c) it needs its own file under
`lib/tuile/component/layout/`; if (a), it's a few lines on `Layout` itself.
Also: any public signature change means `rake sig` in the same commit.

## Graduation

If built: the user-facing half goes to book ch5 (the key/Enter tables live
there), the invariants half to AGENTS.md's key-dispatch section, and the
choice-plus-rejected-roads half to `DECISIONS.md` as `D_arrow_navigation` —
which must record the `Layout::Form` rejection and the Vaadin FormGroup
precedent behind it, since that's the reasoning most likely to be
re-litigated. Then retire this file.
