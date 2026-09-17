# Hover — motion events, `on_mouse_enter` / `on_mouse_exit`, and who paints the accent

**Status:** designed and measured 2026-09-03; **step 1 landed 2026-09-17** with
`D_mouse_dispatch` — the event classes, the `capture_mouse:` ladder, motion, and
the enter/exit/move hooks all ship; what is left here is steps 2–3 and the
questions below. Paused otherwise — see *Where this stands* for the resume point. The note was reframed on
the same day it was filed (*The opt-in reframe*), which retired its first
conclusion; several other rulings were revised in place and are marked where
they changed. The terminal findings have since **graduated to
`R_mouse_reporting`**, and the code references were re-verified against the tree
on 2026-09-17.

Three questions, and the plan is to answer them in that order rather than
together:

1. **Plumbing.** Settle the event vocabulary, parse the motion codes and SGR
   encoding correctly, put motion behind the mode ladder — and *test it on real
   terminals*. **Done, except SGR**: the vocabulary and the dispatch it forced
   are `D_mouse_dispatch`, X10 motion parses and `capture_mouse: :drag` /
   `:hover` ship, and the measurement (one row of four, the rest skipped with
   reasons) is in `hover/terminal-probe.md`, its findings in
   `R_mouse_reporting`. **Still open here: request 1006 and parse both**, which
   needs the buffered incremental parser described below — without it a click
   past column 223 is still dead.
2. **Notices.** Derive enter/exit per component from the move stream. Mostly
   settled; two questions open.
3. **Ink.** *Then* decide, with the first two in hand: abandon the accent and
   let each app paint its own, do it for `MenuBar` only, or do it flatly for
   every component. **Untouched by design.**

Step 3 is deliberately last and deliberately reversible: steps 1–2 are useful
on their own, and a framework accent can be added later but not removed.

## Where this stands (resume point, 2026-09-03)

**Settled** — the event vocabulary and its three rulings, the two-level opt-in
and the `capture_mouse:` ladder, the encoding (request 1006, parse both), the
scroll split, exit-before-enter, the hover lifecycle from 1004, the tiled
resolution rule, and the demo. Each is marked *settled* at its own section; do
not re-litigate one without reading the paragraph that closed it.

**Open** — nine things, and they split by what unblocks them:

- *Needs a hand on a mouse* (both scoped in `hover/terminal-probe.md`): tmux pane
  offset in a split, and text selection under 1003.
- *Decidable by reasoning now*: open questions 1, 3, 7, 9, 10, 11 — the hover
  target's shape, chain-vs-leaf, whether `on_mouse_exit` survives outcome (A),
  the silent no-op, the `Ticker` delay, and whether the scroll split also
  changes scroll routing.

**The next substantive move is step 2**, the notices — the hooks exist, so what
is left is the two questions below (chain shape, and whether `handle_mouse_exit`
earns its place) plus the `MenuBar` consumers. The one piece of step 1 still
unbuilt is **1006**, and it is not hover-shaped.
`Keys.getkey`'s 5-byte gulp sits under ESC ambiguity, the `\e]` OSC 11 drain, the
8-byte 2031 report and bracketed paste — four things with nothing to do with
mice. Two facts keep it tractable: **parse-both leaves the X10 path and its tests
intact** (`keys_spec.rb:259-260` is the back-to-back burst test,
`file_commander_spec.rb:20` builds X10 clicks, and a PTY spec writes whatever the
helper builds), so the SGR path is purely additive — **but then nothing covers
SGR in a PTY spec**, because the burst-safety exception is X10-only. That path
needs unit coverage against a fake stdin with a report split across two reads,
mirroring the measured 11.5-byte read in `R_mouse_reporting`.

Also falls out, independent of all three: split `design/ideas/new-components.md`
item 5 into 1002-drag and 1003-hover; it currently lumps them, which is the
conflation this note exists partly to unpick. Landings 2 and 3 each owe a
CHANGELOG entry and a `D_`, and any public signature change ships the regenerated
`sig/tuile.rbs` in the same commit.

**If this note is picked up cold**, read in this order: *The opt-in reframe* →
*The opt-in model* → *The event vocabulary* → `R_mouse_reporting`. The rest is
detail hanging off those four.

## The opt-in reframe (supersedes the first draft's conclusion)

The first draft's headline objection was that a hover accent competes with the
focus accent — two highlights, same token, and the keyboard user cannot tell
which one Enter goes to. **That objection was scoped wrong.** It holds only for
a widget the framework accents *automatically*, and the intended shape is that
**the app names which components hover**: the OK button in a dialog, a
"Scroll to bottom" affordance the way the Claude CLI harness has one, a menu
item. Nothing else lights up, so nothing competes.

And the example that makes it clearly right: **a "Scroll to bottom" `Label` is
not focusable at all.** It is a click target outside the Tab cycle, so there is
no focus accent for a hover accent to be confused with — the ambiguity is
*structurally absent*. Which inverts the finding:

> **Hover is most valuable exactly where focus cannot go.** The competing-signal
> problem is real for `Button` (focusable, already accented) and vanishes for a
> non-focusable click target, which is the case with no other affordance at all.

That is worth noticing as a gap in its own right: Tuile has no "clickable but
not focusable" idiom today. `Component#handle_mouse` focuses if `focusable?`
and otherwise just descends, so such a thing is a `Label` subclass with a
`handle_mouse` override — reachable, unnamed, and undocumented. **Open
question:** is the hover target a *flag on `Component`*, or is it a component
kind (a `Link`, a non-focusable `Button`) that happens to hover? The COP answer
leans to the latter, and it would keep `Component` from growing a knob.

## The opt-in model — two levels, and hover is never load-bearing

**Settled 2026-09-03.** Motion is opt-in the way the whole mouse already is:
one switch at `run_event_loop`, off by default, so **an app that does not ask
pays nothing** — not a byte on the wire, not an event in the queue, not a
branch in the hot path. That is what makes the rest of this note safe to build,
and it is worth stating before any design: the default profile does not change.

Two levels, and they answer different questions:

| level | question | shape |
|---|---|---|
| **the mode** | does this app want to pay for motion at all? | one kwarg at `run_event_loop` |
| **the component** | which widgets do something when hovered? | having a handler / a hover color |

The mode switch is a statement about the app's *character* — a rich TUI says
yes, a log tailer says no — not a per-feature toggle. The component level is
where "flatly for everything" vs. "only the menus" is expressed, and it needs no
framework knob at all (see *the opt-in mechanism* below).

### The invariant that keeps it honest

> **A hover feature is a second route to an affordance that already exists.
> Never the only route.**

`MenuBar` must work exactly as well with motion off, and it does — check both
sub-cases against the rule:

- *Open-on-hover of a sibling menu while a cascade is open* → with motion off
  you **click** the sibling. Same outcome, one more click.
- *Item highlight under the pointer* → with motion off the **arrows** move the
  cursor. Hover just becomes a third way to set a position that already has
  two.

This is the acceptance test for every future hover consumer, and it is what
stops the opt-in from quietly becoming mandatory. A proposal that fails it — a
disclosure reachable *only* by hovering — is rejected on that ground alone,
because it would make a mode-off app strictly less capable rather than merely
less smooth. It also keeps the existing suite valid: no PTY spec needs motion
to prove `MenuBar` works, because nothing about `MenuBar` depends on it.

### The kwarg

`run_event_loop(capture_mouse: true)` is a Boolean today (`screen.rb:466`).
Widen it into a **ladder named for what the app gets**, not for the mechanism —
each rung a strict superset of the one before, ordered by cost:

```ruby
capture_mouse: false      # nothing
capture_mouse: true       # == :clicks → 1000   (the default; today's behavior)
capture_mouse: :drag      # → 1002
capture_mouse: :hover     # → 1003
```

`true` stays the default and becomes an alias for `:clicks`, so nothing breaks.
One knob makes the illegal state — motion without mouse capture —
*unrepresentable*, where a second `track_motion:` kwarg would need a guard and a
raise to say the same thing. Symbol enums are house style already
(`scrollbar_visibility=`, which also shows the discipline of refusing an
`:auto`).

Naming them `:drag` / `:hover` rather than a single `:motion` matters: `:motion`
conflates 1002 and 1003, which is exactly the conflation
`design/ideas/new-components.md` item 5 already makes and which this note exists partly
to unpick.

### The one real cost of two levels: a silent no-op

An app that overrides `on_mouse_enter` and forgets the mode switch gets
**nothing, silently** — no error, no warning, no hint. That is the footgun, and
it has no cheap detection (the framework cannot know a hook was overridden
without probing every component, and components are added after the loop
starts). Mitigations, none free: document it on both members so either rdoc
mentions the other; put it in the book's mouse section; and let a dedicated
`examples/` script be the copy-paste source rather than the sampler. **Open
question** whether anything stronger is warranted — a one-time `Tuile.logger`
warning the first time a hover hook fires with the mode off is possible but
inverts the dependency (the framework would have to notice a hook it never
called).

### What the settled mode kills

Recording this because it removes work the earlier draft was carrying:

- **No refcounting.** The "enable 1003 while a cascade is open, disable it
  after" design needed an enable/disable count as soon as two consumers
  overlapped. Gone.
- **No mid-loop mode toggling**, and so no inheriting `D_background_rgb`'s rule
  about which thread may write to the terminal between frames. The escape is
  written once in `run_event_loop`'s existing `begin`/`ensure` pair, beside the
  three modes already there.
- **Scoped tracking stays available as a later optimization** if the measured
  event rate turns out to be a problem, but it is no longer part of the design.

## Step 1 — plumbing

### Tuile receives no motion today

{Screen#run_event_loop} enables **mode 1000** only (`screen.rb:474` →
`MouseEvent.start_tracking`, `"\e[?1000h"`), so releases arrive today and are
simply discarded. The mode ladder itself — 1000 / 1002 / 1003, and why 1002 buys
nothing over 1000 unless you want drag-motion — is `R_mouse_reporting`. Who here
wants which:

| mode | who wants it |
|---|---|
| `1000` | today's clicks and wheel |
| `1002` | Split divider, Slider, scrollbar drag |
| `1003` | **hover**, open-on-hover, Tooltip |

Two naming hazards, both live in this note rather than in the research:
**"X10"** in `mouse_event.rb` names the *encoding*, never mode 9; and when
talking about 1002/1003, say **motion** or **hover** tracking — "highlight
tracking" is mode 1001's actual name, and using it loosely will eventually get
1001 typed by accident, which can hang the terminal. Mode **1004** is wanted here
only to clear a stranded hover (see *no reliable exit event*).

**Hover needs 1003, drag needs only 1002, and they are not one prerequisite.**
`design/ideas/new-components.md` item 5 lumps them ("mouse motion/drag, modes
1002/1006"); split it when either lands. A drag flood is bounded — it lasts as
long as a button is down and the user is doing one deliberate thing. A 1003
flood is a report per cell crossed, unconditionally, including while the app is
idle and while the user is merely moving the mouse to a different window.

### What Tuile's parser does with it today

{MouseEvent.parse} decodes `Cb = code + 32` and cases on the code
(`mouse_event.rb:51-59`). Against the X10 code layout (`R_mouse_reporting`):

| event | code | `parse` gives today |
|---|---|---|
| left press | 0 | `:left` |
| wheel up / down | 64 / 65 | `:scroll_up` / `:scroll_down` |
| **release (any button)** | 3 | **`button: nil`** |
| motion, left held | 32 | `button: nil` |
| motion, no button | 35 | `button: nil` |

Two consequences:

- **No collision, so flipping to 1003 is safe today.** Motion codes sit clear of
  the wheel's, so motion
  would *not* manufacture phantom scroll events, and every `handle_mouse` gates
  on `event.button == :left`, so motion would arrive and be ignored. That makes
  step 1 genuinely low-risk to spike.
- **`button: nil` is already an overload**, and this is a pre-existing wart the
  work would fix rather than create. It means "release" today — releases *do*
  arrive under mode 1000, they are just button-anonymous, which is why nothing
  has ever used them — against an rdoc that says `nil` means "not known"
  (`mouse_event.rb:8`). Both `D_menu_bar` and `D_no_context_menu` say
  "press-only, no release"; that is imprecise and should be corrected when this
  lands.

### The event vocabulary — superseded by `D_mouse_dispatch`

**This section's rulings were re-decided and shipped**; what follows is kept only
for the reasoning that fed them, and `D_mouse_dispatch` is authoritative. The
shape that landed: one class per wire event under `Tuile::Mouse` (no `kind:`
field, no `MouseEvent`), a router rather than `Component#handle_mouse`, a move
that *bubbles* rather than going to the whole hovered chain, and scroll bubbling
with consumption (which answers open question 11 the other way).

### The event vocabulary — as settled 2026-09-03

Derived from consumers rather than from the wire, which is what makes it come
out small:

| event | who actually needs it |
|---|---|
| press | everything today — `Button`, `Checkbox`, `List` row, `Select`, `MenuBar` |
| scroll notch | `TextView`, `List`, `TextArea`, `ListDropdown` |
| release | nothing today; drag, and press-visual-feedback |
| move | **nobody directly** — it is substrate |
| enter / exit | hover consumers (derived from move) |
| drag | Split divider, Slider, scrollbar thumb (derived from press→moves→release) |

**Almost nothing wants a raw move** — enter/exit and drag are both *derived*, so
moves are consumed inside `Screen` rather than broadcast. But "never delivered"
was too strong, and the demo in open question 12 is what found it: a component
that paints something **at the pointer's position inside itself** — a crosshair,
a following tooltip, a canvas — needs the position on every move, and enter/exit
cannot supply it.

So the rule is narrower than "nowhere public": **a move goes to the hovered
chain, and only to a component that overrides `on_mouse_move`.** One that does
not override it pays nothing and never sees the flood. That is the same
opt-in-by-handler mechanism the rest of the design uses, and it is what makes
the volume safe — which is also the *real* argument for keeping moves out of
`handle_mouse`, see below.

**Chain, not leaf — and that is the *existing* rule, not a new one.** Worth
stating outright, because "only the component under the cursor" is the intuitive
reading and it is wrong: `Component#handle_mouse` already runs its own body
first and *then* descends into every child containing the point
(`component.rb:351-357`), so every ancestor on the path sees a click today. Moves
mirror it. A container therefore gets moves both when the pointer is over one of
its children and when it is over a `spacing` gap that no child covers — the
latter being the case where the container is also the leaf. Two things make
chain the right answer rather than merely the consistent one:

- **Enter/exit are chain already** (symmetric difference of the two chains). A
  container told "the pointer entered you" but denied *where* it is has a strange
  contract — coarse fact granted, fine fact withheld.
- **`on_mouse_move` is a hook, not a handler.** No return value, nothing
  consumes it, so there is no "the leaf ate it" concept to build leaf-only on. It
  is fan-out like `handle_theme_changed`, not dispatch like `handle_key?`, and
  leaf-only would mean the framework *deciding* not to tell an interested
  ancestor.

**The point is screen-absolute**, 0-based, exactly as `MouseEvent#x/y` are today
(`mouse_event.rb:9-12`) — each recipient converts against its own rect, which is
what makes chain delivery work at all. Stated rather than inferred, per
AGENTS.md's convert-never-conflate rule: a hook whose entire job is positional
should not leave its space to the reader.

**Wire / queue layer — three classes:**

```ruby
MouseEvent(kind: :press | :release, button:, x:, y:)   # buttons only
MouseScrollEvent(direction:, x:, y:)                    # the wheel
MouseMoveEvent(button:, x:, y:)                         # button = held, or nil
```

**Component layer — barely changes:**

```ruby
handle_mouse(event)                # press/release; existing name, existing routing
handle_scroll(event)               # the wheel
on_mouse_enter / on_mouse_exit     # hooks, :hover only
on_mouse_move(point)               # hook, :hover only, opt-in by override
```

**This reverses the first draft's lean**, which argued one class with a `kind`
field and rejected a separate move class as "modelling the wire wrong". Two
things overturned it.

First, once scroll and move leave, `MouseEvent` + `button` means exactly what it
says, so **no rename is needed** — the naming complaint that started this was
really a symptom of three event kinds sharing one class.

Second — and this is the load-bearing one — **the delivery rule differs, and
volume makes that decisive.** A press goes to every component whose rect
contains the point, unconditionally; a move goes to the hovered chain and only
to opted-in overriders. Route moves through `handle_mouse` as `kind: :move` and
**every existing `handle_mouse` starts receiving ~84 events/s** and needs a
guard against them — the exact trap the "`:release` is parsed but not delivered"
ruling avoids, at 84× the rate. A separate class makes the flood
unreachable-by-default instead of guarded-by-convention.

*Corrected:* the first version of this argument said press and move need
different routing because press "goes to *every* child whose rect contains the
point, while move must resolve a single topmost target". That overstated it —
**overlapping tiled siblings are already forbidden** (`component.rb:817`: "as
long as siblings don't overlap each other — which Tuile already requires"), so
at most one child contains any point and the tree walk is effectively the same
for both. The delivery-and-volume argument above is the one that actually holds.

`MouseMoveEvent` keeps a `button` because under 1003 motion genuinely carries
held-button state (codes 32/33/34) — which is exactly what a future drag needs,
so the field is honest there rather than vestigial.

`MouseEvent` is a `Data.define(:button, :x, :y)` constructed **positionally** at
`mouse_event.rb:60` and in ~56 spec call sites, so adding `kind:` needs an
`initialize` override with a default (the `PasteEvent` / `TTYSizeEvent`
precedent) to keep three-arg construction working.

### Three rulings that come with the vocabulary

- **Activate on press, not on click — there is deliberately no click
  synthesis.** Real click semantics (press *and* release on the same widget,
  drag-off-to-cancel) are achievable under mode 1000 today, since releases
  already arrive. Declined: activation would then depend on two events instead
  of one, over ssh and tmux where either can be lost, and the failure mode is
  "buttons stop working". Press-activation is also snappier on a laggy link and
  survives a terminal that reports no release at all. This is why the class is
  **not** renamed `MouseClickEvent` — that would name a synthesis Tuile
  deliberately does not perform.
- **`:release` is parsed but not delivered, until a consumer exists.** Not
  merely YAGNI — delivering it *breaks* existing widgets. Thirteen sites filter on
  `event.button == :left` and would see a second event per click, so anything
  toggling on a left event would double-toggle. Parse it, keep it out of
  delivery.
- **Enter/exit fire only under `:hover`.** Mode 1002 *can* produce motion (while
  a button is held), so a partial enter/exit during a drag is technically
  available. Declined: a component that receives enter/exit *sometimes* is worse
  than one that never does. Consistency over capability.

### The scroll split — what it actually buys

Blast radius is small and measured: **exactly two scroll consumers**
(`list.rb:323-325`, `text_view.rb:376-378`) move to `handle_scroll`. The thirteen
`event.button == :left` filters **stay as they are** — they filter button
*identity*, not event kind, so the split does not delete them. The wins are
structural rather than a line count:

- **A wheel notch is not a button.** `direction:` replaces
  `button: :scroll_up`, which was always a category error.
- **Scroll can no longer leak into click logic.** `ScreenPane#handle_mouse`'s
  outside-click dismissal (`screen_pane.rb:241`) and `Component#handle_mouse`'s
  click-to-focus (`component.rb:351`) currently exclude scroll *by filter*; with
  a separate class they exclude it *by type*. `D_notification`'s stray-spin
  lesson becomes unrepresentable rather than remembered.
- **Scroll routing becomes independently specifiable** — the innermost
  *scrollable* under the pointer, bubbling when it cannot scroll further, the
  way a browser does. That is unavailable today because scroll rides the click
  routing, and it is the one new capability here.

Bundle it with the rest: the vocabulary change is the breaking change, so
everything needing one should land together rather than breaking `handle_mouse`
implementors twice.

**And the parse fix is unconditional** — it ships whether or not anyone ever
enables motion. Releases already arrive under mode 1000 and already land as
`button: nil`, so distinguishing `:press` from `:release` is a correctness fix
to today's default profile that happens to leave a `:move` slot ready. Worth
separating in the commit history for that reason: the wire-format cleanup is
not gated on the mode, and does not need the terminal matrix to justify it.

### Two mechanical hazards, both concrete

- **The 5-byte gulp is exactly right for X10 and wrong for SGR.**
  `Keys.getkey` reads `\e` then `read_nonblock(5)`, and the comment at
  `keys.rb:161-167` is explicit that 6 would over-read "on tight mouse-event
  bursts". 5 works *because* an X10 report is exactly 6 bytes. SGR reports are
  variable-length **and split across reads** (`R_mouse_reporting`), so the
  replacement must be a **buffered incremental parser**, not a wider gulp — a
  drain rule of its own, like the `\e[?` and `\e]` loops beside it.
- **The queue coalesces repaints but not events** — and the arithmetic says
  that is fine. `event_loop` yields `EmptyQueueEvent` only when the queue is
  empty (`event_queue.rb:339`), so a flood defers the repaint to the drain,
  which is the right behavior for free. The theoretical failure is that if
  handling were slower than arrival the queue would never empty and the UI
  would stop repainting altogether — a freeze, not a trailing accent. **But
  default handling is a hit-test walk that ends in every component declining**:
  order ~100 `rect.contains?` comparisons, tens of microseconds, against a
  **measured ~84 reports/s** (`R_mouse_reporting`; this note's working estimate
  was ~160/s, so the real margin is twice as wide, and the ssh packet-rate worry
  goes with it). Three to four orders of
  magnitude of headroom. The first draft called a
  mitigation "probably mandatory"; that was overstated, and the measurement has
  now retired the question — **treat throttling, event collapsing and forced
  repaints as out of scope for this note.** If the number ever surprises us, that is a
  separate idea with the measurement to justify it.

### Encoding: request 1006 always, parse both

Reporting modes say *what* is reported; encoding modes say *how* the coordinates
are packed. They are orthogonal, set independently, and both persist — which is
the fact that makes this easy.

**Request `\e[?1006h` alongside whichever reporting mode, unconditionally, and
keep the X10 parser.** A terminal that does not understand 1006 ignores it and
keeps sending X10 (`R_mouse_reporting`), so parsing both degrades gracefully with
no risk of total mouse loss. Two things arrive that X10 cannot express, and both
matter here: **coordinates past 223** — a hover accent that stops working on the
right half of a wide terminal is a reported bug, where a dead click there is
merely invisible — and **a release that says which button came up**, which
anything beyond single-button drag needs.

Keeping the X10 path costs nothing — it exists and is tested. What the addition
does cost is the drain rule above, and X10's convenient PTY burst-safety: a
fixed 6-byte report splits cleanly on a boundary, a variable-length one does not.
`1005`, `1015` and `1016` are all ruled out on their own terms
(`R_mouse_reporting`).

**And there is no runtime capability check** — DECRQM answers for 1006 but for
none of the reporting modes (`R_mouse_reporting`), which retroactively makes
request-and-parse-both the only viable strategy rather than merely the convenient
one, and means the `capture_mouse:` ladder can never validate itself.

### Measured — tmux-over-ssh, 2026-09-03

**One row of the four-environment matrix is done, and the findings have
graduated**: everything the probe established about terminals is
`R_mouse_reporting`. The matrix itself, which rows were skipped and why, and the
two items still open — tmux pane offset in a split, and text selection under 1003
— are `design/ideas/hover/terminal-probe.md`, beside the probe that produced them.

Three results changed this note rather than merely confirming it, so they are
recorded at the decision they moved:

- **The rate is half the working estimate** (~84/s, not ~160/s), which is why
  throttling is out of scope above rather than "probably mandatory".
- **Reads do not align to event boundaries**, which is what makes the SGR
  replacement a buffered incremental parser rather than a wider gulp.
- **DECRQM answers for no reporting mode**, which is what makes
  request-and-parse-both the only viable encoding strategy.

Nothing measured contradicted the design. The one row that would have — tmux
stealing motion from an app that requested tracking — came out clean.

### Testing it in specs

Two pieces of good news:

- **A burst of X10 mouse reports is safe to write in a PTY spec**, unlike
  ESC-then-key. `getkey` reads one byte then gulps 5, and a report is exactly
  6, so back-to-back reports split cleanly on the boundary. That is a genuine
  second exception to AGENTS.md's pacing rule (bracketed paste is the first),
  and it is exactly what a flood test needs. It holds for X10 only — SGR's
  variable length would break bursting, which is one more reason to fix the
  drain rule before switching encodings.
- **Unit specs need no terminal**: `FakeEventQueue` + `FakeScreen` can post
  synthetic move events and assert the enter/exit sequence directly.

## Step 2 — the notices

### Enter/exit are *derived*, so they are hooks, not queue events

Worth separating from the framing above: `MouseMoveEvent` is a wire event, but
enter and exit are **computed by diffing** the previous hovered target against
the new one. Nothing is parsed. So they should not be `EventQueue` events —
routing them through the queue would re-resolve a target that was already
resolved at diff time, and the queue has no other synthesized *targeted* event.
They are the `handle_attached` / `handle_detached` shape from `D_attach_hooks`: **one
firing site, a fixed order, at most one call per component per transition.**

**Order: exit before enter** (settled 2026-09-03, the DOM order). No component
is ever hovered twice at once, which is what a driver switching a menu panel
wants, and a handler firing on enter can rely on the previous target having
already torn down.

### Where the state lives

Hover is one global position resolved to a component — the `Screen#focused`
shape exactly. `Screen` is the service and `ScreenPane` is the UI
(`D_tree_first`), and `focused=` lives on `Screen`, so: **`Screen#hovered`**,
plus a per-component `hovered?` mirroring `active?` (a component's own `repaint`
needs to know, if it paints anything).

### Which component is under the pointer — a rule the click path never needed

Simpler than the first draft feared, because **overlapping tiled siblings are
already forbidden** — `component.rb:817` states it outright ("as long as
siblings don't overlap each other — which Tuile already requires"), and the ban
is load-bearing: `children_tile_rect?` sums child *areas* to decide whether to
wipe gaps, so an overlap silently mis-computes it. In a legal tree at most one
child contains any point, so the tiled resolution is unique by construction and
needs no tie-break. Two rules remain:

- **Popups first.** `ScreenPane#handle_mouse` already resolves topmost
  (`@popups.reverse_each.find`, `screen_pane.rb:240`), and hover *must* go
  through it: popups overdraw content with no clipping, so a component beneath a
  popup contains the point and is not visible. This is the only *layer* rule
  needed, precisely because the tiled tree has no overlap of its own.
- **Hit-test `extent_rect`, not `rect`.** A `Button` in a wide form column must
  not light up when the pointer is on the dead tail it does not paint. This is
  `D_extent`'s hit-testing consumer, and it is *cleaner* than the click case —
  clicks deliberately let the tail focus the widget while refusing to activate
  it, whereas hover has no focus half, so `extent_rect` applies without a
  carve-out.

### Leaf or chain — the reframe flips this

The first draft leaned leaf-only, on the grounds that chain-hover would make a
`Window` tint whenever anything inside it is hovered. **That was an argument
against an automatic accent, not against chain notification** — and once opt-in
is the design, it evaporates: a `Window` that did not ask for hover paints
nothing, so notifying it costs nothing and enables the cases that want it (a
container reacting when the pointer is anywhere inside it).

So: **fire along the ancestor chain**, with enter/exit computed on the
*symmetric difference* of the two chains — which is what browsers do, and what
`focused=`'s `active=` walk already does for focus (`screen.rb:387-393`). The
diff is a set difference rather than a pointer compare; that is the whole added
cost.

### The opt-in mechanism — probably no flag at all

- **A `hoverable?` predicate** mirroring `focusable?` is the obvious move, but
  `focusable?` is a *method* apps override in a subclass, and marking one
  `Button` hoverable without subclassing needs a writer — a new pattern on
  `Component`.
- **Better: opt-in *is* having a handler or a hover color.** The framework
  fires enter/exit on the chain unconditionally (it is a diff, and it is cheap);
  a component that neither overrides the hook nor was given a hover color does
  nothing. Nothing to consult, nothing to keep in sync, no knob. This is the
  COP-shaped answer: the component decides by what it *does*, not by a flag the
  framework reads off it.

### Hook, listener, or one `Screen` channel

Three precedents, ascending in cost — and they are not exclusive:

- **`Screen#on_hover_changed=`** — one app-level channel mirroring
  `Screen#on_focus_changed=` (`screen.rb:428`), the shape the deleted status bar
  was replaced with (`D_status_bar`). Cheapest, and enough for an app that wants
  to drive its own painting.
- **A protected hook pair** — `on_mouse_enter` / `on_mouse_exit`, overridden by
  a subclass, invoked via `__send__` per `D_hook_visibility`. This is what
  `MenuBar` open-on-hover actually needs.
- **A listener registry** — `on_mouse_enter { }` in the `on_value_change` style.
  No consumer yet asks for multiple subscribers.

Naming: `enter`/`exit` is the Swing pair, `enter`/`leave` the DOM one. Focus
grew its own "leave" hook on 2026-09-04 (`Component#handle_blur`, `D_on_blur`), and
that entry settled two things this note can copy rather than re-argue: exit
fires before enter, and an app-level `on_focus_changed` did **not** make the
per-component hook unnecessary — a component that must react to *itself* cannot
do it from a screen-wide notice. Whether hover's exit clears that bar is still
open (see Q7), since hover paints nothing by default.

### There is no reliable exit event

Mode 1003 reports motion *inside* the terminal, and a pointer that leaves the
window sends nothing — motion simply stops (`R_mouse_reporting`), leaving the
last report at whatever cell it was last sampled in. So the last-hovered
component stays hovered and anything it painted strands.

**Mode 1004 answers most of it, and it works** (`R_mouse_reporting`). It fires on a
genuine pointer exit *and* on an alt-tab with the pointer still inside the
window — and **both should clear hover**, because with the app unfocused,
painting an accent for a pointer the user is not driving is simply wrong. That
gives a complete lifecycle out of 1004 plus motion alone:

> **Clear hover on FocusOut. On FocusIn, keep it cleared until the next
> `MouseMoveEvent`** — the pointer may be anywhere, and we do not know where
> until it moves.

Plus a cheap belt — **any keystroke clears hover** — and **three strand sites
that want one repair, not three toggles**: FocusOut, detach, and *hiding*. The
third is easy to miss because `visible = false` fires no lifecycle hook at all,
so there is nothing for a component to hang a clear on; but the firing site
already exists and already does exactly this for focus —
`Component#visible=` calls `repair_focus_after_hiding` (`component.rb:179`), and
a hover repair slots in beside it. Detach is the `@popup_prior_focus` failure
mode: without it `Screen#hovered` strands a reference to a component no longer in
the tree. Per AGENTS.md this should be **one idempotent sync over the invariant**
(the hovered chain is attached, visible, and under the last known point), never
three separate mutations — a third site is what turns the naive pair into a 2×2.

**Rejected: infer the exit from an edge cell.** Tempting, because a real
pointer-exit's last report *was* at an edge (`0,7`, `0,6`, `0,5` in the sample —
the mid-screen ones turned out to be alt-tabs, not exits). Don't build it, for
two reasons. **Edge cells are legitimate, common hover targets** — column 0 is
where a scrollbar, a sidebar's first column and a `MenuBar`'s first item live,
so "last motion at an edge, then quiet" is indistinguishable from a pointer
resting on exactly the widget you most want hovered; the heuristic would flicker
the accent off under a *stationary* pointer, which is worse than a strand. And
**a fast exit may emit no edge report at all**: sampling is ~84 Hz, so a quick
flick out of the window can have its last report several cells short of the
boundary, making it an unreliable signal as well as an unsafe one.

The residual gap after all that is narrow — the pointer wanders off the window
while the terminal keeps *keyboard* focus (1004 is about keyboard focus, so
nothing fires), which in practice means a click-to-focus window manager and a
user who touches no key. But narrow is not the same as harmless, and the shape
of the failure is worth spelling out, because it constrains what the hook may be
used for:

- **Exit fires at *re-entry*, not at departure, so the delay is unbounded.**
  Pointer leaves by one edge, wanders for thirty seconds, comes back by another:
  the first move event resolves a different component, and only *then* does the
  stale one get its `on_mouse_exit`.
- **Or never.** Pointer leaves, never returns, no keystroke, app quits. `Screen#close`
  unmounts the tree and the detach repair drops the reference, but these are
  lifecycle hooks rather than destructors (`D_attach_hooks`), so the honest
  default is that no exit fires at all.
- **Or correctly, by accident.** If re-entry lands on the same component the diff
  sees no change, no exit fires, and the stale state was right all along. That is
  the common case for a large target.

> **So `on_mouse_exit` must never become a commit point** — the exact inverse of
> `handle_blur`, which *is* one (a widget resolving a click calls `super` first, or it
> drops the abandoned field's last edit). An exit that may arrive late, or not at
> all, cannot carry a commit: the failure would be silent and unfixable at any
> layer. Anything that must happen when the pointer leaves has to be idempotent,
> cosmetic, and survivable if it is thirty seconds late.

What is visible during the excursion is not the delay but the accent, sitting lit
on a component the pointer is not over. That is cosmetic, and the
never-load-bearing rule absorbs it — but a menu that *opened* on enter and could
only be closed by exit would be a bug with no fix, which is the concrete form
that rule is protecting against.

## Step 3 — the ink, once 1 and 2 are in hand

The three outcomes, as framed:

- **(A) Abandon the framework accent; the app paints.** With steps 1–2 done
  this is not really abandonment — it is the whole Claude-CLI-`Label` case
  working, with the app's own `repaint` reading `hovered?`. Zero new ink, no
  `BG_STATES` change, no focused-vs-hovered precedence rule, and it stays
  reversible. **The recommended landing point.**
- **(B) `MenuBar` only** — and this is the one with real behavior behind it, not
  just ink. See below; it is more interesting than it looks.
- **(C) Flatly, for every component.** Needs `BG_STATES` to grow `:hover`
  (admissible in principle — AGENTS.md says a key is added "when Tuile grows the
  *state*", and this would be Tuile growing one), *plus* a
  focused-and-hovered precedence ruling that a two-state map never had to answer,
  *plus* an answer to `focus-accent.md`'s finding that three of the five
  accenting widgets highlight a **segment or row**, not the component, which a
  per-component hook cannot express. That last one is fatal on its own: the
  interesting hover targets *are* the segment/row cases.

### What `focus-accent.md` already settles for step 3

That note measured migrating the five accenting widgets onto
`default_bg_color`: **+2 lines each, and inexpressible for `Tabs`, `MenuBar` and
`List`.** Hover lands on the same rock, so if a framework accent is ever built
it is via that note's **option (C)** — a paint-time `over_bg` accent layer
applied to a `StyledString` rather than declared per component, which covers
segment and row granularity. Hover is the second consumer that makes (C) worth
pricing rather than parking. Weigh against `D_theme_ref`'s "not a third colour
channel" first.

One thing that is *not* in the way: `List` applies its cursor highlight at paint
(`is_cursor ? base.with_bg(…) : base`), not into the memoized row, and the
cache-dropping rule is about *geometry* inputs — so a hover accent is the same
shape and needs no `drop_row_cache`.

### `MenuBar` is the strong case, and it needs no new ink

Two sub-cases, and both dodge the accent question entirely:

- **Hover highlight inside an open dropdown = move the `List` cursor.** The
  cursor already highlights, arrows already move it, Enter already activates
  it. Hover just becomes a third way to set the position — so there is no second
  accent, no new token, and no ambiguity, and it is what every desktop menu
  does. This is the cleanest hover feature in the whole note.
- **Open-on-hover of the strip, *only while a cascade is already open*** — the
  desktop convention (hovering a closed menu bar does nothing; once one menu is
  open, hovering a sibling switches to it). `D_menu_bar` defers this explicitly
  on "needs mouse motion".

Both satisfy the never-load-bearing rule for free, which is why this is the
case to build first if anything is built.

### The accessibility argument, taken seriously

Hover-open submenus and a highlighted item under the pointer are worth
something for **low-vision and magnifier users** specifically: when you can see
a fraction of the screen at a time, a highlight that tracks the pointer answers
"where am I" continuously, and auto-opening a submenu removes a precise click
from the sequence. That is a real benefit and it is the strongest *motivation*
in this note. Two consequences follow from taking it seriously rather than
citing it:

- **Open-on-hover needs a delay, or it is worse than nothing.** Dragging the
  pointer across a strip with no delay flash-opens every menu in turn — for a
  magnifier user that is actively disorienting, and for a motor-impaired user it
  is a stream of accidental opens. Desktop menus use ~200–400 ms. Tuile has the
  machinery (`Ticker`, which {Component::ProgressBar} owns), and
  `D_progress_bar`'s `sync_ticker` is the pattern to copy: the timer is *synced
  from an invariant* (cascade open && motion enabled && pointer on a sibling
  segment), never toggled by the enter and exit hooks, because a third mutation
  site turns those two into a 2×2 the naive pair gets half wrong.
- **It argues against a second highlight, which is what the cursor-reuse design
  already does.** For a low-vision user, two similar-but-distinct highlights on
  screen is worse than one — the discrimination task is the expensive part. So
  "hover moves the `List` cursor" is not just the cheap implementation, it is
  the *accessible* one, and a separate hover ink would be a regression for the
  population that motivates the feature.

Worth stating plainly, though, because it changes the priority: **the bigger
accessibility lever here is not hover at all.** `D_menu_bar` records that with
no Alt and no function keys the only way to *reach* the bar is Tab — "the
deferral that costs something". A user who cannot use a mouse gains far more
from `Alt+F` than any pointer user gains from hover. If accessibility is the
reason to spend a session, `Keys` growing function keys and a bar mnemonic
outranks all of this.

## The demo — `examples/hover.rb`

Settled 2026-09-03, and it earned its keep before being written: designing it is
what found the `on_mouse_move` hole above. A `Layout::Horizontal` of two
`Percent[50]` panes:

- **Left — one custom component**, exercising all three channels: it changes its
  background on `on_mouse_enter` / `on_mouse_exit`, changes it *again* on a
  press (so hover and click are visibly distinct signals), and paints an `X` at
  the pointer's cell from `on_mouse_move`. That last one is the whole reason the
  move hook exists, and the pane is its only demo.
- **Right — a live log** of every event the left pane received, auto-scrolling.

Two house-rules corrections to the obvious implementation:

- **Use {Component::LogTextView}, not a `List`.** `List` has **no appenders**
  (removed in 0.12.0, `D_list_items`) — an app that grows one keeps its own
  array and re-assigns, and a re-assignment drops the whole row cache, so at 84
  events/s the viewport would re-render every row 84 times a second.
  `LogTextView` is the auto-scrolling, incrementally-appending one and is what
  `LogWindow` is built from. It also demos a second component for free.
- **Don't log raw moves verbatim.** At ~84/s the log becomes unreadable and
  proves nothing. Log the *discrete* events (enter, exit, press) in full, and
  show the live pointer position in the left pane — the `X` already is that
  readout, optionally with a coordinate label. If a move trace is wanted, it
  belongs as a counter or a single replaced line, not one row per event.

The demo also needs `capture_mouse: :hover`, which makes it the copy-paste
source for the two-level opt-in and the natural place to document the silent
no-op (open question 9).

## Open questions, collected

Struck-through entries are settled and kept so a re-reader can see the question
was asked and answered rather than missed. **Two further open items are
measurements, not decisions, and live in `hover/terminal-probe.md`:** tmux pane
offset in a split, and text selection under 1003.

1. Is the hover target a flag on `Component`, or a component *kind* (a `Link` /
   non-focusable `Button`)? Related: should Tuile name the
   clickable-but-not-focusable idiom at all?
2. ~~`kind:` field on `MouseEvent` vs. a separate `MouseMoveEvent`.~~
   **Settled 2026-09-03:** both — three wire classes (`MouseEvent` with
   `kind: :press|:release`, `MouseScrollEvent`, `MouseMoveEvent`), no rename,
   moves never delivered to components. Press-not-click, release-parsed-but-
   undelivered, and enter/exit-only-under-`:hover` settled with it.
3. Chain or leaf for enter/exit. (Lean: chain, given opt-in — and note this now
   carries weight it did not when it was filed: *the event vocabulary*'s move
   rule leans on enter/exit being chain, so settling this leaf-only would make
   moves the odd one out against a click path that is already chain.)
4. ~~Scoped 1003 vs. all-or-nothing at `run_event_loop`.~~ **Settled
   2026-09-03:** all-or-nothing, opt-in, off by default. Scoped tracking stays a
   later optimization if the measured rate demands it.
5. ~~Does mode 1004 focus-out actually arrive?~~ **Measured 2026-09-03**
   (`R_mouse_reporting`): yes, on both real exits and alt-tabs. Lifecycle settled
   (clear on FocusOut; stay cleared through FocusIn until the next move); the
   edge heuristic is rejected. Still unmeasured in the other three environments.
6. ~~Exit-before-enter, or the reverse?~~ **Settled 2026-09-03:** exit first,
   the DOM order.
7. If step 3 lands as (A), does `on_mouse_exit` still earn its place — or does
   `Screen#on_hover_changed=` plus `hovered?` cover every consumer? (The focus
   half of this question was answered *against* the app-level-only design on
   2026-09-04 — `D_on_blur`. Hover differs in that no widget commits anything
   on exit, so it may still land the other way.)
8. ~~Overlapping tiled rects: last-in-paint-order wins, or refuse?~~ **Settled
   2026-09-03: the question does not arise** — overlapping tiled siblings are
   already forbidden (`component.rb:817`, and `children_tile_rect?` depends on
   it), so at most one child contains any point. Only the popup layer needs a
   topmost rule, and it already has one.
9. Anything stronger than docs for the silent no-op (hover hook overridden,
   mode off)?
10. Does open-on-hover need a `Ticker` delay, and is ~250 ms the number? See
    *the accessibility argument*.
11. Does the scroll split also change scroll *routing* — innermost scrollable
    under the pointer, bubbling when it cannot scroll further — or does it keep
    today's click routing and bank only the type separation? (The capability is
    the split's main prize, but it is a second behavior change and could land
    after.) **Lean: bank only the type separation.** The split is already
    breaking for `handle_mouse` implementors, so bundling a routing change means
    two behaviour changes under one CHANGELOG entry and no way to bisect a broken
    scroll. And bubbling-when-exhausted needs a "can I scroll further?" predicate
    on `List`, `TextView`, `TextArea` and `ListDropdown` — a new cross-component
    contract, and its own design question. Type separation alone is mechanical.
    **Decide this before writing `handle_scroll`**, since it is the difference
    between a rename and a new walk.
12. ~~Demo shape?~~ **Settled 2026-09-03:** a dedicated `examples/hover.rb`
    (which also keeps the sampler's PTY spec on the default profile), two panes
    side by side — see *The demo* below.

## Related

`R_mouse_reporting` (what terminals, the encodings and tmux actually do — the
probe's findings, and the one durable thing this investigation produced),
`design/ideas/hover/terminal-probe.md` + `probe.rb` + `probe_spec.rb` (the matrix,
the skipped rows and the tooling; research scaffolding, dies with this note),
`design/ideas/focus-accent.md` (the surface/accent line, the segment-vs-component
problem, and option (C) which a framework hover accent would share),
`design/ideas/new-components.md` (item 5, the motion prerequisite that needs splitting
into 1002-drag and 1003-hover; Tier 2 Split Layout; Tier 3 Tooltip),
`D_menu_bar` (open-on-hover, deferred on motion; and the "press-only, no
release" imprecision), `D_no_context_menu` (same, and the left-button-only
ruling), `D_extent` (hit-test the extent, not the rect),
`D_bg_surface` (`BG_STATES` is closed and framework-defined),
`D_theme_ref` (not a third colour channel), `D_inverse` (model the SGR rather
than faking it, if a non-background hover ink is ever wanted),
`D_attach_hooks` (the edge-trigger shape enter/exit must copy),
`D_hook_visibility` (a framework-invoked hook is protected, reached with
`__send__`), `D_tree_first` (why `hovered` belongs on `Screen`),
`D_progress_bar` (`sync_ticker` — how a hover-delay timer must be owned),
`D_background_rgb` (which thread may write to the terminal mid-loop — no longer
binding here, since the settled mode writes its escape once at loop start),
`D_status_bar` (`Screen#on_focus_changed=` as the app-channel precedent),
`D_bracketed_paste` (the other sanctioned PTY burst).
