# Tuile

Tuile is a small component-oriented terminal-UI framework for Ruby. You build
your interface as a tree of components — windows, lists, text fields, popups —
and Tuile runs a single-threaded event loop that dispatches keys and mouse
events, then repaints everything that was invalidated since the last tick. The
name is French for "roof tile": small pieces that compose into a larger whole.

The design philosophy — "boxes within boxes" that talk via listeners and data
providers — is described in
[component-oriented programming](https://mvysny.github.io/component-oriented-programming/).
Tuile is that approach applied to a terminal.

If you have looked at the alternatives:

- [tty-toolkit](https://ttytoolkit.org/) (`tty-prompt`, `tty-cursor`, …) is a
  set of low-level building blocks rather than a framework: there is no
  component tree, no event loop, no invalidation. Tuile sits on top of
  `tty-cursor`/`tty-screen` and adds the framework layer.
- [vedeu](https://github.com/gavinlaking/vedeu) is the closest Ruby comparable
  but is no longer maintained (last release 2017).
- [ratatui](https://github.com/ratatui/ratatui) is the popular TUI framework
  in the Rust ecosystem; its immediate-mode API is closer to `tty-prompt` than
  to Tuile's retained component tree.

Tuile is the only actively maintained component-oriented TUI framework for
Ruby that we are aware of.

## Installation

Install the gem and add it to the application's Gemfile by executing:

```bash
bundle add tuile
```

If bundler is not being used to manage dependencies, install the gem by
executing:

```bash
gem install tuile
```

Or pin to git directly:

```ruby
gem "tuile", git: "https://github.com/mvysny/tuile.git"
```

Tuile requires Ruby 3.4+.

API documentation: <https://rubydoc.info/gems/tuile>.

## Hello world

```ruby
require "tuile"

# Screen must exist before any Component is built — components reach for
# Tuile::Screen.instance during invalidate/repaint hooks.
screen = Tuile::Screen.new

label = Tuile::Component::Label.new
label.text = "Hello, world!"

window = Tuile::Component::Window.new("Tuile")
window.content = label

screen.content = window
window.focus
begin
  screen.run_event_loop
ensure
  screen.close
end
```

Save it as `hello.rb` and run `ruby hello.rb`. Press `q` or `ESC` to exit.

A larger demo lives in [`examples/file_commander.rb`](examples/file_commander.rb):
a two-pane file browser with cursor navigation, header label, and a layout
that follows terminal resize. For a tour of every shipped component, run
[`examples/sampler.rb`](examples/sampler.rb): a two-pane sampler where the
left pane lists demos and the right pane loads the highlighted one. Tab /
Shift+Tab move focus between the list and the demo's widgets.

## How it works

### Component tree

Everything on screen is a `Tuile::Component`. Components have a `parent`,
`children`, a `rect` (absolute position), an `active?` flag (true for every
component on the focus chain root → focused), and an optional `key_shortcut`
that the framework will route keys to from anywhere in the tree.

A single `Tuile::Screen` (process singleton) owns the tree. Under it sits a
structural `ScreenPane` with three slots: tiled `content` (your app's main
layout), a `popups` stack (modal overlays), and a one-row `status_bar`.
Putting popups under the same parent as content means focus traversal,
attachment checks and child-removed callbacks all work uniformly.

### Layout and repaint

Tuile uses the simplest possible repaint model — no damage tracking, no
clipping, no diffing:

1. A component that needs to redraw calls `invalidate`. This just records the
   component in a set on the screen.
2. After the event loop drains the current batch of keyboard/mouse/posted
   events, the screen runs a single `repaint` pass:
   - Invalidated **tiled** components are sorted by tree depth (parents first)
     and each one fully redraws its `rect`.
   - If anything tiled was redrawn, **all popups** are drawn on top in
     stacking order. Popups deliberately overdraw content; there is no
     clipping.
   - The hardware cursor is moved to the focused component's
     `cursor_position` (e.g. into a focused text field).

This means a component is responsible for fully covering its own `rect` —
parents do not paint behind their children. `Layout` enforces this by simply
not drawing anything itself; its children must tile the entire layout area.
The trade-off is that if you leave gaps, they will show stale characters; the
upside is that the repaint code is tiny and predictable, and there is no
flicker because the terminal is written to in a single batched pass per tick.

### Single-threaded event loop

`Tuile::Screen#run_event_loop` reads keys and mouse events on a worker thread,
funnels them through `Tuile::EventQueue`, and processes them on the main
thread. **All** UI mutations — `rect=`, `content=`, `add_line`, `invalidate`,
`screen.focused=` — must run on that thread. Most UI methods will raise
`"UI lock not held"` if you violate this.

If you need to mutate the UI from a background thread (an HTTP poll, a file
watcher, a worker), marshal the work back via the queue:

```ruby
Thread.new do
  result = some_long_call
  screen.event_queue.submit { log_window.content.add_line(result) }
end
```

`SIGWINCH` (terminal resize) is plumbed through the same queue: the framework
posts a size event, runs layout, and invalidates the entire tree. Components
react by reassigning their child rectangles inside `rect=` — do not install
your own WINCH handler.

### Focus and keyboard input

`screen.focused = component` walks parent pointers up to the root, marks the
whole chain `active?`, and deactivates everything else. Click-to-focus and
`Layout#on_focus` only ever forward focus to components whose `focusable?`
returns true, so clicking a `Label` inside a `Window` does not pull focus
away from the window's content.

When a key arrives, the screen dispatches it in this order — the first
mechanism that handles it wins:

1. **Tab / Shift+Tab** advance focus through `tab_stop?` components in the
   current modal scope (the topmost popup if one is open, otherwise the
   tiled content). They are intercepted at the screen level before anything
   else sees them, so a focused `TextField` cannot swallow them.

2. **Global shortcuts** registered via `Screen#register_global_shortcut`.
   These are app-level hotkeys for actions that don't belong to any
   specific component — opening a log window, toggling help, etc.:

   ```ruby
   screen.register_global_shortcut(Tuile::Keys::CTRL_L,
                                   over_popups: true,
                                   hint: "^L #{screen.theme.hint('log')}") do
     log_popup.open
   end
   screen.unregister_global_shortcut(Tuile::Keys::CTRL_L)
   ```

   Only unprintable keys are accepted (control characters, ESC, BACKSPACE,
   arrows, F-keys); printable keys raise so they can't hijack typing into
   a `TextField`. By default, the shortcut is suppressed while any popup
   is open and the popup receives the key; pass `over_popups: true` to
   pre-empt the popup.

   Pass `hint:` to surface the shortcut in the status bar. It's a
   preformatted string the caller fully owns (color it however the rest
   of your app does). In the tiled case it appears right after `q quit`
   and before the active window's hint; while a popup is open, only
   `over_popups: true` hints show up, prepended before the popup's
   `q Close`. Omit `hint:` to leave the shortcut silent in the status bar.

3. **`Component#key_shortcut`** — a declarative hotkey attached to a
   component. The framework walks the focused component's subtree for a
   match and focuses the winner. Good fit for "press F to focus the filter
   field" or one-key tab pickers. The lookup is suppressed while the
   focused component owns the hardware cursor (e.g. a `TextField` the user
   is typing into) so editing isn't interrupted:

   ```ruby
   filter_field.key_shortcut = "f"
   ```

4. **`Component#handle_key`** — override this on your own component when
   it needs to react to keys directly (a list reacting to arrows, a custom
   widget handling Enter, …). Return `true` to mark the key handled,
   `false` to let the dispatcher keep walking. Call `super` to keep the
   default `key_shortcut` subtree lookup; suppress it only when you
   deliberately want this component to swallow everything:

   ```ruby
   class Toggle < Tuile::Component
     def handle_key(key)
       if key == " "
         @on = !@on
         invalidate
         true
       else
         super
       end
     end
   end
   ```

If nothing handles the key and it's `q` or `ESC`, the event loop exits.

A component can advertise the keys it responds to by overriding
`keyboard_hint`. The status bar shows the active window's hint alongside
the global `q quit` prompt; while a popup is open, the popup's own hint
replaces it, prefixed with `q Close`:

```ruby
class FilterWindow < Tuile::Component::Window
  def keyboard_hint
    "f #{screen.theme.hint('filter')}  Enter #{screen.theme.hint('open')}"
  end
end
```

### Theming

The accent colors built-in components paint with — the list-cursor /
focused-input highlight, the inactive input "well", the active window
border, the status-bar hint color — come from a `Tuile::Theme`, a frozen
value type of semantic color tokens. The current theme lives at
`screen.theme`.

The theme is picked automatically when the screen is constructed:
`Screen.new` queries the terminal's background color (OSC 11, with a
`COLORFGBG` fallback) and selects `Theme::LIGHT` on light backgrounds,
`Theme::DARK` (the colors Tuile has always used) otherwise. While the
event loop runs, terminals supporting mode 2031 (kitty, foot, contour,
ghostty, …) push appearance changes, and the screen follows OS
light/dark flips live, repainting everything in the matching theme.
Override it any time:

```ruby
screen.theme = Tuile::Theme::LIGHT
# or tweak a single token (tokens are strict: `Color` instances only):
screen.theme = Tuile::Theme::DARK.with(active_border_color: Tuile::Color::CYAN)
```

Note a bare `theme=` assignment is transient: the next OS appearance flip
re-picks from the screen's `ThemeDef` and replaces it. To theme an app
durably, see [App themes](#app-themes) below.

The theme's primary API is its rendering helpers — `active_bg(text)`,
`active_border(text)`, `input_bg(text)`, `hint(text)` — which return the
text wrapped in the token's color:

```ruby
screen.theme.hint("quit")        # => "\e[38;5;109mquit\e[0m"
screen.theme.active_bg("[ Ok ]") # => "\e[48;5;59m[ Ok ]\e[0m"
```

The raw colors are also readable via the `*_color` counterparts
(`active_bg_color`, …) for span-aware styling with `StyledString`.

Assigning a theme invalidates every component, so the whole UI restyles on
the next repaint. One caveat: strings with colors already baked in (global
shortcut `hint:`s, `Theme#hint` output you cached) don't restyle —
rebuild them in `Component#on_theme_changed` (see
[Reacting to theme changes](#reacting-to-theme-changes)).

Everything that isn't an accent deliberately inherits the terminal's own
default foreground/background, which already matches the user's terminal
theme — so there is no global `bg`/`fg` token to configure.

### App themes

Your app's own colors belong in the theme too, so they restyle in the same
invalidate-everything pass and stay legible on both terminal backgrounds.
Beyond the built-in tokens, a theme carries app-specific tokens in
`custom` — a `Hash{Symbol => Color}`. Look them up with `theme[:token]`
(fail-fast: a typo raises `KeyError` instead of quietly painting a
default) and render with the generic `fg` / `bg` helpers:

```ruby
theme = Tuile::Theme::DARK.with(custom: { accent: Tuile::Color::DARK_ORANGE })
theme[:accent]             # => Color — e.g. for StyledString#with_fg
theme.fg(:accent, "NEW")   # => "\e[38;5;208mNEW\e[0m"
```

`Color::DARK_ORANGE` is `Color.palette(208)` — the 256-color palette
carries a constant per standard xterm chart name (`CADET_BLUE`,
`DODGER_BLUE1`, `GREY37`, …; see `Color::PALETTE_NAMES`), so a theme
declaration can say which color it means instead of citing a bare index.

The recommended shape is a `Theme` subclass that implements one coloring
function per custom token, mirroring the built-in helpers (`hint`,
`active_bg`, …) — call sites then read `theme.added("+42")` instead of
`theme.fg(:added, "+42")`. `Data#with` preserves the subclass, so an
`AppTheme` stays an `AppTheme` through `with`:

```ruby
class AppTheme < Tuile::Theme
  # one coloring function per custom token
  def added(text)   = fg(:added, text)
  def removed(text) = fg(:removed, text)
end
```

Build both appearance variants and pair them in a `Tuile::ThemeDef`
assigned to `screen.theme_def=`. This is the durable way to theme an app:
the screen picks the member matching the detected background at startup
and re-picks on every OS appearance flip, so your definition survives
light/dark toggles where a bare `theme=` assignment would be replaced.
`ThemeDef.new` enforces that both members declare the same custom key
set — a token present in only one variant fails at construction instead
of raising `KeyError` at the unpredictable moment the user flips
appearance:

```ruby
APP_THEME = Tuile::ThemeDef.new(
  dark:  AppTheme.new(**Tuile::Theme::DARK.to_h,
                      custom: { added:   Tuile::Color::DARK_SEA_GREEN,
                                removed: Tuile::Color::LIGHT_PINK3 }),
  light: AppTheme.new(**Tuile::Theme::LIGHT.to_h,
                      custom: { added:   Tuile::Color::SPRING_GREEN4,
                                removed: Tuile::Color::INDIAN_RED })
)
screen.theme_def = APP_THEME
```

### Reacting to theme changes

Built-in components read `screen.theme` at paint time, so their accents
restyle automatically. Content you rendered yourself does not: a
`StyledString` stored in `Label#text` / `List#lines` / `TextView#text`
has its colors baked in at construction, and only your app knows which of
those were theme-derived (as opposed to inherent to the data — log-level
colors, say). `Component#on_theme_changed` fires on every attached
component when the theme changes (assignment or appearance flip); rebuild
theme-derived content there by re-running the code that rendered it
initially. Consume it either way:

```ruby
# composition style — assembling stock components:
label.on_theme_changed = -> { label.text = render_status_line }

# subclass style — call `super` so an assigned listener keeps firing:
class DiffView < Tuile::Component::TextView
  def on_theme_changed
    super
    self.text = render_diff   # screen.theme already returns the new theme
  end
end
```

The hook runs on the UI thread and repaint coalesces per tick, so
mutating content inside it is safe. Don't assign `screen.theme=` from
inside the hook.

## Components

All components live under `Tuile::Component::*`. Each one is documented below
with the methods you are most likely to reach for; full API docs are in the
YARD output (`bundle exec rake yard`).

### `Component::Label`

Static text. No word-wrapping; long lines are clipped to `rect.width`. Lines
may contain ANSI SGR formatting — theme helper output, a `StyledString`,
or any SGR-emitting library (e.g. Rainbow, which is no longer a Tuile
dependency — add it to your own Gemfile if you use it).

```ruby
label = Tuile::Component::Label.new
label.text = "Hello, #{screen.theme.hint('world')}!"
```

Key API: `text=`, `content_size`.

### `Component::Layout`

Positions children but paints nothing of its own — children must completely
cover the layout's `rect`. Use `add(child)` and `remove(child)`. By default,
focus forwards to the first focusable child.

```ruby
class Header < Tuile::Component::Layout::Absolute
  def initialize
    super
    @left = Tuile::Component::Label.new
    @right = Tuile::Component::Label.new
    add(@left)
    add(@right)
  end

  def rect=(new_rect)
    super
    @left.rect  = Tuile::Rect.new(rect.left, rect.top, rect.width / 2, 1)
    @right.rect = Tuile::Rect.new(rect.left + rect.width / 2, rect.top,
                                  rect.width - rect.width / 2, 1)
  end
end
```

`Layout::Absolute` is the recommended base when you want to position children
manually; it inherits all the focus / key dispatch wiring and only asks you
to override `rect=` to reposition children whenever the parent resizes.

### `Component::Window`

A bordered frame with a caption and a single content slot. Optionally has a
`footer` (a component that overlays the bottom border row, e.g. a search
field) and a built-in scrollbar when the content is a `List`.

```ruby
window = Tuile::Component::Window.new("Settings")
window.content = some_list
window.scrollbar = true       # only valid when content is a Component::List
window.footer    = search_field
```

Key API: `content=`, `footer=`, `caption=`, `scrollbar=`. Windows are
focusable; focus delegates to content (or footer when active).

### `Component::List`

A scrollable list of strings with optional cursor and scrollbar.

```ruby
list = Tuile::Component::List.new
list.lines = ["alpha", "beta", "gamma"]
list.cursor = Tuile::Component::List::Cursor.new
list.on_item_chosen = ->(index, line) { Tuile.logger.info("picked #{line}") }
list.auto_scroll = true       # auto-scroll to bottom on add_line
list.add_line("delta")
```

Cursor variants:

- `List::Cursor::None` — no cursor (default).
- `List::Cursor` — lands on every line; arrows / `jk` / Home / End / Ctrl+U /
  Ctrl+D move it.
- `List::Cursor::Limited` — restricts the cursor to a fixed set of line
  positions (useful for menus where only some rows are selectable).

Pressing Enter or left-clicking an item fires `on_item_chosen(index, line)`.

Key API: `lines=`, `add_line`, `add_lines`, `cursor=`, `top_line=`,
`auto_scroll=`, `scrollbar_visibility=`, `on_item_chosen`,
`select_next` / `select_prev` (search).

### `Component::TextField`

A single-line input with a real terminal caret. The field does not scroll —
keystrokes that would overflow `rect.width - 1` are rejected.

```ruby
field = Tuile::Component::TextField.new
field.text       = "initial"
field.on_change  = ->(text)  { filter_results(text) }
field.on_enter   = ->         { submit(field.text) }
field.on_escape  = ->         { popup.close }
field.on_key_up  = ->         { results.cursor.go_up_by(1) }
```

Optional callbacks: `on_change`, `on_enter`, `on_escape`, `on_key_up`,
`on_key_down`. When set, the corresponding key is consumed by the field; when
nil, the key falls through to the parent (e.g. ESC closes the surrounding
popup by default).

### `Component::Popup`

A modal overlay. It paints nothing itself: it wraps any component as
`content`, centres itself on the screen, auto-sizes to the wrapped content,
and consumes `q` / `ESC` to close. Popups are drawn on top of the tiled
content; multiple popups stack.

```ruby
window = Tuile::Component::Window.new("Help")
window.content = help_list
Tuile::Component::Popup.open(content: window)
# or, equivalently:
popup = Tuile::Component::Popup.new(content: window)
popup.open
# popup.close, popup.open?
```

Bare content also works (a `Label`, a `List`…) and yields a borderless popup;
wrap in a `Window` if you want a frame.

### `Component::InfoWindow`

A `Window` preconfigured with a `List` of static lines. Convenient for
read-only information.

```ruby
Tuile::Component::InfoWindow.open("Cannot open", [path, error.message])
```

Usable tiled too — just `add` it to a layout.

### `Component::PickerWindow`

A `Window` that lists single-keystroke options and fires a callback when one
is picked. ESC / `q` cancel without firing.

```ruby
Tuile::Component::PickerWindow.open("Choose action", [
  ["e", "Edit"],
  ["d", "Delete"],
  ["c", "Copy"]
]) do |key|
  perform(key)
end
```

The callback receives the picked option's key. The popup variant closes
itself after the pick.

### `Component::LogWindow`

A `Window` whose content is an auto-scrolling `List`. Wire your logger at it
through `LogWindow::IO`:

```ruby
log_window = Tuile::Component::LogWindow.new("Log")
Tuile.logger = Logger.new(Tuile::Component::LogWindow::IO.new(log_window))
Tuile.logger.info("started up")
```

`LogWindow::IO` implements both `write` (stdlib `Logger`) and `puts`
(`TTY::Logger` and similar), and marshals lines back through the event queue,
so it is safe to log from any thread. Tuile itself is silent unless the host
app sets `Tuile.logger`.

## Geometry primitives

`Tuile::Point`, `Tuile::Size`, `Tuile::Rect` are `Data.define` value types
(frozen, structural equality). `Rect` uses **half-open** edges:
`rect.contains?(point)` is true when `x >= left && x < left + width`. `Rect`
also offers `centered`, `clamp_height`, `top_left`, etc.

## Logging

Tuile writes to `Tuile.logger`, which defaults to a `Logger.new(IO::NULL)`
(silent). Set it to any object that quacks like the stdlib `Logger`
interface:

```ruby
Tuile.logger = Logger.new($stderr)              # or:
Tuile.logger = TTY::Logger.new                  # duck-typed, works directly
Tuile.logger = Logger.new(Tuile::Component::LogWindow::IO.new(window))
```

## Testing

Tuile ships with a `Tuile::FakeScreen` that you install in place of the real
screen for unit tests. It fixes the viewport at 160×50, disables the UI lock,
collects every string the framework "would have printed" into an array, and
uses a synchronous `FakeEventQueue` (submitted blocks run inline; posted
events are discarded). No terminal IO happens, so the TTY running the tests
is never painted over.

The standard setup is `Screen.fake` / `Screen.close` as a before/after pair —
this resets the singleton between examples, so state can't leak across
tests:

```ruby
require "tuile"

module Tuile
  describe Component::Label do
    before { Screen.fake }
    after  { Screen.close }

    it "renders text into its rect" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "hi"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "hi   "], Screen.instance.prints
    end
  end
end
```

Key hooks:

- `Screen.instance.prints` — array of strings the screen would have written
  to the terminal. Assert against it (or `.join`) for repaint output.
- `Screen.instance.repaint` — drive a repaint synchronously; production code
  must not call this, but specs use it to flush the invalidated set after a
  mutation.
- `Screen.instance.invalidated?(component)` / `invalidated_clear` — verify
  that a mutation did (or did not) invalidate something. Setting a property
  to its current value should typically *not* invalidate.
- `Screen.instance.clear` — drops accumulated `prints` without resetting
  invalidation.

Because `FakeEventQueue#submit` runs the block immediately on the calling
thread, code paths that marshal work back via `screen.event_queue.submit { … }`
just work in tests. Posted events (`#post`) are dropped — if your test needs
to drive a real event loop, you are in system-test territory.

For end-to-end tests of a runnable script, spawn it in a pseudo-TTY with
`PTY.spawn`, wait for a known glyph to confirm the first paint landed, send
a key, and assert the exit status. `spec/examples/hello_world_spec.rb` is the
canonical template; PTY-based tests are Linux/macOS only since Ruby's stdlib
`PTY` isn't on Windows.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then,
run `bundle exec rake spec` to run the tests. You can also run `bin/console`
for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.
To release a new version, see [`RELEASING.md`](RELEASING.md).

## Contributing

Bug reports and pull requests are welcome on GitHub at
<https://github.com/mvysny/tuile>. Please read [`AGENTS.md`](AGENTS.md) before
opening a PR — it documents the architecture invariants (singleton screen,
invalidation/repaint contract, threading rule) that the framework relies on.
This project is intended to be a safe, welcoming space for collaboration, and
contributors are expected to adhere to the
[code of conduct](https://github.com/mvysny/tuile/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).

