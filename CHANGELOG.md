## [Unreleased]

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
