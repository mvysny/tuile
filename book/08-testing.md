# 8. Testing a Tuile app

**Status: stub.**

The closing chapter: how to test a Tuile app without a real terminal.
Narrative and walkthrough-driven — the *approach* and the use-cases; the
`FakeScreen` API surface stays in the rdoc.

Will cover:

- `Screen.fake` / `Screen.close` as the before/after pair: an in-memory
  `FakeScreen` (fixed 160×50 viewport, no terminal IO, no UI lock,
  synchronous `FakeEventQueue`), and why it resets the singleton so
  state can't leak between examples.
- Asserting painted content against the buffer: `buffer.region_text` /
  `region_ansi` scoped to a component's `rect`, and `cell(x, y)` for a
  single cell.
- Driving the system: `Screen#repaint` to flush after a mutation (tests
  only — production never calls it), and `invalidated?` /
  `invalidated_clear` to check that a mutation did or didn't invalidate.
- Why `submit`-based background code just works under the synchronous
  fake queue.
- End-to-end tests of runnable scripts: `PTY.spawn`, wait for a known
  glyph, send a key, assert a clean exit (Linux/macOS only).
