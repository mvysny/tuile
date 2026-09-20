# Architecture

How the pieces compose — what no single symbol can say and what would be expensive to overturn:
wiring and dependency direction, the lifecycle / threading / data-flow story, the flows a newcomer
needs, where to start reading. **Normative: the code conforms.** Change this file first, then the
code. Not here: why (`decisions.md` — cite the `D_`), what upstream does (`research.md` — cite the
`R_`), one symbol's behaviour (its rdoc), the module map (`AGENTS.md`, root and per-directory).
Only the sections with content; **the first entry in each is the ruler** — later entries trim to
its length. Cap 12 KB — over it, research or rdoc content has crept in.

## Wiring

- **Dependencies point at `Screen`, and `Screen` points back at no widget.** Every component
  reaches `Screen.instance` for the buffer, the invalidation set, the theme and the locale;
  {Tuile::Screen} itself names only {Tuile::ScreenPane} and {Tuile::Component}.
- **`Screen` is the service and `ScreenPane` is the UI** — the queue, the UI-thread rule, terminal
  IO, the back buffer, the invalidation set and the detected theme/locale/color-depth live on the
  singleton; the tree, attachedness, the popup stack and focus repair live on the pane. New
  machinery goes on one, new tree semantics on the other (`D_tree_first`).
- **An app constructs the tree, then hands ownership to the loop.** `Screen.new` → build
  components → `screen.content =` → `run_event_loop` → the loop's thread owns every mutation until
  it returns. Nothing is wired by the framework: a component's collaborators arrive through its
  own setters (`items=`, `renderer=`, `on_click`), and a service never holds a reference back up.
- **Painting funnels twice.** Widgets paint through the {Tuile::Canvas} they were handed, which
  applies the inherited background, adds its origin (a widget writes at `(0, 0)`) and writes to its
  {Tuile::Canvas::Backend}, normally {Tuile::Buffer}; `Buffer#flush` is the only thing that writes
  bytes, and the only place a {Tuile::Color} is quantized to the terminal's depth.
- **One coordinate space per component, and the framework does the converting.** A `rect` is
  measured inside its parent, so a component's own coordinates are what it paints in, where its
  children sit, where a {Tuile::Mouse::Event} counts and what `cursor_position` answers — nothing
  adds an ancestor's offset. Three places sum the chain: {Tuile::Screen#canvas_for} building the
  {Tuile::Canvas#origin}, {Tuile::Screen#cursor_position} on the way out to the terminal, and
  {Tuile::Mouse::Router} on the way in. Anything else asks by name — `absolute_rect`,
  `absolute_extent_rect`, `to_screen`, `to_local` — and an overlay anchoring to its driver is the
  only widget-level caller (`D_relative_rect`, `D_canvas`).
- **One background chain, four levels, resolved at paint.** `effective_bg_color` is
  `error_bg_color || @bg_color || default_bg_color || parent.effective_bg_color` — a validation
  error first, so tinting a panel cannot switch the signal off; then the app's override; then the
  widget's own opaque surface (protected, `nil` for "no surface of my own"); then what surrounds it,
  with the terminal default as the root. A non-nil `default_bg_color` terminates inheritance, which
  is what keeps a form's fields looking like fields inside a tinted panel;
  `Component::BG_INHERIT` on `bg_color` skips the widget's own level, which is how a composed field
  lets its composer own the well. {Tuile::Screen#canvas_for} resolves it once per repaint and loads
  it onto the canvas; nothing caches the answer, and no widget reaches around the chain to
  `screen.theme` (`D_bg_inherit`, `D_bg_surface`, `D_canvas`).
- **Two threads, one owner.** {Tuile::EventQueue} runs a key-reading thread and owns the sole
  `SIGWINCH` trap; everything it reads becomes an event. {Tuile::FakeScreen} and
  {Tuile::FakeEventQueue} replace both for specs.
- **Two gates prune every tree walk, and they are different axes.** Geometry says *where and how
  much* — a component whose rect, or any ancestor's, is empty is skipped; the `visible?` flag says
  *whether* at all. Both are **ancestor-inclusive**: a walk prunes at the hidden or empty subtree's
  root rather than testing leaves, so a widget three levels down is skipped without knowing it. The
  gates sit on the component tree rather than in the containers — `Screen#repaint`'s drain filter,
  `children_tile_rect?` (so a hidden child's cells count as a gap the parent blanks),
  `Screen#cycle_focus` / `ScreenPane#first_tab_stop_or_root` / `Layout#handle_focus` /
  `HasContent#handle_focus` through one shared walk helper, `Screen#focused=` (which raises on a hidden
  target), {Tuile::Mouse::Router}'s descent, and `Testing.find`. Cursor and keys follow, since the focused
  component is always shown. A container that never heard of the flag therefore degrades to a hole
  rather than to a leak (`D_visibility`, `D_empty_ancestor`).

## Flows

**One event-loop tick** (`Screen#event_loop`, the loop's thread):

1. The key thread posts a `KeyEvent`, `PasteEvent`, `TTYSizeEvent` or `ColorSchemeEvent`; the
   queue synthesizes `EmptyQueueEvent` when it drains.
2. A key climbs the three-rung ladder — Tab, then the global-shortcut registry, then delivery to
   `Screen#focused` bubbling up to the scope root (`D_key_dispatch`). A paste skips the ladder and
   goes to `Screen#focused` alone (`D_bracketed_paste`). A mouse event goes to
   {Tuile::Mouse::Router} (below).
3. Handlers mutate components; each mutation calls `invalidate`, which records the component in
   `Screen`'s invalidated set. Nothing paints yet — **a retained tree, not a redraw loop**.
4. On `EmptyQueueEvent`, `Screen#repaint` drains the set: drop anything with an empty rect on its
   ancestor chain, paint the tiled tree parent-first by depth, then re-assert every popup subtree
   above it in stacking order.
5. `Buffer#flush` emits the **minimal diff** — only cells that changed — plus the focused
   component's `cursor_position`, wrapped in one synchronized-output batch, through `Screen#emit`.

**A mouse event** (`Mouse::Router#dispatch`) resolves a walk first: the topmost popup containing the
point, else the tiled content unless a modal popup is open (`ScreenPane#mouse_root_at`), then down
through shown children whose `rect` contains the point — converting the point at each level, so
every component is handed the event in its own coordinates. A left press focuses the innermost
`focusable?` on that path *before* any handler runs, then `handle_mouse_down?` bubbles back up the
prefix whose `local_extent_rect` contains the point until one component claims it — and the claimant is
**grabbed**, so this button's drags and its up go to it alone until the release, any key, or the next
press. A wheel notch and a move bubble the same way and grab nothing; enter and exit are the
difference between the last hovered chain and the new one, and `Screen#repaint` re-syncs that chain
so a hidden or detached component gets its exit (`D_mouse_dispatch`).

**A resize** rides the same queue rather than the signal handler: `SIGWINCH` → `TTYSizeEvent` →
`Screen#size =` and `layout`, which resizes the pane and invalidates the whole tree; each parent
recomputes its children's rects in its own `rect=`, and the tick above repaints.

**A background job** submits its UI half back: `screen.event_queue.submit { … }` runs the block on
the loop's thread at the next drain. Calling a mutator from any other thread raises
{Tuile::Error} instead of corrupting the frame.

## Where to start reading

`lib/tuile/screen.rb` — the singleton every other file talks to: the loop, the ladder, the
repaint drain and the lifecycle states are all there in order. Then `lib/tuile/component.rb` for
the tree, the paint helpers and the background chain every widget inherits.
