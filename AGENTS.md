# AGENTS.md

Orientation for coding agents working on Tuile. Read this before making
changes; the architecture has invariants that are not obvious from any
single file.

## What Tuile is

A small component-oriented terminal-UI framework built on top of the TTY
toolkit (`tty-cursor`, `tty-screen`, `tty-logger`). Apps build
a tree of {Tuile::Component}s under a singleton {Tuile::Screen}; the
screen runs an event loop, dispatches keys/mouse, and repaints
invalidated components in batch. The name is French for "roof tile" —
small pieces that compose into a larger whole.

The gem was extracted from
[virtui](https://github.com/mvysny/virtui)'s `lib/ttyui/` in 0.1.0, so
references to virtui in commit history are expected.

## Layout

```
lib/tuile.rb                       gem entry point: requires, Zeitwerk loader
lib/tuile/version.rb               VERSION constant
lib/tuile/keys.rb                  Tuile::Keys (key constants + .getkey)
lib/tuile/{point,size,rect}.rb     geometry value types (Data.define)
lib/tuile/mouse_event.rb           Tuile::MouseEvent (parses xterm sequences)
lib/tuile/event_queue.rb           Tuile::EventQueue + nested events
lib/tuile/fake_event_queue.rb      synchronous test double
lib/tuile/component.rb                  Tuile::Component base + nested Label
lib/tuile/component/has_content.rb      mixin for one-child containers
lib/tuile/component/layout.rb           Tuile::Component::Layout (+ Absolute)
lib/tuile/component/list.rb             Tuile::Component::List (+ Cursor / None / Limited)
lib/tuile/component/text_field.rb       Tuile::Component::TextField
lib/tuile/component/window.rb           Tuile::Component::Window (border + content slot)
lib/tuile/component/popup_window.rb     modal, self-sizing, ESC/q closes
lib/tuile/component/info_popup_window.rb popup-of-static-lines convenience
lib/tuile/component/picker_window.rb    single-keystroke option picker
lib/tuile/component/log_window.rb       Tuile::Component::LogWindow + IO adapter for tty-logger
lib/tuile/vertical_scroll_bar.rb        character-grid scrollbar (rendering helper, not a Component)
lib/tuile/screen.rb                     Tuile::Screen (singleton runtime)
lib/tuile/fake_screen.rb                in-memory test double
lib/tuile/screen_pane.rb                structural root of the component tree (kept at root, owned by Screen)

spec/tuile/**/<file>_spec.rb       mirrors lib/tuile/**/<file>.rb — one spec
                                   per source file (mostly; version.rb has none,
                                   and a few internals like has_content / fake_*
                                   are still uncovered)
spec/examples/<file>_spec.rb       PTY-based system tests for examples/ scripts
spec/spec_helper.rb                requires "tuile", uses minitest assertions
sig/                               RBS signatures (not yet authored — Phase 6)
```

Zeitwerk loads everything from `lib/`. Source files are wrapped in
`module Tuile` and don't `require_relative` each other — Zeitwerk
resolves constants on first reference.

## Core architecture (must-know)

### Singleton Screen, structural pane

`Tuile::Screen` is a process-singleton. It owns the event queue, the
"UI lock", invalidation set, terminal IO, and a single
{Tuile::ScreenPane}. *All* UI lives under that pane:

```
ScreenPane            (structural root, never paints anything)
├── content           (tiled Component, optional — usually a Layout::Absolute)
├── popups[0..n]      (modal stack, last is topmost)
└── status_bar        (Component::Label, bottom row)
```

Putting popups under the same parent as content means focus traversal,
`Component#attached?`, and `on_child_removed` work uniformly without
special-casing popups.

### Component tree

Every UI piece is a {Tuile::Component} with `parent` / `children`,
`rect`, `active?`, `focused`, `key_shortcut`. Two derived APIs:

- `depth` / `root` — distance to root and root pointer
- `on_tree { |c| … }` — pre-order traversal of self + descendants
- `attached?` — true iff `root == screen.pane`

`children` is read-only by convention (the array must not be mutated by
callers; containers expose `add` / `remove` / `content=` / `footer=` to
swap and reparent).

### Invalidation + repaint (read this twice)

Components do **not** paint immediately. They call
`invalidate` (a protected method that records `self` in
`Screen#@invalidated`). After an event-loop tick drains the queue,
`Screen#repaint` walks the invalidated set:

1. Partition into tiled-tree and popup-tree (popup-tree = anything
   reachable from `pane.popups`).
2. Sort tiled by depth (parent before child).
3. If any tiled were invalidated, re-paint *all* popup subtrees on top
   in stacking order — popups deliberately overdraw content, no
   clipping.
4. Position the hardware cursor based on the *focused* component's
   `cursor_position`.

**Invariants you must preserve:**

- A component must fully draw over its `rect` and must not draw outside
  it. Use `clear_background` to wipe before painting.
- Borders paint *over* content, so {Tuile::Component::Window#repaint} re-invalidates
  its content after painting its frame. Don't break that ordering.
- Don't call `Screen#repaint` directly from a component; just
  `invalidate` and let the loop coalesce.

### Threading rule (the load-bearing one)

The event queue is single-threaded. *All* UI mutations — `rect=`,
`active=`, `content=`, `add_line`, `invalidate`, `screen.focused=` —
must run on the thread that owns `Screen#run_event_loop`.

Background threads must marshal work back via
`screen.event_queue.submit { … }`. Most UI methods call
`screen.check_locked`, which raises `"UI lock not held"` if you violate
this. {Tuile::FakeScreen} short-circuits the check so tests can mutate
freely.

`Screen#@@instance` is a class variable — the singleton survives
sub-classing (`FakeScreen < Screen`).

### Focus + shortcuts

`screen.focused = component` walks `parent` upward and marks the entire
chain root → focused as `active?`, deactivating everything else. The
flag is universal: every component carries it, but only components on
the current focus chain ever have it set true. Then `component.on_focus`
fires and the status-bar hint is rebuilt. Setting `nil` deactivates
everything.

`Component#focusable?` is independent of the active flag: it gates
*becoming* a focus target. Click-to-focus (`Component#handle_mouse`) and
the on_focus cascade in `HasContent` / `Layout` only forward focus to
focusable components, so clicking a {Tuile::Component::Label} doesn't
hijack focus from the surrounding window.

`Component#handle_key` first checks for a `key_shortcut` match anywhere
in its subtree — *unless* the focused component owns the hardware cursor
(i.e. its `cursor_position` is non-nil, e.g. a {Tuile::Component::TextField}
the user is typing into). That suppression is what lets text fields
swallow printable keys without sibling shortcuts hijacking them.

{Tuile::Component::Layout#handle_key} falls back to dispatching to its
active child. {Tuile::Component::Window} delegates to `content` when content is
active, and to `footer` when footer is active.

### Popup focus repair

When a popup closes, focus must land somewhere reasonable. The order
implemented in {Tuile::ScreenPane#on_child_removed}:

1. The now-topmost remaining popup, if any.
2. The focus snapshotted just before this popup was added — *if it's
   still attached*. Snapshots are stored in `@popup_prior_focus`.
3. The tiled `content`.
4. `nil`.

If a non-topmost popup closes while focus is in the topmost, focus is
left untouched, but `@popup_prior_focus` is rewritten so any popup that
remembered a focus *inside* the just-closed popup forwards to the
closing popup's own prior. This prevents stranded references to
detached components when popups close out of order. {Tuile::ScreenPane}
spec has the regression cases — read them before refactoring this.

### Resize

Terminal resize is plumbed through the event queue, not handled
directly off the signal. `EventQueue#trap_winch` installs the sole
`SIGWINCH` handler and posts an `EventQueue::TTYSizeEvent` (carrying
the new `width` / `height`). `Screen#event_loop` catches it, assigns
the event to `Screen#size`, and runs `layout`, which resizes
`pane` to `(0, 0, size.width, size.height)`, invalidates the entire
tree, and repaints.

**React to resize via the normal invalidation path** — i.e. let your
parent reassign your `rect`, and recompute child layout in `rect=`.
Do **not** add your own `Signal.trap("WINCH")` in component code; only
one handler can win, and `EventQueue` owns it. If a component needs to
read the current viewport directly, use `Screen.instance.size` (seeded
at construction from `TTYSizeEvent.create`, so it's valid before the
first WINCH ever fires).

### Geometry primitives

`Point`, `Size`, `Rect` are `Data.define` value types (frozen,
structural equality). `Rect#contains?` uses **half-open** edges
(`x >= left && x < left + width` — right/bottom are exclusive).
`Rect#empty?` includes width==0 *and* width<0.

## Testing

`spec/tuile/**/<file>_spec.rb` mirrors `lib/tuile/**/<file>.rb` (so
`lib/tuile/component/window.rb` ↔ `spec/tuile/component/window_spec.rb`).
Specs are
wrapped in `module Tuile` so unqualified references (`Component`,
`Screen`, …) resolve via lexical scope. Assertions are minitest-style
(`assert`, `assert_equal`, `assert_raises`, `refute_*`) wired through
rspec-core via `config.expect_with :minitest`.

`spec/examples/` holds end-to-end tests for the runnable scripts under
`examples/`: each spawns its target script in a pseudo-TTY via
`PTY.spawn`, waits for a known glyph to confirm the first paint landed,
sends a key, and asserts a clean exit. Linux/macOS only — Ruby's stdlib
`PTY` isn't on Windows. They run as part of `rake spec`.

The `Screen.fake` / `Screen.close` `before`/`after` pair is the standard
setup — it installs a {Tuile::FakeScreen} (160×50, in-memory `prints`
buffer, no terminal IO, no UI lock) and resets the singleton between
examples. Without it, code that touches `Screen.instance` will see
state leaked from the previous test.

`Screen.instance.prints` is the array of strings the screen "would have
printed". Assert against it for repaint behavior.
`Screen.instance.invalidated?(c)` and `invalidated_clear` are the
test-only hooks for verifying invalidation.

`FakeEventQueue` runs submitted blocks synchronously and discards
posted events; it lets specs drive the system without a real loop.

## Commands

```sh
bundle exec rake spec                        # run all specs (unit + examples)
bundle exec rspec spec/tuile/list_spec.rb    # run one file
bundle exec rspec spec/tuile/list_spec.rb:42 # run a specific example
COVERAGE=true bundle exec rake spec          # specs + SimpleCov report at coverage/index.html
bundle exec rubocop                          # lint (Phase 4 not yet done — many violations expected)
```

Coverage at 0.1.0 sits at ~97% line / ~88% branch. The remaining gap is
in real-terminal runtime paths (`Screen#run_event_loop`,
`EventQueue#start_key_thread`, the WINCH trap) that need raw-mode stdin
and a real signal handler — not worth mocking. There is no CI gate;
treat the number as a signal, not a target.

YARD generation, RBS validation, and example apps are not yet wired
(Phases 5–7). Don't claim those work until the corresponding phase
lands.

## Common pitfalls

- **Calling UI from a background thread.** Use
  `screen.event_queue.submit { … }`. The `check_locked` raise is a
  guardrail, not a feature — fix the call site, don't bypass it.
- **Mutating `children` / `popups` arrays.** Always go through
  `add` / `remove` / `add_popup` / `remove_popup` / `content=` /
  `footer=`. They handle parent pointers, focus repair, and
  invalidation.
- **Expecting `repaint` to happen synchronously.** It happens once per
  event-loop tick (when `EmptyQueueEvent` fires). Specs trigger it via
  `Screen#repaint` directly; production code should not.
- **Adding `require 'tuile/foo'` inside source files.** Zeitwerk
  resolves it; explicit requires bypass the loader and create dual-load
  hazards. The only `require`s that belong inside `lib/tuile/` files
  are gem-level deps you genuinely need at file-load time — and most of
  those are already hoisted into `lib/tuile.rb`.
- **Adding a second top-level constant to a `lib/tuile/foo.rb` file.**
  Zeitwerk expects `foo.rb` to define exactly one top-level
  `Tuile::Foo`. Nested constants inside it (`Foo::Bar`) are fine. If
  you have a sibling top-level class, give it its own file.
- **Logging from gem code.** Use `Tuile.logger`, not `$log` or
  `TTY::Logger`. The default is `Logger.new(IO::NULL)`, so the gem is
  silent unless the host app sets `Tuile.logger = ...`. The accessor
  targets the stdlib `Logger` interface — `TTY::Logger` duck-types it,
  so virtui can pass its existing logger straight in. To route logs
  *into* a {Tuile::Component::LogWindow}, construct the host's logger with
  `Component::LogWindow::IO.new(window)` as its output.
- **Touching `@@instance` directly.** Use `Screen.instance` /
  `Screen.close` / `Screen.fake`. The class variable is part of the
  singleton-survives-subclassing contract.

## Project state (as of 0.1.0)

- ✅ Source ported under `Tuile::*`, Zeitwerk wired
- ✅ Specs green; ~97% line / ~88% branch coverage via SimpleCov
  (opt-in, see Commands)
- ✅ CI runs specs on Ruby 4.0 + head and gates RBS drift
  (`.github/workflows/ci.yml`)
- ✅ RBS sigs: `sig/tuile.rbs` generated by sord with zero warnings;
  `bundle exec rake sig` regenerates and CI fails on drift (Phase 6)
- ✅ YARD docs: link warnings cleared, types tight enough for sord;
  remaining `@param` / `@return` gaps are minor (Phase 5 mostly done)
- ◐ Rubocop: clean except for `Metrics/*` size cops (BlockLength,
  MethodLength, AbcSize, etc.) which we accept — TUI rendering loops
  are long by nature. Either disable those cops in `.rubocop.yml` or
  live with them; don't "fix" them by extracting helpers (Phase 4)
- ◐ README is still the bundler-gem scaffold; `examples/` has a
  hello-world (covered by a PTY system spec) but no larger demo yet
  (Phase 7)
- ⏳ Wiring `tuile` back into virtui as the integration test
  (Phase 8)
