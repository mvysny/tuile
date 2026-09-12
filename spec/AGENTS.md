# AGENTS.md — `spec/`

The test suite's must-not-break list, loaded beside the root file when work touches this directory.
One-line invariants and pointers only; the argument for each is `design/decisions.md`. Cap 10 KB.

`spec/tuile/**/<file>_spec.rb` mirrors `lib/tuile/**/<file>.rb` (mostly — `version.rb` has none,
and a few internals like `has_content` and the fakes are uncovered). Specs are wrapped in
`module Tuile`, so unqualified references resolve by lexical scope; assertions are minitest-style
(`assert`, `assert_equal`, `assert_raises`, `refute_*`) wired through rspec-core with
`config.expect_with :minitest`.

## Seams

- **The `Screen.fake` / `Screen.close` `before`/`after` pair is the standard setup** — it installs a
  160×50 {Tuile::FakeScreen} with an in-memory `prints` buffer and no terminal IO, and resets the
  singleton between examples. Without it, anything touching `Screen.instance` sees leaked state.
- **The fake runs no event loop, so the ordinary `check_locked` admits the example thread** — a spec
  mutating UI from a *spawned* thread raises, exactly as an app would. Don't add a bypass.
- **Assert painted content against `Screen.instance.buffer`**, not `prints` — `region_text(rect)` /
  `region_ansi(rect)` / `cell(x, y)` after a `Screen#repaint`, which a spec calls directly and
  production code never does. `prints` now holds only cursor escapes and
  the assembled frame, so use it for cursor behaviour alone. See `D_list_items`.
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

## Files

- `spec_helper.rb` — requires `tuile`, wires minitest assertions into rspec
- `tuile/` — one spec per source file, mirroring `lib/tuile/`
- `tuile/component_contract_spec.rb` — the framework-wide contract suite over every component
- `tuile/nomenclature_spec.rb` — the vocabulary guard over `lib/`; it holds no allowlist
- `examples/` — PTY-based system tests for the `examples/` scripts (Linux/macOS only; no Windows
  `PTY`), each spawning its script, awaiting a glyph, sending a key and asserting a clean exit
