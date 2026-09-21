# How other toolkits trigger a layout pass

Sourcing for `design/ideas/relayout.md`'s `Q_defer`. Provenance markers are
`design/research.md`'s — **[docs]** (the project's own documentation, quoted),
**[src]**, **[unverified]** — so the survivors can graduate into an `R_` entry
with no re-checking. Everything below was read on **2026-09-21**; where a quote
appears, it is verbatim from the cited page.

## The answer, in one table

| Toolkit | Mode | Mark | Pass runs | Force-now escape |
|---|---|---|---|---|
| Terminal.Gui v2 (C#, TUI) | retained | `SetNeedsLayout()` | MainLoop iteration, before Draw | — (not checked) |
| Textual (Python, TUI) | retained | `refresh(layout=True)` | next idle event, coalesced | — (not checked) |
| Cursive (Rust, TUI) | retained, **two-pass** | — | `required_size()` then `layout()` per draw | n/a |
| ratatui / FTXUI / egui | **immediate** | n/a | every frame, from scratch | n/a |
| Swing (Java) | retained | `revalidate()` | after pending events are dispatched | `validate()` |
| Tk | retained | implicit on geometry change | idle tasks | `update idletasks` |
| UIKit | retained | `setNeedsLayout()` | next run-loop update cycle | `layoutIfNeeded()` |
| Android | retained | `requestLayout()` | next frame traversal (Choreographer/vsync) | — |
| Flutter | retained | `markNeedsLayout()` | `PipelineOwner.flushLayout` in the frame pipeline | — |
| DOM / browsers | retained | style mutation | frame time ("reflow") | implicit: read `offsetWidth` |
| **Tuile today** | retained | — | **synchronously, inside the mutator** | n/a |

## The quotes

**Terminal.Gui v2** — the closest peer: a retained-tree TUI in a managed
language, with the same back-buffer-and-flush model Tuile has. **[docs]**

> Each iteration of the Application MainLoop performs these steps: 1. **Layout** —
> Views that need layout are measured and positioned (`LayoutSubviews()` is
> called) 2. **Draw** — Views that need drawing update the driver's back buffer
> (`Draw()` is called) 3. **Write** — The driver writes changed portions of the
> back buffer to the actual terminal 4. **Cursor** …

> Drawing occurs during Application MainLoop iterations, not immediately when
> draw-related methods are called.

> These methods do not cause immediate drawing. They mark the view for redraw in
> the next MainLoop iteration.

Source: <https://raw.githubusercontent.com/gui-cs/Terminal.Gui/v2_develop/docfx/docs/drawing.md>

**Textual** — the other retained TUI, and the tightest statement of coalescing
anywhere in this survey. On `Widget.refresh(layout=True)`: **[docs]**

> This method sets an internal flag to perform a refresh, which will be done on
> the next idle event. Only one refresh will be done even if this method is
> called multiple times.

Source: <https://textual.textualize.io/api/widget/>

**Cursive** — the TUI that took the channel `D_declared_size` refuses, and pays
for it with a cache. **[docs]**

> `required_size()` returns the minimum size the view requires with the given
> restrictions, and is the main way a view communicates its size to its parent.

> The layout phase is when the size and location of each view is computed. … In
> order to determine how much space should be given each child, parents can use
> `View::required_size()` on them.

Note the consequence, in their own words: "if they call `required_size` or
`layout` with stable parameters, the children may cache the result themselves and
speed up the process anyway", plus a built-in one-dimensional layout cache. The
measurement channel is what makes the cache necessary.
Source: <https://docs.rs/cursive/latest/cursive/view/trait.View.html>

**Swing** — `revalidate()`'s javadoc opens with the sentence that names the whole
category. **[docs]**

> Supports deferred automatic layout.

The mechanism: `revalidate()` calls `invalidate` and adds the component's
validate-root to a list; `RepaintManager.addInvalidComponent` "marks the
component as in need of layout and queues a runnable for the event dispatching
thread"; `validateInvalidComponents()` drains it. `validate()` is the synchronous
sibling that survives from AWT.
Sources: <https://docs.oracle.com/javase/8/docs/api/javax/swing/JComponent.html>,
<https://docs.oracle.com/en/java/javase/11/docs/api/java.desktop/javax/swing/RepaintManager.html>
(the `addInvalidComponent` / `validateInvalidComponents` wording is from search
result summaries of these pages, not fetched verbatim — **[unverified]** at the
sentence level, certain at the mechanism level).

**Flutter** — the most explicit model, and the one `content-height.md` already
reasons about. **[docs]**

> `markNeedsLayout` … register[s] this object with its `PipelineOwner`, or
> defer[s] to the parent, depending on whether this object is a relayout boundary
> or not respectively.

A node is a relayout boundary when `sizedByParent` is true ("the constraints are
the only input to the sizing algorithm, in particular child nodes have no
impact") or when the parent passed `parentUsesSize: false`. The dirty list is
drained by `PipelineOwner.flushLayout` during the frame.
Source: <https://api.flutter.dev/flutter/rendering/RenderObject-class.html>

**Android** — `requestLayout()` sets `PFLAG_FORCE_LAYOUT` and climbs to
`ViewRootImpl`, which posts a traversal via
`Choreographer.postCallback(CALLBACK_TRAVERSAL, …)`; the traversal runs on vsync
and does measure, then layout, then draw. Search-summary level, consistent across
several sources. **[unverified]**
Source: <https://developer.android.com/guide/topics/ui/how-android-draws>

**Tk** — the oldest of these, and the one whose *failure mode* is best
documented. Geometry is recomputed at idle time; before that pass runs,
`winfo_width()` reports the placeholder `1`, and `update_idletasks` is the
documented way to "force pending geometry calculations before taking immediate
measurements". Search-summary level. **[unverified]**
Sources: <https://wiki.tcl-lang.org/page/update+idletasks>,
<https://tkdocs.com/tutorial/grid.html>

**The DOM** — batched reflow at frame time, with an implicit forced flush on any
geometric read. **[docs]**

> the browser must *first* apply the style change … and *then* run layout

> You should always batch your style reads and do them first (where the browser
> can use the previous frame's layout values) and then do any writes.

The industry name for getting this wrong is **layout thrashing** / *forced
synchronous layout*.
Source: <https://web.dev/articles/avoid-large-complex-layouts-and-layout-thrashing>

**ratatui** (and FTXUI, egui) — the contrast case, not a competitor: no retained
widget tree at all, layout recomputed from scratch inside each frame's render
call. In their words, the crate "does not introduce a retained widget tree and
does not make containers store child widgets". This is precisely the shape
Tuile's promise — *a retained tree, not a redraw loop* — rules out, so it
carries no vote on `Q_defer`. **[docs]**
Source: <https://ratatui.rs/concepts/rendering/>

## Checks not done

- Whether Terminal.Gui **v1** laid out synchronously and v2 moved it into the
  MainLoop deliberately. If so it is the single most relevant data point in the
  survey — a TUI that ran road A and migrated to road B in a major version — and
  the migration notes would say why. The v2 docs describe the current model only;
  `migratingfromv1.md` and discussion #2448 are the places to look.
- Whether any retained-mode toolkit lays out **synchronously inside the
  mutator**, as Tuile does today. Nothing surveyed does. Absence of evidence
  here is weak evidence of absence — but it was looked for.
- Qt (`QEvent::LayoutRequest`, `QLayout::activate`), GTK4
  (`gtk_widget_queue_allocate`), JavaFX (`requestLayout` + the pulse) and
  Jetpack Compose were not checked. All are believed deferred; none would change
  the tally, and three confirmations of the same shape are enough.
