# 8. Testing a Tuile app

Every chapter so far has, quietly, also been about this one. When chapter
2 said components *invalidate* rather than paint, and write into a back
*buffer* rather than to the terminal — that was a testing decision as much
as a rendering one. When chapter 4 insisted everything runs on one thread
through a queue you could swap out — same. A Tuile app is testable without
a terminal not because someone bolted on a test mode, but because the
framework never actually needed the terminal. It needed a `Screen`, a
buffer, and an event queue, and each of those has an in-memory double that
behaves like the real thing minus the I/O.

So this chapter is the payoff. It shows how to exercise a UI in a plain
unit test — instantiate a component, poke it, and read back exactly what
it drew — and, when that isn't enough, how to drive the whole real script
through a pseudo-terminal.

## The fake screen, and why it resets

The singleton `Screen` from chapter 4 is the thing tests replace. Two
class methods bracket every example:

```ruby
before { Screen.fake }
after  { Screen.close }
```

`Screen.fake` installs a {Tuile::FakeScreen} as the process singleton — a
`Screen` subclass with the terminal amputated. It has a fixed 160×50
viewport (so geometry is deterministic, independent of whoever's terminal
runs the suite), it writes nothing to any TTY, and its event queue is the
synchronous {Tuile::FakeEventQueue} (more on that below). You can mutate the
UI directly from your example — and note there is no lock *bypass* doing
that for you: the fake runs no loop, so `running?` is false and chapter 4's
rule falls back to "the thread that created the screen," which is yours. A
spec that mutates the UI from a **spawned** thread therefore raises, exactly
as an app would. It also pins the color scheme to `:dark`, skipping
the OSC 11 probe from chapter 6 — a probe would otherwise write an escape
query to the test runner's terminal and swallow its input.

`Screen.close` matters as much as `fake` does, and the reason is the
singleton itself. Because there is exactly one `Screen` per process
(chapter 4), a screen left standing after one example is the *same* screen
the next example sees — its tree, its focus, its invalidation set, all
leaked forward. `close` tears the singleton down so each example starts
from nothing. Skip the `after` and you get the classic singleton test
smell: passes in isolation, fails in suite, order-dependent. The pair is
not boilerplate you can trim.

One more line of setup earns its place if your app has a theme of its own. A
fresh `Screen.fake` starts from the built-in {Tuile::ThemeDef}, so a
component reading `theme[:my_token]` would `KeyError` in every example.
Rather than assigning `Screen.instance.theme_def` in every `before` block,
point the construction-time default at your definition once, in
`spec_helper`:

```ruby
Tuile::ThemeDef.default = APP_THEME   # every Screen.fake now carries it
```

## Asserting what got painted

Here's where the back buffer earns its keep. Recall from chapter 2 that
components don't emit escape sequences — they write styled cells into
`Screen#buffer`, and only a flush turns that into wire bytes. In a test
that means the buffer *is* the rendered screen, sitting in memory, fully
inspectable, before any diffing or I/O. You assert against it directly.

The rhythm is: build the component, give it a `rect`, repaint, read the
buffer back over that rect.

```ruby
label = Component::Label.new
label.rect = Rect.new(0, 0, 10, 1)
label.text = "hi"
label.repaint

assert_equal ["hi        "], Screen.instance.buffer.region_text(label.rect)
```

{Tuile::Buffer#region_text} returns the plain text of each row in the
rect, one string per row (trailing pad included — the label fills its
width). Its sibling {Tuile::Buffer#region_ansi} returns the same rows *with
their SGR styling* rendered back into ANSI, which is what you assert
against when the test is about *color* — that a focused field painted its
active-background, say, or that a theme flip changed a hint's hue. And
{Tuile::Buffer#cell} gives you a single cell's grapheme and style for a
pinpoint check. Everything is scoped to a `rect`, so you assert about a
component's own region without caring what surrounds it.

What you do *not* assert content against is `prints`. On a FakeScreen,
`prints` captures only what actually went "to the wire" — cursor
positioning, housekeeping escapes, and the assembled frame string. Content
lives in the buffer; cursor behavior lives in `prints`. Keeping the two
apart is deliberate, and mixing them up is the most common way a first
Tuile test goes wrong.

## Finding the component to drive

Asserting on the buffer needs a `rect`; driving a component needs the
component itself. For a two-line test you have it already — you just built
it. The awkward case is the one that shows up as soon as an app grows: the
widget you want to poke is four levels down inside something a *builder
method* assembled, and the test never held a reference to it.

{Tuile::Testing} is the answer. `Testing.get` walks the tree and returns the
one component matching a spec:

```ruby
Testing.get(Component::Button, caption: "Save").handle_key(Keys::ENTER)
Testing.get(id: :amount).value = 42
```

The spec is a class, an `id`, a caption, a block, or any combination of
them — never a path through the hierarchy, which would break every time you
nested one more layout. The class slot also takes a *mixin*, which is where
the `Has*` family from chapter 7 pays off a second time:
`Testing.find(Component::HasBadInput)` finds every field in the tree whose
parse can fail, whatever their classes.

The `id` in that second line is a plain `Symbol` tag you set on any
component, purely so a test can ask for it back:

```ruby
amount = Component::IntegerField.new
amount.id = :amount           # nothing paints this, and nothing reads it
```

`get` is strict on purpose: it raises unless *exactly one* component
matches. That is the whole feature. The obvious thing to write by hand is a
walk that takes the first match —

```ruby
combo = nil
window.on_tree { |c| combo ||= c if c.is_a?(Component::ComboBox) }
```

— and the day the pane grows a second `ComboBox`, that silently re-points
your test at a different widget. Nothing fails; the assertions just start
describing something else. `get` calls that ambiguity what it is, and the
failure comes with a dump of the tree it searched:

```
expected 1 Component::ComboBox, found 2
searched:
  #<ScreenPane rect=(0,0 160x50)>
    #<Window rect=(0,0 40x10) caption="Settings">
→     #<ComboBox rect=(1,1 38x1) value=nil>
→     #<ComboBox rect=(1,2 38x1) value="dark">
```

Which usually tells you the fix immediately: narrow the search. Every
lookup takes `in:` to scope it to a subtree, and by default searches the
whole screen — popups included, since chapter 1's pane holds them under the
same root as the content.

```ruby
Testing.get(Component::ComboBox, in: sampler.demo_window)
```

Its sibling `Testing.find` returns *all* matches as an array, and takes an
optional `count:` — an Integer for exactly, a Range for a bound — so an
assertion about how many of something exists is one call:

```ruby
Testing.find(Component::Checkbox, in: form, count: 3)   # raises unless 3
```

Two habits worth forming. Call these qualified, as `Testing.get(...)`:
`find` and `get` are the most collision-prone names in a spec suite, so
Tuile deliberately neither installs them on `Component` nor asks you to mix
the module in. And remember this is *additive* — it makes driving a tree
terser, and changes nothing about the assertion channel. What a component
*shows* is still asserted on the buffer.

## Driving the system

There are two altitudes at which you feed input, and picking the right one
is most of writing a good Tuile test.

**Low: call the component directly.** {Tuile::Component#handle_key} and
`handle_mouse` are public, and calling them straight tests a component's
own logic in isolation — no focus, no dispatch, just "given this key, does
the list move its cursor?" `handle_key` returns whether it consumed the
key, so you assert on that too:

```ruby
list.handle_key(Keys::DOWN_ARROW)          # exercises the cursor directly
```

**A mouse test needs the component mounted, where a key test doesn't.** A
click doesn't only *do* something, it also *focuses* — and
{Tuile::Screen#focused=} refuses a component that isn't on the pane, so
`handle_mouse` on a component you never attached raises "is not attached to
this screen". Give it a tree first:

```ruby
screen.content = list                      # a click focuses; focus needs a tree
list.rect = Rect.new(0, 0, 10, 5)
list.handle_mouse(MouseEvent.new(:left, 5, 2))
```

That applies to containers too, and to more of them than you might expect:
a click descends to every child whose rect contains the point, so testing a
window's footer by clicking it exercises the window, the footer's slot and
the footer, all of which want to be attached.

**High: go through the pane.** {Tuile::ScreenPane#handle_key} runs the
dispatch rung from chapter 5 that routing is actually about: delivery to
{Tuile::Screen#focused}, then the bubble up its ancestor chain to the scope
root. So when your test is about routing — that a layout's one-key pane jump
fires, that a focused text field swallows a key its ancestor would otherwise
claim, that an open modal keeps the content beneath it from seeing keys — you
drive the pane and let the real machinery run:

```ruby
screen.focused = list                # focus as production does — or list.focus
assert screen.pane.handle_key("1")   # the layout's ancestor binding fires
```

The two rungs *above* the pane have their own doors, because `Screen`'s own
`handle_key` — the top of the ladder — is private: it belongs to the key
thread, not to app code. Tab cycling is {Tuile::Screen#focus_next} /
`focus_previous`, both already scoped to the topmost modal popup, which is
what "a popup traps Tab" means. A global shortcut is a block you registered,
so test the action it calls; the registry itself is a lookup table `Screen`
consults before handing the key to the pane, and `register_global_shortcut`
is worth a test only for what it *rejects* (printables, Tab, `EDITING_KEYS`).

Two more test-only hooks close the loop. After you mutate something, call
`Screen.instance.repaint` to flush the pending invalidations into the
buffer — the coalesced repaint that chapter 2 said happens once per tick,
triggered by hand because there's no loop running to trigger it. (This is
a *test* affordance; production code never calls `repaint`, it just
invalidates and lets the loop coalesce.) And to check invalidation itself
— that a setter did, or deliberately didn't, mark its component dirty —
`Screen.instance.invalidated?(component)` and `invalidated_clear` let you
assert on the set directly.

## Why background code just works

Chapter 4's rule was that background threads marshal UI work back with
`screen.event_queue.submit { … }`. That rule has a happy consequence for
tests: under the {Tuile::FakeEventQueue}, `submit` **runs its block
synchronously, right now, on the calling thread.** There is no loop, no
thread, no waiting. So code that in production hands work across the
thread boundary — a `LogWindow#log`, a worker posting a result — executes
inline the moment the test calls it, and the effect is visible on the very
next line. Posted *events* are simply discarded (a test isn't running the
loop that would consume them), and `check_locked` passing for free means
none of this trips the lock guard.

The one thing with no clock is animation. `tick` on the fake returns a
timeless ticker that fires only when the test tells it to: call
`event_queue.tick_once` to pump every registered ticker one frame. A test
that wants to advance an animation five frames calls `tick_once` five
times — frame cadence is the test's to decide, since there's no real time
passing.

## End to end, through a real terminal

Unit tests with the fake cover component logic and rendering, which is
most of what you write. But some things only exist when the *real* app
runs: the event loop actually looping, raw-mode key decoding, the WINCH
trap, a live color-scheme flip. For those, Tuile's own suite spawns the
real example script in a pseudo-terminal and talks to it like a user
would. The `spec/examples/` tests are the template.

The shape is always the same. Spawn the script under `PTY.spawn`; read its
output until a glyph you know it paints appears — that single wait proves a
lot at once (the tree built, a repaint ran, and the loop is now parked in
the key wait); write a keystroke; assert the process exits cleanly.

```ruby
PTY.spawn("bundle", "exec", "ruby", "-Ilib", "examples/hello_world.rb") do |reader, writer, pid|
  buffer = String.new
  Timeout.timeout(10) do
    buffer << reader.readpartial(4096) until buffer.include?("Hello, world!")
  end
  writer.write("q")
  Timeout.timeout(5) { Process.wait(pid) }
  assert_equal 0, $CHILD_STATUS.exitstatus
end
```

This is the only place the whole stack is exercised together, and it's
where you'd test something like the mode-2031 flip from chapter 6:
wait for the dark-theme hint to paint, write the terminal's
`\e[?997;2n` light report into the PTY, then wait for the *light* hint —
which passes only if the entire chain (key-thread drain, event parse,
theme reassignment, full repaint) actually ran end to end. The cost is
that PTY tests are slower, terminal-dependent, and Linux/macOS only
(Ruby's stdlib `PTY` isn't on Windows), so they stay a thin top layer over
a broad base of fake-screen unit tests — the classic pyramid.

---

That closes the book. You've followed Tuile from the outside in and back
out: a tree of components (chapter 1) that repaint through a back buffer
without flicker (chapter 2), sized top-down by their parents (chapter 3),
driven by a single-threaded event loop (chapter 4), with keys routed by
focus (chapter 5) and accents drawn from a terminal-following theme
(chapter 6); then the library you assemble from (chapter 7), and finally
the fakes that let you test all of it with no terminal in sight (this
one). The recurring lesson is the one the name promises: small pieces, each
doing an obvious thing, composed. The framework is small because the ideas
are few — and now they're all yours to build on.
