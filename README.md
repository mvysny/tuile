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

Tuile requires Ruby 3.3+.

One component — `Component::BigDecimalField` — additionally needs the
`bigdecimal` gem, which Tuile deliberately does *not* depend on (it has been a
bundled gem since Ruby 3.4, so Bundler no longer puts it on the load path for
free). Add `gem "bigdecimal"` to your Gemfile if you use that field; nothing
else in Tuile loads it.

## Documentation

- **[The Tuile guide](book/README.md)** teaches Tuile cover to cover, in
  order — the concepts and the *why*. Start here; the summary below links
  into it chapter by chapter, and the layout chapter is the heart of the
  design.
- **API reference:** every public class and method carries YARD headers —
  browse them at <https://rubydoc.info/gems/tuile>, or run
  `bundle exec rake yard` for a local site.

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

**A retained tree, not a redraw loop.** Everything on screen is a
`Tuile::Component` with a `parent`, `children` and a `rect`. A singleton
`Tuile::Screen` owns the tree; under it a `ScreenPane` holds the tiled
content and a stack of popups. You build the tree once and mutate it —
there is no per-frame rebuild and no immediate-mode redraw. Tuile paints no
chrome of its own and reserves no row: your content gets the whole
terminal, and a status line is yours to build if you want one.
→ [chapter 1](book/01-first-app.md)

**Repaint is automatic, and flicker-free without trying.** Components never
write escape sequences. They call `invalidate`, and paint styled cells into a
back buffer when the loop asks them to; one flush per tick emits the
**minimal diff** — only the cells that actually changed — inside a
synchronized-output batch. There is no damage tracking to maintain and no
clipping to think about: popups simply overdraw, because overdraw into a
buffer is free. → [chapter 2](book/02-repaint.md)

**Layout is top-down, and that is the whole model.** A parent computes its
children's rectangles in plain Ruby and assigns them; a component never
advertises a size it would like. No `min`/`preferred`/`max`, no negotiation
pass, no shrink-to-fit. Subclass `Layout::Absolute` when the arithmetic is
yours, or use `Layout::Vertical` / `Layout::Horizontal` to declare each
child's extent as `Fixed` / `Percent` / `Expand`.
→ [chapter 3](book/03-layout.md)

**One thread owns the UI.** Keys and mouse are read on a worker thread but
dispatched on the loop's, and *every* UI mutation must happen there —
violating it raises `Tuile::Error` rather than corrupting the screen.
Background work marshals back through `screen.event_queue.submit { … }`, and
periodic work through `tick` / `tick_fps`. Resize isn't a callback either:
`SIGWINCH` becomes an event in the same queue.
→ [chapter 4](book/04-event-loop.md)

**Keys are routed by focus, in three rungs.** Tab and Shift+Tab are claimed
above everything, so focus can never be trapped inside a widget; then an
app-level registry (`Screen#register_global_shortcut`, which refuses keys a
widget might need, printables included); then delivery to the focused
component, bubbling up its ancestors to the scope root — which is what makes
an ancestor the natural home for a form's Enter or a layout's one-key jumps
between panes. A paste is deliberately *not* a burst of keys: with bracketed
paste it arrives whole, as one `handle_paste`.
→ [chapter 5](book/05-focus.md)

**Theming is accents-only, and follows the OS.** A `Theme` carries semantic
accent tokens — the list cursor, an input well, an active window border,
status-bar hints — plus whatever `custom` tokens your app adds. Everything
else inherits the terminal's own foreground and background, so Tuile looks at
home in the user's palette instead of fighting it. Tuile probes the terminal
background at startup, pairs a dark and a light theme in a `ThemeDef`, and
re-picks on a live OS appearance flip.
→ [chapter 6](book/06-theming.md)

## Components

Every component lives under `Tuile::Component::*`, and every one of them is a
`Tuile::Component`: its parent sizes it top-down, it invalidates rather than
paints, and it draws its accents from the theme. This is the catalogue — one
line each, so you can find the right name. The **book** explains when and why
to reach for each (chapter 7 is a tour organized by the job), and the **rdoc**
carries the per-method reference: `bundle exec rake yard`, or
<https://rubydoc.info/gems/tuile>.

### Laying out — [book ch3](book/03-layout.md)

| component | what it is |
|---|---|
| `Layout::Absolute` | Positions children by assigning their `rect` in a `rect=` override, and paints nothing itself. The base to subclass when the arithmetic is yours. |
| `Layout::Vertical`, `Layout::Horizontal` | Stack children along one axis from declared extents — `Fixed[n]`, `Percent[n]`, `Expand[weight]` — with box-global `spacing` and `padding`. Sugar over `Absolute`, not a new sizing model. |

### Framing and switching — [book ch7](book/07-components.md#framing-content)

| component | what it is |
|---|---|
| `Window` | A frame with a `caption`, one content slot, and a border that lights up while the window is on the focus chain. `footer_text=` decorates the bottom border; `footer=` mounts a real component in it; `scrollbar=` reclaims the right border column. |
| `MenuBar` | A one-row strip of menu captions, each dropping a cascade of submenus that nests without limit. Items are handles from `#add_item`, each with its own `on_click`. See [Menus](book/07-components.md#menus). |
| `Tabs` | A one-row strip of captions with one selected, Left/Right switching immediately. Knows nothing about content — pair it with `TabSheet`, or drive your own view swap from `on_tab_selected`. |
| `TabSheet` | A `Tabs` strip plus the pane belonging to the selected tab. Unselected panes are *detached*, so they keep their state and stay out of the Tab cycle. See [Switching between views](book/07-components.md#switching-between-views). |

### Showing text — [book ch7](book/07-components.md#showing-text)

| component | what it is |
|---|---|
| `Label` | Static text, one row per line, no wrapping — long lines are ellipsized. Content is a `StyledString`, so ANSI passes through. |
| `TextView` | A read-only viewer for prose: word-wrapped, scrollable, appendable, and addressable in named `Region`s when you want to rewrite one part of the text in place. |
| `ProgressBar` | A one-row bar — `█` over a `░` track — driven by `value` within a `Range`, or `indeterminate` for a bouncing sweep that owns its own ticker while on screen. |

### Editing text — [book ch7](book/07-components.md#editing-text)

| component | what it is |
|---|---|
| `TextField` | A single-line input with a real hardware caret, scrolling horizontally to keep the caret in view. |
| `PasswordField` | A `TextField` that paints one mask glyph per character; editing, caret and clicks are unchanged. |
| `TextArea` | A multi-line, word-wrapping input with a caret that moves by grapheme cluster, word-jumps, and a viewport that scrolls to follow it. |

### Typed values — [book ch7](book/07-components.md#the-value-seam)

| component | what it is |
|---|---|
| `IntegerField` | A one-row field whose `value` is an `Integer` or `nil`, filtering input to digits and one leading `-`. |
| `FloatField` | The same, one Ruby type over: `value` is a `Float` or `nil`. |
| `BigDecimalField` | The same for money, where a binary `Float` is the wrong answer. Tuile's one optional dependency — add `bigdecimal` yourself if you name this component. |

### Choosing from a set — [book ch7](book/07-components.md#choosing-from-a-set)

| component | what it is |
|---|---|
| `Checkbox` | A one-row boolean: `[x]` / `[ ]` plus a caption, toggled by Space, Enter or a click on the glyph or label. |
| `List` | The workhorse: a scrollable column of *typed items*, one row each, rendered lazily by a `renderer` you supply and handing your callbacks the item itself. Add a `Cursor` (or `Cursor::Limited`) to make it navigable. |
| `RadioGroup` | Single-select over a set of items, one row each, with the marker painted in front of the label. Its `value` is the selected item. |
| `CheckboxGroup` | Multi-select over the same shape; its `value` is a frozen `Set` of the checked items. |
| `Select` | The enum field: a one-row face plus a `▾`, dropping open a list of options. Claims no printable key but Space, so your app's own keys keep working while it has focus. |
| `ComboBox` | A text field with a filtering dropdown — type to narrow, arrow to highlight, Enter to accept. Its `value` is the selected *item*, never the typed text. |
| `ListDropdown` | The floating, non-focusable list that `Select` and `ComboBox` drop open, and the `Menu` variant an app can drive itself. You rarely instantiate it directly. |

### Taking an action — [book ch7](book/07-components.md#taking-an-action)

| component | what it is |
|---|---|
| `Button` | A one-row `[ caption ]` running a block on Enter, Space or a left click. Size it yourself: `caption.display_width + 4`. |

### Overlays and windows — [book ch7](book/07-components.md#overlays)

| component | what it is |
|---|---|
| `Overlay` | The bare floating layer: it wraps any component, paints nothing itself, and sits at the rect you assign it. Takes no focus and no keys — the building block for anchored panels and toasts. |
| `Popup` | The modal dialog: an `Overlay` that centers itself, grabs focus, scopes keys to its own subtree and blocks clicks beneath it. Sized by `size=` (a `Size` or a `Fraction` of the screen) rather than by its content; ESC or `q` dismisses. |
| `Notification` | A transient corner toast — `Notification.show("Saved")` — stacking messages in one box that a single ticker drains. Non-modal, and it never takes focus. |
| `InfoWindow` | A `Window` of static lines, tiled or popped up. For read-only information you don't want to assemble by hand. |
| `PickerWindow` | A `Window` of options identified by single keystrokes, firing a callback with the key that was pressed. |
| `LogWindow` | A scrolling log view. Point your logger at a `LogWindow::IO` and lines land here from any thread, marshalled through the event queue. |

The mixins those share — `HasValue` (the `value` / `empty?` / `clear` /
`on_value_change` seam every input speaks), `HasContent` (one-child
containers) and `HasCaption` (app-authored chrome text) — are the seams to
include when you write your own; chapter 7's "value seam" section is the
walkthrough.

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
paints into an in-memory back buffer (assert on it for painted content) while
capturing cursor/housekeeping escapes into an array, and uses a synchronous
`FakeEventQueue` (submitted blocks run inline; posted events are discarded).
No terminal IO happens, so the TTY running the tests is never painted over.

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
      assert_equal ["hi   "], Screen.instance.buffer.region_text(label.rect)
    end
  end
end
```

Key hooks:

- `Screen.instance.buffer` — the back buffer painted content lands in. Assert
  on `buffer.region_text(rect)` / `buffer.region_ansi(rect)` (per-row arrays)
  or `buffer.cell(x, y)` for a single cell's grapheme and style.
- `Screen.instance.prints` — array of cursor/housekeeping escapes and the
  assembled frame string. Assert against it (or `.join`) for cursor behavior,
  not for painted content.
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

