# `spec/` — AGENTS.md

The test suite. `spec/tuile/**/<file>_spec.rb` mirrors `lib/tuile/**/<file>.rb` (mostly —
`version.rb` has none, and a few internals like `has_content` and the fakes are uncovered). Specs
are wrapped in `module Tuile`, so unqualified references resolve by lexical scope; assertions are
minitest-style (`assert`, `assert_equal`, `assert_raises`, `refute_*`) wired through rspec-core
with `config.expect_with :minitest`. The argument for each rule below is `design/decisions.md`.

## Invariants

- **The `Screen.fake` / `Screen.close` `before`/`after` pair is the standard setup** — it installs a
  160×50 {Tuile::FakeScreen} with an in-memory `prints` buffer and no terminal IO, and resets the
  singleton between examples. Without it, anything touching `Screen.instance` sees leaked state.
- **The fake runs no event loop, so the ordinary `check_locked` admits the example thread** — a spec
  mutating UI from a *spawned* thread raises, exactly as an app would. Don't add a bypass.
- **Assert painted content against `Screen.instance.buffer`**, not `prints` — `region_text(rect)` /
  `region_ansi(rect)` / `cell(x, y)` after a `Screen#repaint`, which a spec calls directly and
  production code never does. `prints` now holds only cursor escapes and
  the assembled frame, so use it for cursor behaviour alone. See `D_list_items`.
- **The buffer is screen space, so read and click by `absolute_rect`** — a `rect` is measured inside
  its parent, so `region_text(field.rect)` on a nested widget reads the wrong cells and
  `click(field.rect.left, …)` misses. Identical only at the tree root, which is why either spelling
  passes in the simplest specs. See `D_relative_rect`.
- **Paint one component with the suite-wide `repaint(component)` helper** — `Component#repaint`
  takes a required {Tuile::Canvas} and the canvas carries the component's resolved background, so
  `component.repaint` alone is not a thing. See `D_canvas`.
- **A spec that parents a component and paints it directly must lay the parent out** — a parent
  left at its default empty rect now clips its whole subtree to nothing, so the child paints
  nothing and the assertion fails far from the cause. `Screen#repaint` skips such a subtree
  anyway; `repaint(component)` bypasses that and reaches the clip instead. See `D_clip`.
- **The contract suite's stray sweep paints through `paint_unclipped`, not `paint`** — through
  `Screen#canvas_for` the strays never reach the buffer, so the sweep becomes a test of `Screen`
  and cannot fail. See `D_clip`.
- **`spec/tuile/component_contract_spec.rb` runs the framework-wide invariants over a catalog of
  every component, and a new component owes it an entry** — a completeness guard eager-loads `lib/`
  and fails on any subclass in neither the catalog nor `excluded`, so opting out is possible but
  never silent and must carry a reason. See `D_component_contract`.
- **What belongs in the contract suite is the same gate as the root `AGENTS.md`'s**: an invariant
  that holds for every component, that nothing enforces at runtime, and that fails *silently*. A
  violator is `pending` with a reason, never `skip`, so fixing it fails the example.
- **Get a handle with {Tuile::Testing}, qualified** — `Testing.get` demands exactly one match and
  dumps the tree it searched; `Testing.find` takes `count:`. Never `config.include` it: `find` and
  `get` are the most collision-prone names in a suite. See `D_component_lookup`.
- **`Testing` simulates a user, so it never finds a hidden component** — assert a field *is* hidden
  by holding it and checking `refute field.visible?`; assert unreachability with `count: 0`. There
  is deliberately no `visible:` filter. See `D_visibility`.
- **The locator finds it, the gesture refuses it** — `Testing.click` / `.set_value` raise unless a
  user could have done it; a bare `handle_key?` or `value=` on a handle asserts no such thing.
  Receiver syntax is the {Tuile::Testing::Gestures} refinement (`_click`, `_value=`), `using`-ed per
  file or per `describe`; the underscore marks the testing API.
- **A gesture borrows its gate, never invents one** — `click` routes a real press and lets
  {Tuile::Mouse::Router} answer, `set_value` asks one `walk_shown_tree` over `ScreenPane#key_scope`.
  A new gesture with no dispatcher to borrow from is a design problem, not a predicate to write.
  See `D_test_gestures`.
- **`Testing.component_path_at` is a deliberate copy of the router's private walk, pinned by
  `testing_spec`** — the pin asserts it ends where a real press is delivered. Keep the pin green or
  move the walk onto the router; don't fix one side alone.
- **Everything the testing surface raises is `Testing::AssertionError`**, an `Exception` (not a
  `StandardError`, and not a `Tuile::Error`) for the reason `Minitest::Assertion` is one: nobody
  should be catching it.
- **Pace the keys in a PTY test — never write a burst.** `Keys.getkey` gulps a fixed 5 bytes after a
  leading `\e`, so bytes arriving in one read merge into a bogus key; send one key at a time and
  force a round-trip between them. This is inherent ESC ambiguity, not a bug to fix in `getkey`.
- **The *first* key needs the same gap** — the raw-mode flip discards typeahead, so a key written
  before the reader's first `getch` is silently dropped and the test hangs. 50 ms is enough
  (`file_commander_spec` measures it).
- **The one sanctioned burst is a bracketed paste** — `\e[200~…\e[201~` goes in a single `write`,
  because a real paste is gapless and that fidelity is what is under test. See `D_bracketed_paste`.
- **A PTY spec asserting frame *bytes* must pin the color depth** with
  `{ "TUILE_COLOR_DEPTH" => "truecolor" }` in `PTY.spawn`'s env hash — the child otherwise inherits
  the runner's `COLORTERM` and quantizes differently in CI than on a dev terminal, silently.
  Reproduce a suspect spec with `TERM=dumb env -u COLORTERM bundle exec rspec …`.
- **A spec that reassigns an app-global restores it in `after`** — `ThemeDef.default` back to
  `ThemeDef::DEFAULT`, `VerticalScrollBar.handle_char` / `.track_char` back to `█` / `░`; otherwise
  every later example in the run reads the leak. `Screen#locale` needs none: `Screen.fake` resets it.
- **A spec exercising locale detection calls `Locale.from_keywords` with canned answers**, never the
  machine's own; a PTY spec pins with `{"LC_ALL" => "C"}` in the env hash it already passes.
- **`FakeEventQueue` runs submitted blocks synchronously and discards posted events**, which is what
  lets a spec drive the system with no real loop.
- **The contract guard filters `ObjectSpace` to named, non-singleton `Tuile::` classes** — a
  full-suite run manufactures singleton, anonymous and app subclasses.

## Module map

- `tuile/` — one spec per source file mirroring `lib/tuile/`, plus the contract and nomenclature guards
- `examples/` — PTY-based system tests for the `examples/` scripts (Linux/macOS only; no Windows `PTY`)

Maintenance: the root `AGENTS.md`'s rules; cap 10 KB.
