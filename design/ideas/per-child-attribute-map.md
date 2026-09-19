# Is the per-child attribute map a shape worth sharing?

**Status:** seed, 2026-09-19. Filed the same day as a broader question — *is
there a `HasContent` for a container holding **many** populatable children?* —
which `FormItem` answered before this file was a day old. What survives is the
narrow half, kept because it has no other home.

## What `FormItem` answered, so it isn't re-opened

The broad version asked for a `HasChildren`: the collection analogue of
{Tuile::Component::HasContent}, letting a walk ask a container "what did the app
put in here?" without a class list. Two things killed it:

- **The distinction moved.** `design/ideas/form-layout.md` settled on a
  `FormItem` wrapping each field, so a `FormLayout`'s children are homogeneous
  items and nothing else. "Which of my children are the app's and which are my
  chrome?" is now a question *inside* `FormItem`, where `HasContent` already
  answers it in words (`D_has_content`).
- **The implementer count was one.** `Layout` and its subclasses, and nothing
  else: {Tuile::Component::TabSheet} keeps unselected panes out of the tree and
  exposes `Tabs::Tab` handles (`D_tabs`); `CheckboxGroup` / `RadioGroup` /
  `Select` hold **items**, domain objects with a renderer (`D_list_items`);
  `MenuBar`'s items aren't `Component`s; `ScreenPane#popups` is framework
  machinery. One implementer is where the locator argument stopped for `Tabs`.

Also worth not re-deriving: **the tree API cannot be bypassed from app code** —
`add_child` / `remove_child` / `detach_child` are **protected** on `Component`,
so an app reaches children only through a container's own `add` / `remove`, and
`Box#placement` falls back to `DEFAULT_PLACEMENT` rather than crashing on a
missing entry. There is **no leak bug here**; don't write this up as if there
were one.

## What is left

`Q_map_shape`: `Box` keeps `{child => {main:, cross:, align:}}`, a `FormLayout`
will keep `{item => {rows:, colspan:}}`, and a `Grid` would keep per-column
specs. Each hand-rolls the same four moves — put on `add`, delete on `remove`,
default on read, re-run the layout.

Is that a private helper on `Layout`, a protected trio of methods, or nothing at
all? Constraints:

- **Not a public mixin.** Nobody outside the container reads the map, so it
  fails the locator test by construction and is pure DRY — and `D_float_field`'s
  rule says three hand-rolls is when to look again, two is not. `FormLayout`
  makes two.
- **Never a second copy of ordering** — `children` stays the sole ordering
  authority whatever this becomes (`D_box_layouts`).
- **Never a measurement channel.** Nothing here may grow into asking a child how
  big it wants to be (`D_declared_size`).
- **Not a `Container` base class to share code** — COP: inherit to *be* a
  component, never to share.

The honest default is **nothing at all**: let `FormLayout` hand-roll its map like
`Box` does, and revisit when `Grid` makes it three.

## Related

`design/ideas/form-layout.md` (the second hand-roll, and the file that answered
the broad question), `D_box_layouts` (the first), `D_has_content`,
`D_declared_size`, `D_float_field` (duplicate rather than DRY a shallow shell),
`D_tabs` (where the locator argument stopped last time).
