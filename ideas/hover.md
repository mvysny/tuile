# Hover — motion events, `on_mouse_enter` / `on_mouse_exit`, and who paints the accent

**Status:** filed 2026-09-03, unmeasured. **Reframed the same day** — see *The
opt-in reframe*, which retires this note's first conclusion.

Three questions, and the plan is to answer them in that order rather than
together:

1. **Plumbing.** Enable motion tracking, parse the motion codes correctly, fire
   a move event — and *test it on real terminals* (vanilla Alacritty, over ssh,
   under tmux, tmux-over-ssh).
2. **Notices.** Derive enter/exit per component from the move stream.
3. **Ink.** *Then* decide, with the first two in hand: abandon the accent and
   let each app paint its own, do it for `MenuBar` only, or do it flatly for
   every component.

Step 3 is deliberately last and deliberately reversible: steps 1–2 are useful
on their own, and a framework accent can be added later but not removed.

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

`run_event_loop(capture_mouse: true)` is a Boolean today (`screen.rb:411`).
Two shapes:

- **(a) `capture_mouse: :motion`** — one knob, three values: `false`, `true`,
  `:motion`. `true` stays the default and becomes an alias for `:clicks`, so
  nothing breaks. The illegal state ("motion but no mouse capture") is
  *unrepresentable*, and symbol enums are house style already
  (`scrollbar_visibility=`, which also shows the discipline of refusing an
  `:auto`). **Lean: this one.**
- **(b) A second kwarg `track_motion:`** — reads more orthogonally than it is:
  motion without capture is nonsense, so it needs a guard and a raise, which is
  a rule where (a) has a type.

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

{Screen#run_event_loop} enables **mode 1000** only (`screen.rb:419` →
`MouseEvent.start_tracking`, `"\e[?1000h"`). Motion is a separate mode:

| mode | what arrives | who wants it |
|---|---|---|
| `1000` | press, release | today's clicks and wheel |
| `1002` | + motion **while a button is held** | Split divider, Slider drag, scrollbar drag |
| `1003` | + motion **always** | **hover**, open-on-hover, Tooltip |

**Hover needs 1003, drag needs only 1002, and they are not one prerequisite.**
`ideas/new-components.md` item 5 lumps them ("mouse motion/drag, modes
1002/1006"); split it when either lands. A drag flood is bounded — it lasts as
long as a button is down and the user is doing one deliberate thing. A 1003
flood is a report per cell crossed, unconditionally, including while the app is
idle and while the user is merely moving the mouse to a different window.

### The wire format (verified by reading)

{MouseEvent.parse} decodes `Cb = code + 32` and cases on the code
(`mouse_event.rb:51-59`). The X10 code layout is `button | 4 shift | 8 meta |
16 ctrl | 32 motion | 64 wheel`, so:

| event | code | `parse` gives today |
|---|---|---|
| left press | 0 | `:left` |
| wheel up / down | 64 / 65 | `:scroll_up` / `:scroll_down` |
| **release (any button)** | 3 | **`button: nil`** |
| motion, left held | 32 | `button: nil` |
| motion, no button | 35 | `button: nil` |

Two consequences:

- **No collision, so flipping to 1003 is safe today.** Motion codes 32–35 sit
  clear of the wheel's 64–67 (the `- 32` offset is applied first), so motion
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

### Where a move event goes — `kind:` on `MouseEvent`, not a second class

`MouseEvent` is the one mouse type and the one top-level constant in its file;
the other event classes are nested in `EventQueue`. Two shapes:

- **(a) A `kind` field** — `MouseEvent` gains `:press` / `:release` / `:move`,
  one class, one file, one parse site, and the `button: nil` overload dies. The
  cost is precise: `MouseEvent` is a `Data.define(:button, :x, :y)` constructed
  **positionally** at `mouse_event.rb:60` and in ~56 spec call sites, so a
  fourth field needs an `initialize` override defaulting `kind:` (the
  `PasteEvent` / `TTYSizeEvent` precedent) to keep three-arg construction
  working. Worth it.
- **(b) A separate `MouseMoveEvent`** — its own file per the
  one-top-level-constant rule, a branch in `Screen#event_loop`'s `case`, and a
  `Component#handle_mouse_move` sibling. More surface, and it splits one wire
  format across two parsers.

**Lean: (a).** A move is the same 6-byte report with a bit set; modelling it as
a different class models the wire wrong.

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
  bursts". 5 works *because* an X10 report is exactly 6 bytes. **Mode 1006 (SGR)
  reports are variable-length** (`\e[<35;12;34M`), so adopting it needs a drain
  rule of its own, like the `\e[?` and `\e]` loops beside it. And 1006 is hard
  to avoid: X10 packs a coordinate into one byte and so caps at 223. A dead
  click past column 223 is invisible; a hover accent that stops working on the
  right half of a wide terminal is a reported bug.
- **The queue coalesces repaints but not events** — and the arithmetic says
  that is fine. `event_loop` yields `EmptyQueueEvent` only when the queue is
  empty (`event_queue.rb:339`), so a flood defers the repaint to the drain,
  which is the right behavior for free. The theoretical failure is that if
  handling were slower than arrival the queue would never empty and the UI
  would stop repainting altogether — a freeze, not a trailing accent. **But
  default handling is a hit-test walk that ends in every component declining**:
  order ~100 `rect.contains?` comparisons, tens of microseconds, against ~160
  reports/s. Three orders of magnitude of headroom. The first draft called a
  mitigation "probably mandatory"; that was overstated. **Measure it to retire
  the question — and treat throttling, event collapsing and forced repaints as
  out of scope for this note.** If the number ever surprises us, that is a
  separate idea with the measurement to justify it.

### The terminal matrix — the actual deliverable of step 1

This is the part that cannot be reasoned about, and it is why step 1 exists
separately. Per environment — **vanilla Alacritty, Alacritty over ssh, tmux
local, tmux over ssh** (this session is the last one, so it is testable now) —
check:

1. **Does 1003 motion arrive at all**, and with what `Cb` codes?
2. **Event rate**: count reports for ten seconds of ordinary mouse movement,
   and time the handling of one. Expected verdict is "no mitigation needed";
   the point of measuring is to retire the question, not to justify a fix.
3. **Pointer leaves the window** — anything at all? (Expected: nothing. See
   *no reliable exit event*.) And does mode 1004 focus-out (`\e[O`) arrive?
4. **tmux with `mouse on` vs `mouse off`** — these are different paths: with
   mouse off tmux passes the bytes through, with mouse on tmux interprets them
   and re-emits to an app that requested tracking. Both need a row.
5. **tmux pane offset** — are coordinates pane-relative or window-relative in a
   split? tmux should translate; verify rather than assume.
6. **Does anything upstream coalesce?** If neither ssh nor tmux drops
   intermediate reports, the app is the only place it can happen.
7. **X10 vs SGR 1006** per environment, and behavior past column 223 (reachable
   in a full-screen tmux on a wide monitor).
8. **Latency, not bandwidth.** The first draft called ssh bandwidth a cost;
   that is probably wrong and should be measured rather than repeated — 6 bytes
   × ~160 reports/s is ~1 KB/s of payload, nothing. The plausible costs are
   **packet rate** (a 40-byte TCP header per report) and **round-trip latency**,
   which is what would make the accent visibly trail. tmux-over-ssh doubles the
   hops and adds tmux's own loop.
9. **Text selection.** Under 1003 the terminal's native drag-select is captured
   far more aggressively than under 1000 — which matters, because
   `capture_mouse:`'s rdoc already frames select-to-copy as the thing you trade
   away. Check whether Shift+drag still overrides it per terminal; that is the
   mitigation. If it does not hold everywhere, that is a fact for the mode
   switch's rdoc — an app opting in is trading more select-to-copy away than
   `capture_mouse: true` already trades — not an argument for scoping, which the
   opt-in model has settled.

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
They are the `on_attached` / `on_detached` shape from `D_attach_hooks`: **one
firing site, a fixed order, at most one call per component per transition.**

Order matters and must be picked deliberately: exit-then-enter (the DOM order)
means no component is ever hovered twice at once, which is what a driver
switching a menu panel wants.

### Where the state lives

Hover is one global position resolved to a component — the `Screen#focused`
shape exactly. `Screen` is the service and `ScreenPane` is the UI
(`D_tree_first`), and `focused=` lives on `Screen`, so: **`Screen#hovered`**,
plus a per-component `hovered?` mirroring `active?` (a component's own `repaint`
needs to know, if it paints anything).

### Which component is under the pointer — a rule the click path never needed

**There is no topmost rule for the tiled tree today.** `Component#handle_mouse`
hands a click to *every* child whose rect contains the point
(`component.rb:262`), so under `Layout::Absolute` with overlapping rects two
children both get it — fine for a click, incoherent for "the hovered one".
Three sub-rules to settle:

- **Popups first.** `ScreenPane#handle_mouse` already resolves topmost
  (`@popups.reverse_each.find`, `screen_pane.rb:237`), and hover *must* go
  through it: popups overdraw content with no clipping, so a component beneath a
  popup contains the point and is not visible.
- **Hit-test `extent_rect`, not `rect`.** A `Button` in a wide form column must
  not light up when the pointer is on the dead tail it does not paint. This is
  `D_extent`'s hit-testing consumer, and it is *cleaner* than the click case —
  clicks deliberately let the tail focus the widget while refusing to activate
  it, whereas hover has no focus half, so `extent_rect` applies without a
  carve-out.
- **Last-wins, or refuse?** For overlapping tiled rects, "last child in paint
  order" is the honest answer since that is what the user sees.

### Leaf or chain — the reframe flips this

The first draft leaned leaf-only, on the grounds that chain-hover would make a
`Window` tint whenever anything inside it is hovered. **That was an argument
against an automatic accent, not against chain notification** — and once opt-in
is the design, it evaporates: a `Window` that did not ask for hover paints
nothing, so notifying it costs nothing and enables the cases that want it (a
container reacting when the pointer is anywhere inside it).

So: **fire along the ancestor chain**, with enter/exit computed on the
*symmetric difference* of the two chains — which is what browsers do, and what
`focused=`'s `active=` walk already does for focus (`screen.rb:337-343`). The
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
  `Screen#on_focus_changed=` (`screen.rb:346`), the shape the deleted status bar
  was replaced with (`D_status_bar`). Cheapest, and enough for an app that wants
  to drive its own painting.
- **A protected hook pair** — `on_mouse_enter` / `on_mouse_exit`, overridden by
  a subclass, invoked via `__send__` per `D_hook_visibility`. This is what
  `MenuBar` open-on-hover actually needs.
- **A listener registry** — `on_mouse_enter { }` in the `on_value_change` style.
  No consumer yet asks for multiple subscribers.

Naming: `enter`/`exit` is the Swing pair, `enter`/`leave` the DOM one. Note
Tuile has `on_focus` and **no** `on_blur`, so an exit notice would be the
framework's first "leave" hook — and worth noticing *why* focus never needed
one (`active=` invalidates, and `on_focus_changed` covers the app), because if
hover paints nothing by default, the same argument may apply.

### There is no reliable exit event

Mode 1003 reports motion *inside* the terminal. A pointer that leaves the window
or crosses to another application sends nothing, so the last-hovered component
**stays hovered forever** and anything it painted strands. That is not an edge
case — it is how most mouse gestures end. Mitigations, all of which belong in
whatever ships:

- **Mode 1004 focus tracking** (`\e[?1004h`, `\e[O` on focus-out) to clear
  hover. Item 3 of the matrix exists to find out whether it actually arrives.
- **Any keystroke clears hover** — belt and braces, and cheap.
- A component's `on_detached` must clear it too, or `Screen#hovered` strands a
  reference to a detached component (the `@popup_prior_focus` failure mode).

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

## Open questions, collected

1. Is the hover target a flag on `Component`, or a component *kind* (a `Link` /
   non-focusable `Button`)? Related: should Tuile name the
   clickable-but-not-focusable idiom at all?
2. `kind:` field on `MouseEvent` vs. a separate `MouseMoveEvent`. (Lean: field.)
3. Chain or leaf for enter/exit. (Lean: chain, given opt-in.)
4. ~~Scoped 1003 vs. all-or-nothing at `run_event_loop`.~~ **Settled
   2026-09-03:** all-or-nothing, opt-in, off by default. Scoped tracking stays a
   later optimization if the measured rate demands it.
5. Does mode 1004 focus-out actually arrive in the four environments? If not,
   what clears a stranded hover besides a keystroke?
6. Exit-before-enter, or the reverse? (Lean: exit first, the DOM order.)
7. If step 3 lands as (A), does `on_mouse_exit` still earn its place — or does
   `Screen#on_hover_changed=` plus `hovered?` cover every consumer, the way
   `on_focus` needs no `on_blur`?
8. Overlapping tiled rects: last-in-paint-order wins, or refuse to resolve?
9. Anything stronger than docs for the silent no-op (hover hook overridden,
   mode off)?
10. Does open-on-hover need a `Ticker` delay, and is ~250 ms the number? See
    *the accessibility argument*.
11. Demo shape: a dedicated `examples/hover.rb` (lean — it keeps the sampler's
    PTY spec on the default profile) or a sampler pane that forces the whole
    sampler onto `:motion` to demo one pane?

## Related

`ideas/focus-accent.md` (the surface/accent line, the segment-vs-component
problem, and option (C) which a framework hover accent would share),
`ideas/new-components.md` (item 5, the motion prerequisite that needs splitting
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
