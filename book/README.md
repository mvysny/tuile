# The Tuile guide

A short, sequential guide to building terminal UIs with Tuile. Each
chapter builds on the vocabulary the previous one established, so
reading order matters — the layout chapter assumes the component tree
from chapter 1, focus assumes the event loop, and so on. Don't jump
into chapter 5 without chapters 1 and 2 first.

If you want the reference instead of the narrative, every public class
and module is documented with YARD headers in the sources. Run
`bundle exec rake yard` for a browsable local site, or — once the gem
is published — see <https://rubydoc.info/gems/tuile>. The division of
labour: this guide teaches concepts and the *why*; the rdoc carries the
precise per-method technical truth. When the guide needs a signature it
links to the rdoc rather than restating it.

## How the guide is shaped

Chapters 1–2 are the **base vocabulary** — the component tree and the
repaint model that every later chapter leans on. Chapter 3 is the heart
of Tuile's design: layout is top-down and absolute, and the chapter
argues *why that is enough* — the "C64" case for hand-placed
coordinates on a character grid — rather than reaching for the
negotiated min/pref/max machinery of desktop and web toolkits.

Chapters 4–6 are the **runtime**: the single-threaded event loop and
how to do background work safely, focus and keyboard dispatch, and
theming (including live OS light/dark flips). Chapters 7–8 close out
**narratively** — a tour of the shipped component toolbox framed around
when and why to reach for each, and how to test a Tuile app end to end.
Those two lean on the rdoc for the exact APIs; the guide keeps to the
walkthroughs and use-cases. Chapter 9 is a **deep dive** on
`Tuile::StyledString`, the text primitive under everything the framework
draws — read it when you start rendering your own styled content.

The book grows organically — a chapter exists when a concept has earned
one, not to fill an outline.

## Chapters

1. **[Your first Tuile app](01-first-app.md).** Install, then a
   hello-world walkthrough. Establishes the base vocabulary the rest of
   the guide leans on: the singleton `Tuile::Screen`, the tree of
   `Tuile::Component`s under `ScreenPane`, and the "build a tree, run
   the loop" shape of every Tuile program.
2. **[How the screen repaints](02-repaint.md).** Why components never
   write to the terminal directly. `invalidate` → the back buffer →
   a minimal diff → one synchronized flush per tick. The "cover your
   own `rect`" contract, and why the whole model is flicker-free
   without damage tracking or clipping.
3. **[Layout: the parent sets the size](03-layout.md).** The heart of
   the design. Top-down, absolute, integer coordinates; a parent
   assigns its children's `rect` and components never negotiate a size.
   The C64 argument for *why simple layouting is enough* on a character
   grid, `Layout::Absolute` and the `rect=` override, `Fraction` for
   sizing a popup against the screen, and resize as a discrete
   recompute. Geometry primitives (`Point` / `Size` / `Rect`) live here.
4. **[The event loop and background work](04-event-loop.md).** The
   single-threaded rule: all UI mutation happens on the loop thread.
   The event queue, marshalling work back from a background thread with
   `submit`, and how terminal resize (`SIGWINCH`) is plumbed through the
   same queue rather than handled off the signal.
5. **[Focus and the keyboard](05-focus.md).** The focus chain and
   `focusable?`, and the three-rung order in which a keystroke is offered
   to the tree — Tab, global shortcuts, then `handle_key` delivered to
   focus and bubbling up its ancestors. Why scope-wide keys (pane jumps, a
   form's default button) belong on an ancestor, and how `keyboard_hint`
   drives the status bar.
6. **[Theming](06-theming.md).** Semantic color tokens read at paint
   time, opt-in component backgrounds that inherit down the tree
   (`bg_color`), light/dark auto-detection at startup and live OS
   appearance flips, pairing variants in a `ThemeDef`, app-specific custom
   tokens, and rebuilding theme-derived content in `on_theme_changed`.
7. **[The component library](07-components.md).** A narrative tour of
   the shipped toolbox — Window, List, the text inputs and views,
   ProgressBar, Popup, and the window conveniences — framed around
   *when and why* you reach for each. Signatures stay in the rdoc.
8. **[Testing a Tuile app](08-testing.md).** The testing approach:
   `FakeScreen`, asserting against the painted buffer, driving
   invalidation, and PTY-based end-to-end tests of runnable scripts.
9. **[Styled text](09-styled-text.md).** A deep dive on
   `Tuile::StyledString`, the span-based "text plus styling" value type
   under everything Tuile draws: why spans instead of a `String` full of
   escape codes, the style-aware algebra (slice/wrap/concat by display
   column), minimal-diff rendering, and the strict-vs-lenient parser.
