# Hover — the stranded-hover repair, the ink, and a demo

**Status:** the plumbing landed 2026-09-17 with `D_mouse_dispatch`, and the demo with it; what is
left here is small and none of it is on the critical path. Originally filed 2026-09-03 as three
steps — plumbing, notices, ink. Steps 1 and 2 are done bar one repair; **step 3, the ink, is
untouched by design and was always meant to be decided last**, because steps 1–2 are useful on
their own and a framework accent can be added later but not removed.

The terminal findings graduated to `R_mouse_reporting`; the dispatch design graduated to
`D_mouse_dispatch`. Read those two before this note — the rest is detail hanging off them.

## What landed, so it is not re-litigated

`D_mouse_dispatch` shipped the event classes under {Tuile::Mouse}, the {Tuile::Mouse::Router},
the `capture_mouse: :clicks / :drag / :hover` ladder, X10 motion parsing, and the hover half:
enter/exit on the symmetric difference of the two hovered chains (exit innermost-first, enter
root-first), `handle_mouse_move?` bubbling with consumption, `extent_rect` hit-testing, popups
resolved topmost, and {Tuile::Screen#hovered}. The router syncs the hovered chain from the
invariant on every repaint, so detach and hide already fire their exits.

Settled along the way and recorded elsewhere: activation on the press with no click synthesis, and
`UpEvent` carrying no button (`D_mouse_dispatch`); the opt-in ladder being all-or-nothing at
`run_event_loop` rather than scoped tracking, which stays a later optimization if the measured
~84 reports/s ever bites (`R_mouse_reporting`); and exit never becoming a commit point
(AGENTS.md, *Focus, keys and paste*).

**Not hover-shaped, and landed separately 2026-09-18:** SGR 1006 is requested alongside every rung,
`Mouse.parse` reads both encodings and `Keys.getkey` drains `\e[<` a byte at a time, so a click past
column 223 works (`R_mouse_reporting`, AGENTS.md *Focus, keys and paste*).

## The invariant that governs every consumer

> **A hover feature is a second route to an affordance that already exists. Never the only route.**

Which is AGENTS.md's *the mouse is additive* (`D_mouse`) sharpened for a channel the app may not
even have enabled. It is the acceptance test for every proposal below, and `MenuBar` passes it in
both its sub-cases: with motion off you **click** the sibling menu instead of hovering it, and the
**arrows** move the item cursor. A disclosure reachable *only* by hovering is rejected on this
ground alone — it would make a mode-off app strictly less capable rather than merely less smooth.

## Step 2's remainder — clearing a stranded hover

Mode 1003 reports motion *inside* the terminal; a pointer that leaves the window sends nothing, so
the last-hovered component stays hovered and anything it painted strands (`R_mouse_reporting`).
The router's `sync_hover` already covers detach and hide. **Mode 1004 covers the rest, and it was
measured working**: it fires on a genuine pointer exit *and* on an alt-tab with the pointer still
inside the window, and both should clear hover — with the app unfocused, painting an accent for a
pointer the user is not driving is simply wrong.

> **Clear hover on FocusOut. On FocusIn, keep it cleared until the next `MoveEvent`** — the pointer
> may be anywhere, and we do not know where until it moves.

Plus a cheap belt: **any keystroke clears hover**. Both feed `sync_hover`'s single idempotent pass
over the invariant rather than becoming further mutation sites, per AGENTS.md's hook-owned-resource
rule — the router already learned that lesson once.

**Rejected: infer the exit from an edge cell.** Tempting, because a real pointer-exit's last report
*was* at an edge. Two reasons not to. **Edge cells are legitimate, common hover targets** — column 0
is where a scrollbar, a sidebar's first column and a `MenuBar`'s first item live, so "last motion at
an edge, then quiet" is indistinguishable from a pointer resting on exactly the widget you most want
hovered, and the heuristic would flicker the accent off under a *stationary* pointer. And **a fast
exit may emit no edge report at all**: sampling is ~84 Hz, so a quick flick out of the window can
have its last report several cells short of the boundary.

The residual gap after 1004 is narrow — the pointer wanders off while the terminal keeps *keyboard*
focus, which means a click-to-focus window manager and a user who touches no key. What is visible
then is an accent sitting lit on a component the pointer is not over: cosmetic, and the
never-load-bearing rule absorbs it.

## Step 3 — the ink

- **(A) No framework accent; the app paints.** With the plumbing in, this is not abandonment — it
  is the non-focusable click target working, with the app's own `repaint` reading hover state. Zero
  new ink, no `BG_STATES` change, no focused-vs-hovered precedence rule, and it stays reversible.
  **The recommended landing point.**
- **(B) `MenuBar` only** — the one with real behavior behind it rather than ink. See below.
- **(C) Flatly, for every component.** Needs `BG_STATES` to grow `:hover` (admissible in principle —
  AGENTS.md says a key is added "when Tuile grows the *state*"), *plus* a focused-and-hovered
  precedence ruling a two-state map never had to answer, *plus* an answer to `focus-accent.md`'s
  finding that three of the five accenting widgets highlight a **segment or row**, not the
  component. That last one is fatal on its own: the interesting hover targets *are* the segment/row
  cases.

`focus-accent.md` measured migrating those five widgets onto `default_bg_color`: **+2 lines each,
and inexpressible for `Tabs`, `MenuBar` and `List`.** Hover lands on the same rock, so a framework
accent would have to go via that note's **option (C)** — a paint-time `over_bg` layer applied to a
`StyledString` rather than declared per component. Hover is the second consumer that makes it worth
pricing rather than parking; weigh against `D_theme_ref`'s "not a third colour channel" first. One
thing that is *not* in the way: `List` applies its cursor highlight at paint, not into the memoized
row, and the cache-dropping rule is about *geometry* inputs — so a hover accent needs no
`drop_row_cache`.

### `MenuBar` is the strong case, and it needs no new ink

- **Hover highlight inside an open dropdown = move the `List` cursor.** The cursor already
  highlights, arrows already move it, Enter already activates it. Hover becomes a third way to set a
  position — no second accent, no new token, no ambiguity, and it is what every desktop menu does.
  The cleanest hover feature in the note.
- **Open-on-hover of the strip, *only while a cascade is already open*** — the desktop convention.
  `D_menu_bar` defers this explicitly on "needs mouse motion", which it no longer does.

### The accessibility argument, taken seriously

A highlight that tracks the pointer answers "where am I" continuously for **low-vision and
magnifier users**, and auto-opening a submenu removes a precise click. That is the strongest
*motivation* in this note, and two things follow from taking it seriously rather than citing it:

- **Open-on-hover needs a delay, or it is worse than nothing** — dragging across the strip with no
  delay flash-opens every menu in turn, which for a magnifier user is actively disorienting.
  Desktop menus use ~200–400 ms. `Ticker` is the machinery and `D_progress_bar`'s `sync_ticker` is
  the pattern: the timer is *synced from an invariant* (cascade open && motion enabled && pointer on
  a sibling segment), never toggled by the enter and exit hooks.
- **It argues against a second highlight** — for a low-vision user two similar-but-distinct
  highlights are worse than one, the discrimination being the expensive part. So "hover moves the
  `List` cursor" is not just the cheap implementation, it is the *accessible* one.

But plainly, because it changes the priority: **the bigger accessibility lever is not hover at
all.** `D_menu_bar` records that with no Alt and no function keys the only way to *reach* the bar is
Tab. A user who cannot use a mouse gains far more from `Alt+F` than any pointer user gains from
hover.

## The demo — landed as the sampler's *Mouse* pane

Shipped 2026-09-17 as `SamplerExample::Canvas` plus `build_mouse_demo`, not as the separate
`examples/hover.rb` this note had planned. It reversed two things:

- **It lives in the sampler**, which takes the whole app to `capture_mouse: :hover`. The rung is one
  choice at `run_event_loop`, so a pane needing `:hover` cannot have it alone. The cost is the ~84
  reports/s, *not* select-to-copy — mode 1000 had already taken that — and the PTY walk sends no
  mouse, so its profile never mattered. The alternative was a third example file nobody opens.
- **Two inks, neither erasing**: a drag strokes `X`, a plain hover trails `.`, and a right-drag
  lifts. A hover that *cleared* — the first sketch — makes the drawing unviewable with the pointer
  over it. The enter/exit pair shows up in the log rather than as a background flip, which is what
  keeps the pane from prejudging step 3 below.

Kept from the plan: the discrete events go to a log ({Component::LogWindow}, never a `List` —
`D_list_items`), while the ~84-a-second moves go to one replaced row. The rest of the reasoning is
in `Canvas`'s rdoc and in the comment on the runner's `capture_mouse:` argument.

## Open questions

1. **Is the hover target a flag on `Component`, or a component *kind*** — a `Link`, a non-focusable
   `Button`? Tuile has no "clickable but not focusable" idiom today, and hover is most valuable
   exactly where focus cannot go: a "scroll to bottom" `Label` is outside the Tab cycle, so there is
   no focus accent for a hover accent to compete with and the ambiguity is *structurally absent*.
   The COP answer leans to the component kind, which would keep `Component` from growing a knob.
2. **Does (A) need `Component#hovered?`, `Screen#on_hover_changed=`, or neither?** The hooks
   shipped, so a component that reacts to *itself* is covered. What is not: `Screen#hovered` is the
   **innermost** component only, so a container on the hovered chain cannot ask whether it is on it,
   and an app wanting to drive its own painting from one place has no channel
   (`D_status_bar`'s `on_focus_changed=` is the precedent for the latter).
3. **Anything stronger than docs for the silent no-op? No — answered.** An app that overrides a
   hover hook and forgets `capture_mouse: :hover` gets nothing, silently, and there is no cheap
   detection: the framework cannot know a hook was overridden without probing every component, and
   components are added after the loop starts. A one-time `Tuile.logger` warning was possible but
   inverts the dependency. The three mitigations shipped instead — the rdoc on both members, a
   paragraph in book ch5, and the *Mouse* pane.
4. **Does open-on-hover need a `Ticker` delay, and is ~250 ms the number?** See *the accessibility
   argument*.

**Two further open items are measurements, not decisions**, and live in
`hover/terminal-probe.md`: tmux pane offset in a split, and text selection under 1003.

## Related

`R_mouse_reporting` (what terminals, the encodings and tmux actually do — the durable thing this
investigation produced), `D_mouse_dispatch` (the router, the grab, and everything step 1 settled),
`design/ideas/hover/terminal-probe.md` + `probe.rb` + `probe_spec.rb` (the matrix, the skipped rows
and the tooling; research scaffolding, dies with this note),
`design/ideas/focus-accent.md` (the surface/accent line, the segment-vs-component problem, and
option (C) which a framework hover accent would share),
`design/ideas/new-components.md` (Tier 2 Split Layout; Tier 3 Tooltip),
`D_menu_bar` (open-on-hover, deferred on motion; and the bar-mnemonic gap),
`D_mouse` (the mouse is additive), `D_extent` (hit-test the extent, not the rect),
`D_bg_surface` (`BG_STATES` is closed and framework-defined),
`D_theme_ref` (not a third colour channel), `D_inverse` (model the SGR rather than faking it, if a
non-background hover ink is ever wanted),
`D_progress_bar` (`sync_ticker` — how a hover-delay timer must be owned),
`D_status_bar` (`Screen#on_focus_changed=` as the app-channel precedent).
