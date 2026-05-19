## [Unreleased]

- `Screen#run_event_loop` accepts `capture_mouse:` (default `true`); pass `false` to skip xterm mouse tracking so the terminal's native select-to-copy keeps working.
- **Breaking:** `Component::TextView#append` is now verbatim — chunks are concatenated onto the current last hard line, embedded `\n` becomes hard breaks, no implicit newline is inserted. Designed for streaming use (e.g. an LLM chat window feeding partial messages straight in). Aliased as `<<` for chainability. The old "add a new entry" behavior is now `Component::TextView#add_line`.

## [0.3.0] - 2026-05-18

- Add `Component::TextView` — read-only scrollable wrapped prose with word wrap, incremental append, and a lazy text reader.
- Add `Tuile::StyledString` for span-modeled ANSI styling, with `#wrap` (span-preserving word wrap), `#ellipsize` (width-bounded truncation), `#with_bg`, and an `EMPTY` shared instance.
- Model `Label`, `List`, and `TextView` text as `StyledString`; pre-pad clipped/physical lines.
- Extract `Tuile::Ansi` for shared ANSI helpers.
- `Window#scrollbar=` accepts any content that exposes `scrollbar_visibility=`.
- Document `TextView` in the README and `examples/sampler.rb`.
- Remove `Tuile::Wrap` (superseded by `StyledString#wrap`).
- Remove `Tuile::Truncate` (superseded by `StyledString#ellipsize`).

## [0.2.0] - 2026-05-15

- Add `Component::TextArea` with multi-line editing, word navigation, and VT220-style Home/End handling.
- Add `Component::Button`.
- Add Tab / Shift+Tab focus cycling.
- Add Ctrl+arrow word navigation to `Component::TextField`.
- Add `Component::List#on_cursor_changed`.
- Add `examples/sampler.rb`.
- Paint `TextField` with a colored background.
- Buffer `Screen#print` into a per-frame buffer during repaint, and release it on exception.
- Join the key thread after killing it in `run_loop`'s ensure block.
- Auto-clear gappy children in `Component#repaint`.
- Inline a minimal truncation helper and drop the `strings-truncation` dependency.
- Lower the Ruby floor to 3.4; pin CI head to 4.0; fix Ruby 3.4 compatibility.
- Bump `minitest` to 6.0.
- Document `TextField` SGR constants; refresh `sig/tuile.rbs`.

## [0.1.0] - 2026-05-02

- Initial release
