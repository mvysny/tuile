## [Unreleased]

- Add `Tuile::Color` — a value type wrapping the four color forms ANSI understands (named Symbol, 256-color Integer, RGB Array, or `nil`). Pre-defined constants `Color::RED`, `Color::BRIGHT_BLUE`, … cover the 16 named ANSI colors; `Color.coerce` accepts raw forms transparently.
- `Component::Label`: add `bg` accessor — applies a background color uniformly across every painted row (text, trailing pad, and blank rows past the last line). Accepts anything `Color.coerce` accepts.
- **Breaking:** `StyledString::Style#fg` and `#bg` now return `Color` (or `nil`) instead of the raw `Symbol`/`Integer`/`Array`. `Style.new` and `#merge` continue to accept the raw forms via `Color.coerce`.
- **Breaking:** Remove `StyledString::Style::COLOR_SYMBOLS` — moved to `Color::COLOR_SYMBOLS`.

## [0.4.0] - 2026-05-20

- Add `Screen#register_global_shortcut` for app-level hotkeys; registered shortcuts surface in the status bar via `hint:`.
- Add `Keys::CTRL_A..CTRL_Z` constants and `Keys.printable?` (extracted from `TextField`/`TextArea`/`Screen`).
- Extract `Component::TextInput` as the shared base of `TextField` and `TextArea`; add `#empty?`.
- `TextField`/`TextArea`: default `on_escape` to clear focus.
- `Screen#run_event_loop` accepts `capture_mouse:` (default `true`); pass `false` to skip xterm mouse tracking so the terminal's native select-to-copy keeps working.
- `StyledString`: add `#with_fg`, mirroring `#with_bg`.
- `Component::TextView`: add `#<<`, `#add_line`, `#empty?`, and `#remove_last_n_lines` for streaming-tail retraction.
- `MouseEvent`: map buttons 66/67 to `:scroll_left`/`:scroll_right`.
- `Component::LogWindow`: extract `#log` helper.
- `Component::List`: skip `auto_scroll` when rect is empty; re-snap on width change; snap cursor to last line on `auto_scroll`.
- Document `Component#repaint`'s attached-only call contract.
- Document keyboard input dispatch order and testing (`FakeScreen`, PTY system tests) in the README.
- **Breaking:** `Component::TextView#append` is now verbatim — chunks are concatenated onto the current last hard line, embedded `\n` becomes hard breaks, no implicit newline is inserted. Designed for streaming use (e.g. an LLM chat window feeding partial messages straight in). Aliased as `<<` for chainability. The old "add a new entry" behavior is now `Component::TextView#add_line`.
- **Breaking:** `MouseEvent.parse` raises on malformed input instead of silently truncating.
- Fix: `Component` gates `invalidate` and `repaint` on `attached?`, dropping the negative-rect relic.
- Fix: `Popup` recomputes size from content on every `#open`.
- Fix: `Keys.getkey` reads 5 trailing bytes after ESC, not 6.
- Fix: `Component::List#add_line` rejects `nil`.

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
