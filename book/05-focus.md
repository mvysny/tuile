# 5. Focus and the keyboard

Chapter 4 ended on a promise: because everything runs on one thread, this
chapter can describe keyboard handling without a single caveat about
concurrency. When a key is dispatched, nothing else is happening — no
repaint mid-flight, no background thread mutating the tree. So the only
question left is the interesting one: given a keystroke and a tree of
components, *who gets it?*

The answer has two halves. **Focus** decides which component is the
current target. **Dispatch** decides the order in which components are
offered a key — because focus is the common case, not the only case.

## The focus chain

At any moment, at most one component is **focused**. You set it directly:

```ruby
screen.focused = some_component     # or: some_component.focus
screen.focused = nil                # nothing focused
```

Focus is not just a flag on one component, though — it's a *chain*.
Setting focus walks from the target up through its parents to the root,
and marks every component on that path **active**. Everything not on the
path is deactivated. So if you focus a text field inside a window inside
the content area, the field, the window, and the content are all active;
their siblings are not.

That active chain is what components paint against. A {Tuile::Component::Window}
draws its border in the accent color when it's active and a plain color
when it isn't — which is why, in a multi-window layout, exactly the
window containing the focused widget lights up. "Active" means "on the
path to what has focus," and it falls out of one assignment.

## Two gates: `focusable?` and `tab_stop?`

Not everything can be focused, and not everything focusable participates
in every way of *getting* focused. Two predicates draw those lines, and
they're independent on purpose.

{Tuile::Component#focusable?} gates whether a component can become a focus
target *at all*. It's `false` by default — a {Tuile::Component::Label} is
decoration; clicking one shouldn't yank focus away from the window around
it. Controls that accept input (a text field, a list, a button) override
it to `true`. This gate is what makes click-to-focus sane: clicking lands
focus on the component under the cursor *only if it's focusable*,
otherwise the click is ignored for focus purposes. The same rule governs
the automatic focus-forwarding a container does when it's focused — a
window handed focus passes it down to its content, but only if that
content is focusable.

{Tuile::Component#tab_stop?} gates something narrower: whether Tab and
Shift+Tab land on this component while cycling. It's also `false` by
default, and it *implies* focusable — a tab stop is always a valid focus
target, but not every focus target is a tab stop. The distinction matters
for containers: a {Tuile::Component::Window} is focusable (so a click on
its chrome can focus it) but is *not* a tab stop (Tab should skip the frame
and stop on the actual inputs inside it). So:

- **Label** — neither. Decoration.
- **Window, Popup** — focusable, not a tab stop. Clickable chrome,
  skipped by Tab.
- **TextField, List, Button** — both. Real inputs you can click *and*
  Tab to.

Tab cycling is confined to a **modal scope**: the topmost modal popup if
one is open, otherwise the tiled content. Tab collects the tab stops in
that scope in tree order and advances by one, wrapping around; Shift+Tab
walks backward. This is what keeps Tab from escaping an open dialog — the
scope is the dialog, so cycling stays inside it.

## The dispatch order

When a key arrives, it's offered to the tree in a fixed order, and the
first handler to claim it wins. Understanding this order is the whole
game, because a key you expected one component to get can be intercepted
earlier.

**1. Tab and Shift+Tab — focus navigation, first, always.** These are
intercepted before anything else and drive the cycling described above.
They're taken off the top deliberately: a focused text field swallows
almost every printable key, and if Tab weren't reserved here, a field would
trap it too and you could never Tab out.

**2. Global shortcuts.** App-level shortcuts registered with
{Tuile::Screen#register_global_shortcut} fire next, before any component
sees the key. These are for app-wide actions — "Ctrl+L opens the log,"
"F1 shows help" — that should work regardless of what's focused:

```ruby
screen.register_global_shortcut(Tuile::Keys::CTRL_L,
                                hint: "^L #{screen.theme.hint("log")}") do
  log_popup.open
end
```

This registry is the only keyboard mechanism that sits *above* the
component tree, and nothing suppresses it — which is exactly why it's
picky about what it accepts. Printable keys are rejected at registration
time, because a global binding on `a` would hijack someone typing `a` into
a text field. So are Tab and Shift+Tab (step 1 already took them), and so
are `Screen::EDITING_KEYS` — Enter, Backspace, Delete and the arrows —
because every editable widget needs those, and a global binding would
break text entry app-wide with no way for a field to defend itself. What's
left is yours: control keys, ESC, PgUp/PgDn, function keys. A shortcut can
opt to fire even while a modal popup is open (`over_popups: true`); by
default it's suppressed while a popup is up, so the popup stays modal.

**3. `handle_key`, delivered to focus and bubbling up.** Everything else
goes to the focused component's {Tuile::Component#handle_key}, and if that
returns `false` (didn't handle it), the key bubbles up the ancestor chain —
the focused component, then its parent, then *its* parent — until someone
returns `true` or the scope root is reached. This is how a list handles
arrow keys itself but lets an unhandled key rise to the window around it.

A component only ever receives a key when it's on the focus chain, so
`handle_key` implementations act on the key alone — they never need to
check their own `active?` state. And if focus is `nil`, or sits outside
the current modal scope, delivery reaches no one: that's precisely what
makes an open modal popup modal.

Three rungs, and that's the whole ladder. Tuile used to have a fourth — a
scan of the scope for a component carrying a matching "shortcut key,"
which would jump focus to it. It's gone; the next section explains why the
bubble does that job better.

## Scope-wide keys live on an ancestor

Two things every app wants: `1`/`2`/`3` to jump between panes, and Enter to
submit a form. Neither is a *global* action — each belongs to one region of
the tree — and neither needs machinery, because bubbling already has the
right shape. **Put the key on the ancestor that owns the region.**

```ruby
class AppLayout < Tuile::Component::Layout::Absolute
  def handle_key(key)
    case key
    when "1" then @files.focus; true
    when "2" then @log.focus; true
    else false
    end
  end
end
```

Now think about what happens when the user clicks into a search field
inside `@files` and types "add item". Should the `1` in a typed "item 1"
jump panes? Obviously not — and it doesn't, for a reason that requires no
special case at all: **the focused field consumes the key at step 3 and
returns `true`, so the layout never sees it.** An ancestor only hears the
keys its descendants declined. That's the whole protection.

The same mechanism gives you a form's default button, one form per popup:

| focused widget | Enter | outcome |
|---|---|---|
| `TextArea` | consumes it (newline) | the form never sees it |
| `TextField` with an `on_enter` | consumes it | no double-submit |
| `TextField` without one | declines | bubbles up → submit |
| `Button` | consumes it | activates *itself*, not the default |

Because bubbling stops at the scope root, two forms in two popups each get
their own Enter — something a global registry structurally cannot do. This
is also why registering Enter globally is refused in step 2: the registry
would take it away from all of them at once.

The one thing this shape asks of you is that the *parent* holds the key →
child table, rather than each widget declaring its own mnemonic. That's a
fair trade: which key jumps where is a decision about the assembly, and it
reads well in one place.

## Where the cursor comes in — and where it doesn't

A component signals cursor ownership through
{Tuile::Component#cursor_position} — return a `Point` and the terminal
cursor is shown there; return `nil` (the default) and there's no cursor. A
{Tuile::Component::TextField} being edited returns its caret position, so
the caret you see blinking is the focused component's answer to that one
question.

That's all it does. It positions the hardware cursor; it does not route
keys. Tuile briefly used it as a proxy for "this widget is in text-entry
mode, don't steal its printable keys" — a signal the deleted fourth rung
needed. With dispatch resting on nothing but "did you return `true`," the
proxy is gone, and a component's decision to consume a key is the only
declaration in the system.

## The status bar writes itself

You've seen the bottom row showing hints like `q quit` since chapter 1.
It's driven by focus. Whenever focus changes, the screen rebuilds the
status bar from two sources: the currently-relevant shortcuts, and the
focused context's own advertised hint.

A component advertises its hint by overriding
{Tuile::Component#keyboard_hint} to return a preformatted string
(components build these with `theme.hint(...)` so the styling matches).
The screen composes the bar differently depending on what's in front:

- **Tiled (no popup):** `q quit`, then any global-shortcut hints, then the
  active window's `keyboard_hint`.
- **Popup open:** the over-popups global hints, then the popup's own hint
  (a popup owns its `q Close` prefix).

You don't assemble the bar yourself; you override `keyboard_hint` on the
components that have shortcuts worth advertising, register global
shortcuts with a `hint:`, and the composition happens on every focus
change. The status bar is a *view* of the focus state, not a thing you
maintain.

---

Focus and dispatch are the last piece of the runtime. You now have the
whole loop: build a tree (chapter 1), it repaints without flicker
(chapter 2), sized top-down (chapter 3), driven by a single-threaded
event loop (chapter 4), with keys routed through focus (this chapter).
Chapter 6 adds the last cross-cutting concern — color — and then chapters
7 and 8 turn from *how the framework works* to *what you build with it*.
