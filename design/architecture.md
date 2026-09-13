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
- **Painting funnels twice.** Widgets paint through `Component#draw_text` / `#draw_char` (which
  apply the inherited background) into {Tuile::Buffer}; `Buffer#flush` is the only thing that
  writes bytes, and the only place a {Tuile::Color} is quantized to the terminal's depth.
- **Two threads, one owner.** {Tuile::EventQueue} runs a key-reading thread and owns the sole
  `SIGWINCH` trap; everything it reads becomes an event. {Tuile::FakeScreen} and
  {Tuile::FakeEventQueue} replace both for specs.

## Flows

**One event-loop tick** (`Screen#event_loop`, the loop's thread):

1. The key thread posts a `KeyEvent`, `PasteEvent`, `TTYSizeEvent` or `ColorSchemeEvent`; the
   queue synthesizes `EmptyQueueEvent` when it drains.
2. A key climbs the three-rung ladder — Tab, then the global-shortcut registry, then delivery to
   `Screen#focused` bubbling up to the scope root (`D_key_dispatch`). A paste skips the ladder and
   goes to `Screen#focused` alone (`D_bracketed_paste`).
3. Handlers mutate components; each mutation calls `invalidate`, which records the component in
   `Screen`'s invalidated set. Nothing paints yet — **a retained tree, not a redraw loop**.
4. On `EmptyQueueEvent`, `Screen#repaint` drains the set: drop anything with an empty rect on its
   ancestor chain, paint the tiled tree parent-first by depth, then re-assert every popup subtree
   above it in stacking order.
5. `Buffer#flush` emits the **minimal diff** — only cells that changed — plus the focused
   component's `cursor_position`, wrapped in one synchronized-output batch, through `Screen#emit`.

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
