# 1. Your first Tuile app

This chapter builds the smallest useful Tuile program — a bordered window
that says hello — and uses it to name the handful of ideas the rest of
the guide leans on. There's almost no depth here on purpose: the goal is
the *shape* of a Tuile program and the mental model, not the details.
Every concept named in passing gets its own chapter later.

## Install

Tuile is a gem; it needs Ruby 3.3 or newer. Add it to a project with
`bundle add tuile`, or install it standalone with `gem install tuile`,
and `require "tuile"` at the top of your script. That's the whole
prerequisite — Tuile builds on the `tty-*` toolkit but pulls in what it
needs itself, and it talks to the terminal you already have.

## The whole program

Here is a complete Tuile app. It draws a framed window containing the
text "Hello, world!" and waits; pressing `q` or `Esc` exits.

```ruby
require "tuile"

# The Screen must exist before you wire components together: attaching a
# component (content=, focus, …) reaches for Tuile::Screen.instance.
screen = Tuile::Screen.new

label = Tuile::Component::Label.new("Hello, world!")

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

That's it — no configuration, no layout file, no main loop you write by
hand. The rest of this chapter walks the seven lines that matter and
names what each one introduces.

## Build the screen first

```ruby
screen = Tuile::Screen.new
```

{Tuile::Screen} is the runtime: it owns the terminal, the event loop, and
the one back buffer everything paints into. It is a **process
singleton** — there is exactly one screen per app, and `Screen.new`
installs it as *the* instance. After this line, any component can find it
with `Tuile::Screen.instance` (which is how the base {Tuile::Component}
implements its `screen` accessor).

Order matters: construct the screen *before* you start wiring components
together. Building a bare component (`Label.new`) touches nothing, but
the moment you attach one to the tree — `window.content = label`,
`window.focus` — that component reaches for `Screen.instance` to register
itself. No screen yet, and you get a "Screen not initialized" error. In
practice the rule is simply: `Screen.new` is the first line.

## Build a tree of components

```ruby
label = Tuile::Component::Label.new("Hello, world!")

window = Tuile::Component::Window.new("Tuile")
window.content = label
```

Everything you see on screen is a {Tuile::Component}: a piece of UI that
occupies a rectangle and knows how to paint itself into it. Components
nest into a **tree** — a component has a `parent` and `children` — and
that tree *is* your UI.

Here the tree is two nodes deep. A {Tuile::Component::Label} is a passive
one-liner of text, given straight to the constructor (or assigned later
with `label.text =`). A {Tuile::Component::Window} is a bordered frame
with a caption (`"Tuile"`, which you'll see drawn into the top edge) and a
single content slot. `window.content = label` puts the label inside the
window's frame and makes the window its parent. Assigning content is also
what *attaches* the label to the live tree, so from this point the label
is a real, paintable thing.

Notice you never say where anything goes or how big it is. You didn't
give the label a position or the window a size. **A component's parent
decides its rectangle** — the window will size the label to fit inside
its border, and something will size the window to fill the terminal.
That "something" is the next line, and the top-down layout rule behind it
is the whole of chapter 3.

## Put it on screen, and focus it

```ruby
screen.content = window
window.focus
```

`screen.content = window` makes the window the screen's **tiled content**
— the component that fills the terminal. Setting it triggers a layout
pass: the window is handed a rectangle spanning the whole screen (minus
one bottom row, which we'll get to), and it in turn sizes the label
inside its border. This is the top-down cascade in miniature — the screen
sizes the window, the window sizes its content — and it re-runs, top
down, every time the terminal is resized.

`window.focus` marks the window as the **focused** component: the one
that receives keystrokes. Focus flows down toward interactive content
where it can, so focusing the window is the natural way to say "this is
the active thing." In a one-window app it's mostly cosmetic (it draws the
border in the active color); in a real app, focus is what routes the
keyboard, and it gets its own chapter (chapter 5).

You may have noticed you never created a status bar, yet the app has one
— the bottom row showing `q quit`. That's because your window isn't the
whole story of what's on screen.

## The tree you didn't build

Your `window` isn't actually the root of the tree. The real root is a
structural node called the {Tuile::ScreenPane}, owned by the screen, and
it holds three things:

```
ScreenPane                (structural root — paints nothing itself)
├── content               your window (the tiled UI)
├── popups                modal overlays, when you open them (none yet)
└── status_bar            the bottom row (that "q quit" hint)
```

You only ever manage the `content` slot directly (via `screen.content=`);
the pane, the popup stack, and the status bar are the framework's. The
reason everything — including popups — lives under one parent is
uniformity: focus traversal, "is this component still on screen?", and
cleanup when a component is removed all work the same way for every node,
with no special cases. You'll meet popups in chapter 7; for now it's
enough to know the pane is up there, quietly being the root.

## Run the loop, and always close

```ruby
begin
  screen.run_event_loop
ensure
  screen.close
end
```

{Tuile::Screen#run_event_loop} is where your program *lives*. It puts the
terminal into raw mode, then loops: read a key (or a mouse event, or a
resize), dispatch it into the component tree, and — once the dust settles
— repaint whatever changed. It's a single thread doing one thing at a
time, and that single-threadedness is a deliberate, load-bearing design
choice (chapter 4). The loop returns when the user presses `q` or `Esc`
without any component consuming the key first.

The `ensure` is not optional. `run_event_loop` reconfigured your
terminal — raw mode, a hidden cursor, mouse tracking — and
{Tuile::Screen#close} is what puts it all back. Skip it and a crash leaves
the user staring at a terminal that no longer echoes what they type. Wrap
the loop in `begin`/`ensure` so teardown happens no matter how you exit.

## The shape of every Tuile program

Strip away the specifics and every Tuile app is the same four beats:

1. **Make the screen** — `Screen.new`, first, so components can find it.
2. **Build a tree** of components and hand its root to `screen.content=`.
3. **Run the loop** — `run_event_loop` reads input, updates the tree, and
   repaints.
4. **Close** in an `ensure`, always.

That's the whole skeleton. Everything else in this guide is about the
second and third beats: how to build richer trees (the component library,
chapter 7), how the tree gets sized (layout, chapter 3), how it repaints
without flicker (chapter 2), and how input and background work move
through the loop (chapters 4 and 5).

Next up: chapter 2, on what actually happens between "a component changed"
and "the terminal shows it" — the repaint model.
