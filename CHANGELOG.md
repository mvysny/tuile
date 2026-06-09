## [Unreleased]

## [0.7.0] - 2026-06-09

- Lower the Ruby floor to 3.3 (was 3.4): replaced the `it` implicit block parameter (3.4+) with `_1` throughout, and added 3.3 to the CI matrix.
- Fix `Component::Popup#close` raising `Tuile::Error` when the popup was not open — it is now the documented no-op (also covers calling `close` twice). `Screen#remove_popup` honors its "does nothing if not open" contract by guarding on `has_popup?`; `ScreenPane#remove_popup` keeps its strict internal assertion.

## [0.6.0] - 2026-06-07

- Add `Tuile::Theme` — semantic color tokens for the accents built-in components paint (the list-cursor/focused-input highlight `active_bg_color`, the inactive input well `input_bg_color`, the active window border `active_border_color`, the status-bar `hint_color`), with `DARK`/`LIGHT` presets and rendering helpers (`#active_bg`, `#active_border`, `#input_bg`, `#hint`). The current theme lives at `Screen#theme`; assigning restyles the whole UI in a single invalidate-everything pass. Everything that isn't an accent keeps inheriting the terminal's own default fg/bg.
- Auto-detect the light/dark terminal background at startup: `Screen.new` queries the terminal via OSC 11 (`COLORFGBG` fallback, dark when inconclusive) and picks `Theme::LIGHT`/`Theme::DARK` to match.
- Follow OS light/dark appearance flips live via mode 2031 (kitty, foot, contour, ghostty, …): the screen re-picks the matching theme and repaints everything.
- Add app-specific theme tokens: `Theme#custom` (`Hash{Symbol => Color}`), looked up fail-fast via `Theme#[]` (`KeyError` on typos) and rendered via the generic `#fg`/`#bg` helpers. Subclass `Theme` to add one semantic coloring function per custom token — `Data#with` preserves the subclass. Theme tokens are strictly `Color` instances; `Color` gains the `Color.palette`/`Color.rgb` named constructors.
- Add `Tuile::ThemeDef` — an app's dark/light `Theme` pair. Assigning `Screen#theme_def=` is the durable way to theme an app: the screen picks the member matching the detected background at startup and on every appearance flip, where a bare `theme=` assignment is transient. Construction validates that both members declare the same custom key set.
- Add `ThemeDef.default` — the definition newly-constructed screens start from (initially `ThemeDef::DEFAULT`). Reassign it once in `spec_helper.rb` and every `Screen.fake` carries the app's custom tokens, instead of repeating `theme_def=` in each `before` block.
- Name the 256-color palette: a constant per standard xterm chart name for palette indices 16..255 (`Color::CADET_BLUE` is `Color.palette(72)`; `Color::DODGER_BLUE1`, `Color::GREY37`, …) — exact palette cells, no quantization, listed in `Color::PALETTE_NAMES`. Where the chart names several cells identically, the first cell wins the constant; indices 0..15 keep the symbolic `Color::RED`/`Color::BRIGHT_BLUE`/… constants, which respect the terminal's own scheme.
- Add `Color.hex` — a 24-bit RGB color from a CSS-style hex string (`Color.hex("#333333") == Color.rgb(51, 51, 51)`; leading `#` optional, case-insensitive, 3-digit shorthand expands as in CSS). Alpha forms (`#rgba`/`#rrggbbaa`) are rejected — SGR has no alpha channel. `Color.coerce` stays string-free; `.hex` is the explicit entry point.
- Add `Component#on_theme_changed` — fired pre-order across the attached tree on every theme change, so apps can rebuild styled content whose colors were derived from the old theme. Override it (calling `super`) or assign the `on_theme_changed=` proc.
- Add `Tuile::Sizing` (`FILL` / `WRAP_CONTENT` / `Sizing.fixed(n)`) and `Window#footer_sizing` — the footer slot is sized per policy against the inner width; a `WRAP_CONTENT` footer re-lays-out live as its content changes. The footer is excluded from `Window#content_size`: it is decoration overlaying the border and must not drive window size.
- `Component#content_size` is now maintained eagerly: content mutators assign via the protected `content_size=` setter, which fires `parent.on_child_content_size_changed(self)` only when the value actually changed. Fixes a `Popup` staleness — an open popup now re-sizes and recenters when its content grows.
- **Breaking:** `rainbow` is no longer a runtime dependency (nothing under `lib/` uses it — `Theme`/`StyledString`/`Color` produce all SGR output). Apps that style text with Rainbow must add it to their own Gemfile.

## [0.5.0] - 2026-05-21

- Add `Tuile::Color` — a value type wrapping the four color forms ANSI understands (named Symbol, 256-color Integer, RGB Array, or `nil`). Pre-defined constants `Color::RED`, `Color::BRIGHT_BLUE`, … cover the 16 named ANSI colors; `Color.coerce` accepts raw forms transparently.
- `Component::Label`: add `bg` accessor — applies a background color uniformly across every painted row (text, trailing pad, and blank rows past the last line). Accepts anything `Color.coerce` accepts.
- Add `Component::TextView::Region` — opaque handle to a contiguous run of hard lines, so apps can stream into logical sections without tracking line indices across sibling mutations. Create with `view.create_region`; mutate via `region.append`/`#<<`/`#text=`/`#add_line`/`#remove_last_n_lines`/`#replace`/`#insert`/`#remove`. Detached handles raise on every reader / mutator (except `#remove`, which is idempotent). `view.text=` / `clear` detach all region handles and install a fresh internal default.
- Add `Component::TextView#replace(range, str)` and `#insert(at, str)` for mid-buffer hard-line splices (Integer or Range, inclusive/exclusive end, empty range == insertion, `begin == hard-line count` valid for end-insertion).
- `Component::TextView`: incremental wrap via a per-hard-line row-count cache — mid-buffer mutations now re-wrap only the affected slice instead of the whole buffer. Speeds up the LLM streaming path (mid-document `region.append`, tombstone-style `region.text=`, `view.replace`/`view.insert`). `view.append` on the spatial tail keeps its existing fast path; `view.text=` and `on_width_changed` still do a full rewrap (now rebuilding the cache too).
- Add `EventQueue#tick(fps) { |n| ... }` returning a `Ticker` backed by `Concurrent::TimerTask`; fires on the event-loop thread with a 0-based monotonic counter. Intended for spinner animations, periodic refresh, or surfacing background-task progress. Auto-cancels on raise.
- Add `FakeEventQueue#tick` and `FakeTicker` — synchronous test double that drives ticks deterministically.
- **Breaking:** `StyledString::Style#fg` and `#bg` now return `Color` (or `nil`) instead of the raw `Symbol`/`Integer`/`Array`. `Style.new` and `#merge` continue to accept the raw forms via `Color.coerce`.
- **Breaking:** Remove `StyledString::Style::COLOR_SYMBOLS` — moved to `Color::COLOR_SYMBOLS`.
- **Breaking:** `EventQueue#run_loop` now yields submitted `Proc` events to its consumer block instead of dispatching them inline, so a raise from a `submit{}` block is routed through `Screen#on_error` like any other event. Custom `run_loop` consumers must `call` Procs in their case statement.

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
