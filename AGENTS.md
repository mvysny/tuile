# AGENTS.md

Orientation for coding agents working on Tuile. Read this before making
changes; the architecture has invariants that are not obvious from any
single file.

**What belongs here — the gate.** An invariant earns a place in this file only
if it can be broken *from outside the file that implements it*. A rule you can
only violate while editing `float_field.rb` is already guarded by that file's
rdoc and its `D-` entry, both of which you are reading anyway. This file carries
what a contributor breaks by accident, at a distance: thread confinement, the
minimal-diff blanking rule, `add_child` / `parent=`, top-down layout, the key
ladder, `draw_text` as the background choke point, `emoji:` on every
`DisplayWidth.of`, one Zeitwerk constant per file — plus recipes for code that
does not exist yet (how a *new* `List` composer or `TextField` subclass must
behave). Per-widget behavior belongs in **rdoc** and its rationale in
**DECISIONS.md**; a widget's whole footprint here is usually one pointer line.
Apply the gate when you add a section, and again when a section you're editing
has grown past it.

## What Tuile is

A small component-oriented terminal-UI framework built on top of the TTY
toolkit (`tty-cursor`, `tty-screen`, `tty-logger`). Apps build
a tree of {Tuile::Component}s under a singleton {Tuile::Screen}; the
screen runs an event loop, dispatches keys/mouse, and repaints
invalidated components in batch. The name is French for "roof tile" —
small pieces that compose into a larger whole.

The gem was extracted from
[virtui](https://github.com/mvysny/virtui)'s `lib/ttyui/` in 0.1.0, so
references to virtui in commit history are expected.

The project is hosted at <https://github.com/mvysny/tuile>. The
underlying philosophy — composing UIs from small, encapsulated
components ("boxes within boxes") that talk via listeners and data
providers — is described in
<https://mvysny.github.io/component-oriented-programming/>. Tuile is
that approach applied to a TTY.

## Documentation kinds

Tuile's prose lives in seven kinds of document, each with a distinct
audience, length, and *what it is allowed to own*. Knowing which kind
you're writing keeps any one file from becoming the mixed bag the README
used to be (concepts + reference + quickstart fused). Match the target's
kind before you write a line.

| Kind | Audience | Scope & length | Owns |
|---|---|---|---|
| `ideas/*.md` | you + the author | dense, technical, provisional | design rationale *in flight*; transient (see graduation below) |
| **book** (`book/`, cover-to-cover) | a learner, reading in order | verbose, narrative, order-dependent | *concepts and the why* |
| **rdoc / YARD** (source headers) | someone at the API | dense, per-symbol, standalone | the precise technical workings of each class/method |
| **README** | a prospective user at the front door | thin: positioning + quickstart + a couple of examples + pointers | luring the reader in and routing them onward |
| **AGENTS.md** (this file) | a contributor / coding agent | invariant-focused; pointers, not reference | "what you must not break *from a distance*" — see the gate at the top |
| **DECISIONS.md** | a contributor asking "why this way?" | one coherent, mutable entry per live decision | the *why-we-chose*, incl. roads not taken |
| **CHANGELOG.md** | an existing user deciding whether/how to upgrade | one sentence per entry, append-only per release | *what changed* and *what you must do about it* |
| **TERMINOLOGY.md** | anyone who met a house word and wants its meaning | a glossary: one line per term, looked up by word | the *definitions* — and nothing else (no rationale, no invariants) |

Rules that make eight documents survivable:

- **Single source of truth per fact.** Each fact has one home; the
  others link to it rather than restating it. The book owns concepts;
  rdoc owns the per-symbol technical truth; the README owns pointers +
  quickstart; AGENTS.md owns cross-file invariants; DECISIONS.md owns the *why
  we chose it and not the alternative*. When tempted to explain something
  twice, link instead — and note the failure mode this file keeps hitting is
  compressing a `D-` entry into a bullet here, which reads like a summary and
  is really a third copy.
- **But don't over-link into unreadability.** A tiny, load-bearing
  restatement is fine when it saves the reader a jump — e.g. "Tuile is
  single-threaded by intent; see the book for why." The test: repeat the
  *one-line fact*, defer the *explanation*. Ten hops to assemble one
  mental picture is worse than one repeated sentence.
- **rdoc defers only *motivation* to the book, never *usage*.** It is
  browsed standalone on rubydoc.info by someone who won't click into a
  book, so it must carry the complete local technical truth of the
  symbol. "See the book for *why* layout is top-down" is fine; "see the
  book for *what* this method does" is not.
- **The book grows organically** — no target chapter count. Add a
  chapter when a concept has earned one (the threading model +
  background jobs; layout and why it's simple; theming), not to fill an
  outline. Tuile's conceptual surface is small; a short book is a
  finished book.
- **README stays a front door.** Positioning (what Tuile is, the
  alternatives comparison), install, one hello-world, a couple of
  example pointers, then links to the book and rdoc. Concepts migrate to
  the book; per-component API migrates to rdoc. The one catalogue it *does*
  own is the **Components** table — one line per component, grouped to match
  the book's own sections and linking into them — so **a new component owes it
  a row**, the fourth registration after rdoc, the CHANGELOG and the layout
  list above. Keep it a table of one-liners: the section used to be nine
  `###` per-component write-ups with code samples and "Key API" lists, which
  covered a third of the toolbox and had drifted into stating the opposite of
  what the code did.
- **A CHANGELOG entry is one sentence.** Lead with `Add` / `Fix` /
  `**Breaking:**`, name the symbol, say what changed — ≈40 words, and a
  trailing `See DECISIONS.md D-xxx` or book pointer doesn't count toward
  the cap. A **breaking** entry earns one *second* sentence, and only for
  what the caller must now *do* (the migration). Everything else — the
  rationale, the roads not taken, the measurements, the worked example,
  the "there is deliberately no X" — belongs in DECISIONS.md, rdoc or the
  book, and a changelog that restates them is the single-source rule
  broken in the file nobody re-reads. Group a release's entries `Add`,
  then `Fix`, then `**Breaking:**`. The one sanctioned narrative is a
  **≤3-sentence preamble** under a themed release's version heading
  (0.9.0's top-down layout note is the model) — once per release, never
  per entry. 0.1.0–0.3.0 show the target register.

**The graduation pipeline.** `ideas/*.md` is transient by design — a
scratchpad "for the two of us," not user docs. It is still a vital part
of the mechanism: it's where rationale is born. On graduation — once the
idea is implemented and stable — it *moves* to its final destinations and
the `ideas/` note is retired: the **user-facing half** graduates into the
book (rewritten for the reader), the **decision half** — the choice made and
the alternatives rejected — graduates into DECISIONS.md (which may already
carry an entry recorded when the decision was *made*, ahead of
implementation), and the **must-not-break half** graduates into rdoc, or into
AGENTS.md only for the part that clears the gate above. Most of it doesn't:
a new widget's rules are per-symbol, so its rdoc is the destination and this
file gets a pointer. The v0.9.0 top-down layout overhaul is the worked example
of a full run — `ideas/simpler-layouting.md` → book ch3 + the "Layout is
top-down" section below + `D-*`, note retired.

## Layout

```
lib/tuile.rb                       gem entry point: requires, Zeitwerk loader
lib/tuile/version.rb               VERSION constant
lib/tuile/keys.rb                  Tuile::Keys (key constants + .getkey)
lib/tuile/{point,size,rect}.rb     geometry value types (Data.define)
lib/tuile/fraction.rb              Tuile::Fraction (width/height ratio; resolves against a Size — Popup sizing only)
lib/tuile/mouse_event.rb           Tuile::MouseEvent (parses xterm sequences)
lib/tuile/ansi.rb                  Tuile::Ansi (escape constants — RESET, BEL, the synchronized-output pair)
lib/tuile/color.rb                 Tuile::Color (named/256-palette/RGB; .palette/.rgb/.hex factories, .coerce, xterm-named palette constants)
lib/tuile/styled_string.rb         Tuile::StyledString (span-based styled text: parse/slice/wrap/truncate)
lib/tuile/theme.rb                 Tuile::Theme (semantic color tokens; DARK/LIGHT, current one at Screen#theme)
lib/tuile/theme_def.rb             Tuile::ThemeDef (app theme definition: dark/light Theme pair at Screen#theme_def; ThemeDef.default seeds new screens)
lib/tuile/terminal_background.rb   Tuile::TerminalBackground.detect (OSC 11 + COLORFGBG light/dark probe)
lib/tuile/event_queue.rb           Tuile::EventQueue + nested events
lib/tuile/fake_event_queue.rb      synchronous test double
lib/tuile/component.rb                  Tuile::Component base
lib/tuile/component/has_content.rb      mixin for one-child containers
lib/tuile/component/has_value.rb        mixin: the value seam (value/empty?/clear/on_value_change) + focusable? default
lib/tuile/component/has_caption.rb      mixin: the StyledString caption seam (chrome text)
lib/tuile/component/label.rb            Tuile::Component::Label
lib/tuile/component/button.rb           Tuile::Component::Button
lib/tuile/component/checkbox.rb         Tuile::Component::Checkbox — one-row boolean input
lib/tuile/component/checkbox_group.rb   Tuile::Component::CheckboxGroup — multi-select over a List; Set-valued
lib/tuile/component/radio_group.rb      Tuile::Component::RadioGroup — single-select over a List
lib/tuile/component/layout.rb           Tuile::Component::Layout (+ Absolute; nests the Fixed/Percent/Expand constraints and Insets)
lib/tuile/component/layout/box.rb       Tuile::Component::Layout::Box — abstract 1-D pass + the shared placement arithmetic
lib/tuile/component/layout/vertical.rb  Tuile::Component::Layout::Vertical — main axis is height
lib/tuile/component/layout/horizontal.rb  Tuile::Component::Layout::Horizontal — main axis is width
lib/tuile/component/list.rb             Tuile::Component::List — items + a renderer, lazily rendered (+ Cursor / None / Limited)
lib/tuile/component/abstract_string_field.rb  Tuile::Component::AbstractStringField (abstract; String-valued base of TextField/TextArea)
lib/tuile/component/text_field.rb       Tuile::Component::TextField — horizontally scrolling one-line input
lib/tuile/component/password_field.rb   Tuile::Component::PasswordField — TextField masking via display_text
lib/tuile/component/text_area.rb        Tuile::Component::TextArea — multi-line editor over a wrap + viewport
lib/tuile/component/text_area/wrapped_text.rb  Tuile::Component::TextArea::WrappedText — private (text, width) wrap snapshot + index↔row/column
lib/tuile/component/text_view.rb        Tuile::Component::TextView (read-only scrollable wrapped prose)
lib/tuile/component/combo_box.rb        Tuile::Component::ComboBox — filtering dropdown; a TextField + a ListDropdown
lib/tuile/component/list_dropdown.rb    Tuile::Component::ListDropdown (+ Menu) — non-focusable Popup-over-List; owns placement (anchor_to)
lib/tuile/component/select.rb           Tuile::Component::Select — the enum field: own-painted face over a ListDropdown
lib/tuile/component/integer_field.rb    Tuile::Component::IntegerField — typed Integer/nil input over a TextField
lib/tuile/component/float_field.rb      Tuile::Component::FloatField — typed Float/nil input; IntegerField's deliberate copy
lib/tuile/component/big_decimal_field.rb  Tuile::Component::BigDecimalField — typed BigDecimal/nil input; the optional bigdecimal gem
lib/tuile/component/progress_bar.rb     Tuile::Component::ProgressBar — display-only fill over a Range; owns a Ticker
lib/tuile/component/menu_bar.rb         Tuile::Component::MenuBar (+ Item) — one-row caption strip driving a cascade of submenus; the strip plus the item tree
lib/tuile/component/menu_bar/cascade.rb  Tuile::Component::MenuBar::Cascade — private: the stack of open ListDropdown panels; drill / pop / activate
lib/tuile/component/tabs.rb             Tuile::Component::Tabs (+ Tab) — one-row caption strip, one selected; owns no content
lib/tuile/component/tab_sheet.rb        Tuile::Component::TabSheet — a Tabs strip plus the selected tab's pane; hides by detaching
lib/tuile/component/window.rb           Tuile::Component::Window (border + content slot)
lib/tuile/component/popup.rb            modal overlay, sized via `size=` (Size | Fraction), ESC/q closes
lib/tuile/component/notification.rb     Tuile::Component::Notification — corner toast; `show` is the only ctor, one box, one ticker drains it
lib/tuile/component/info_window.rb      window-of-static-lines convenience (tiled or popup)
lib/tuile/component/picker_window.rb    single-keystroke option picker
lib/tuile/component/log_window.rb       Tuile::Component::LogWindow + IO adapter for tty-logger
lib/tuile/vertical_scroll_bar.rb        character-grid scrollbar (rendering helper, not a Component)
lib/tuile/buffer.rb                     Tuile::Buffer (+ Cell) — back buffer of styled cells; flushes the minimal diff
lib/tuile/screen.rb                     Tuile::Screen (singleton runtime)
lib/tuile/fake_screen.rb                in-memory test double
lib/tuile/screen_pane.rb                structural root of the component tree (kept at root, owned by Screen)

spec/tuile/**/<file>_spec.rb       mirrors lib/tuile/**/<file>.rb — one spec
                                   per source file (mostly; version.rb has none,
                                   and a few internals like has_content / fake_*
                                   are still uncovered)
spec/examples/<file>_spec.rb       PTY-based system tests for examples/ scripts
spec/spec_helper.rb                requires "tuile", uses minitest assertions
sig/tuile.rbs                      RBS signatures (sord-generated; `rake sig` regenerates)
```

Zeitwerk loads everything from `lib/`. Source files are wrapped in
`module Tuile` and don't `require_relative` each other — Zeitwerk
resolves constants on first reference.

## Core architecture (must-know)

### Singleton Screen (the machinery), ScreenPane (the UI)

The split is load-bearing, and it maps onto Vaadin: **`Screen` is the
service** — event queue, thread ownership, terminal IO, back buffer,
invalidation set, theme detection — and it **stays out of the tree**.
**`ScreenPane` is the `UI`**: the root of the component tree, and what
*defines* attachedness (`attached?` is `root.is_a?(ScreenPane)`, one axis, no
`Screen` consulted). Keep new machinery on `Screen` and new tree semantics on
`ScreenPane`; don't let either drift into the other (`D-tree-first`).

`Tuile::Screen` is a process-singleton. It owns the event queue, the
"UI lock", invalidation set, terminal IO, and a single
{Tuile::ScreenPane}. *All* UI lives under that pane:

```
ScreenPane            (structural root, never paints anything)
├── content           (tiled Component, optional — usually a Layout::Absolute)
├── popups[0..n]      (modal stack, last is topmost)
└── status_bar        (Component::Label, bottom row)
```

Putting popups under the same parent as content means focus traversal,
`Component#attached?`, and `on_child_removed` work uniformly without
special-casing popups.

### Component tree

Every UI piece is a {Tuile::Component} with `parent` / `children`,
`rect`, `active?`, `focused`. Two derived APIs:

- `depth` / `root` — distance to root and root pointer
- `on_tree { |c| … }` — pre-order traversal of self + descendants
- `attached?` — true iff `root.is_a?(ScreenPane)`. **One axis: the parent
  chain, and nothing else.** It consults no `Screen`, so it never raises and
  a tree can be assembled with no screen in the process (guarded by a spec).
  Don't reintroduce `root == screen.pane`: reading a mutable pointer inside
  the singleton made `Screen#close` silently mass-detach every tree and made
  `Screen.instance` a prerequisite for asking the question (`D-tree-first`).
  The corollary `Screen#close` now owes: it must *unmount* the tree, since
  nilling `@pane` alone would leave every component claiming to be attached.

`children` is read-only by convention (the array must not be mutated by
callers; containers expose `add` / `remove` / `content=` / `footer=` to
swap and reparent).

**Hiding a component means *detaching* it.** There is no `Component#visible?`
and no `display` flag. The empty rect is a *paint* convention — it gates
`repaint` and nothing else — so an "invisible" component with an empty rect is
still in the Tab cycle, still a target of the focus cascades, still answers
`cursor_position` and `keyboard_hint`, and still sees bubbled keys.
{Tuile::Component::TabSheet} therefore hides its unselected panes by keeping
them *out of the tree*, which is also why `on_attached` / `on_detached` fire on
every tab switch. **Re-grow rule:** a `visible?` flag may come back only when a
second consumer needs one, and only argued as a *focus-and-paint gate*
(`cycle_focus`, both cascades, cursor, hint, repaint) with an explicit ruling on
whether `Box` / `Absolute` skip invisible children when dividing space — never as
a paint-time flag smuggled in under one component (`D-tabs`).

**`children` is final, and reparenting goes through
`Component#add_child(child, at:)` / `#remove_child(child)` /
`#detach_child(child)`** — protected mutators that write the `@children`
array *and* the parent pointer in one call. Invariants:

- **Never override `children`, and never hand-wire `child.parent = …`.**
  `attached?` walks the **parent chain** while subtree walks use
  **`children`**, and the attach/detach hooks will fire from `parent=`, so a
  container that derived `children` from its own slots could disagree with
  the pointers and fire hooks for the wrong set (`D-tree-api`). `parent=`
  stays `protected` rather than private only because Ruby can't dispatch a
  private writer through the explicit receiver `add_child` needs — it is not
  an invitation. `component_spec`'s "keeps children, @children and the parent
  pointers in agreement" walks a tree of every container kind and is the
  guard.
- **Named slots are readers *over* the array, never a second copy.**
  `Window#footer` / `HasContent#content` hold the object; the array holds the
  order. The one exception is `ScreenPane#popups`, which duplicates ordering
  for a *list* slot — bounded to its two mutators and pinned by a drift
  assertion, because every way of deriving it is worse (`D-tree-api`).
- **Order is maintained at insert, so the index is part of the contract.**
  Content goes in at `at: 0` and chrome appended, which is why a `Window`
  paints content-then-footer whichever is assigned first; a popup inserts at
  `at: @children.index(@status_bar)`, naming its anchor rather than assuming
  a position. Both are specced — changing an insert index changes paint and
  Tab order.
- **`parent=` is the sole firing site for `on_attached` / `on_detached`**, and
  it is provably sole: `add_child` / `detach_child` are its only callers.
  Attachedness is measured before and after the pointer write, so reparenting
  inside an attached tree fires nothing and building a detached tree fires
  nothing. Don't move the firing into the mutators or the containers — the
  whole point is one site with one correct order.
- **Hard guarantees the hooks rest on.** `attached?` is `true` throughout
  `on_attached` and `false` throughout `on_detached` (the pointer is written
  first), which is what makes an `invalidate` in the former land and the same
  call in the latter a silent no-op. And *at most one* call per component per
  transition, whatever the hooks do to the tree — `fire_lifecycle`'s two guards
  own that, and its rdoc owns why neither can go (`D-attach-hooks` records the
  rejected `parent.equal?(self)` re-check).
- **What a hook may *not* assume:** no geometry (`on_attached` runs before the
  parent assigns `rect`); `Screen#focused` may still point into a subtree being
  detached (repair runs after); and the ex-parent may be mid-bookkeeping. Hooks
  release resources and don't inspect the tree around them.
- **A raising hook propagates** and leaves the tree in an undefined state; on
  the *detach* path that is durable (the container's remaining work is skipped).
  A raising hook is a bug to fix, not something the framework guards. Keep hooks
  trivial.
- **A hook-owned resource is synced from an invariant, not toggled by the
  hooks.** Write the condition the resource must satisfy (`attached? &&
  indeterminate?`) and make every mutation site call one idempotent sync that is
  the sole writer. Start-in-`on_attached` / cancel-in-`on_detached` — what the
  `on_attached` rdoc example shows — is correct only while *nothing else* can
  change whether the resource is wanted; a third mutation site turns the two
  hooks into a 2×2 the naive pair silently gets half wrong.
  {Tuile::Component::ProgressBar#sync_ticker} is the worked example.
- **`Screen#close` unmounts the tree, so teardown *does* fire `on_detached`** —
  via `ScreenPane#detach_all`, which detaches every child (chrome included) and
  empties the pane's slots. But **a process that exits *without* calling `close`
  fires nothing:** these are lifecycle hooks, not destructors, and there is no
  `at_exit`. Don't add one — the hooks exist so a component can own a
  mounted-lifetime resource, and the OS reclaims everything at exit anyway
  (`D-attach-hooks`).
- **`detach_all` is deliberately not generic.** No `Component#remove_all_children`:
  a slot container calling it would empty `@children` while `#content` / `#footer`
  still pointed at detached components — the desync the tree API prevents. And
  not named `close`, since `Popup#close` already means "remove *me* from the pane".
- **A slot swap detaches without notifying, and notifies last.**
  `detach_child` + rewire + `on_child_removed(old)` — because the default
  focus repair cascades into whatever occupies the slot *now*, so it must see
  the new occupant (`window_spec`: replacing content lands focus on the new
  content). `remove_child` is `detach_child` + notify, for the cases with no
  slot to refill.

### Invalidation + repaint (read this twice)

Components do **not** paint immediately, and they do **not** write
escape sequences to the terminal. They call `invalidate` (a protected
method that records `self` in `Screen#@invalidated`), and when they do
paint they write styled cells into `Screen#buffer` (a {Tuile::Buffer}
back buffer) via `set_text` / `fill` / `set_char` — never `screen.print`.
After an event-loop tick drains the queue, `Screen#repaint` walks the
invalidated set:

1. Partition into tiled-tree and popup-tree (popup-tree = anything
   reachable from `pane.popups`).
2. Sort tiled by depth (parent before child).
3. If any tiled were invalidated, re-paint *all* popup subtrees on top
   in stacking order — popups deliberately overdraw content, no
   clipping. Overdraw into the buffer is free: only net-visible changes
   reach the wire.
4. Flush the buffer — `Buffer#flush` emits the **minimal diff** (only
   cells that changed since the last flush) plus the cursor position,
   wrapped in one synchronized-output batch ({Ansi::SYNC_BEGIN}). This is
   what makes repaint flicker-free on any terminal regardless of mode-2026
   support: an unchanged cell is never rewritten. The cursor lands on the
   *focused* component's `cursor_position` (hidden when none).

`Screen#emit` is the single sink for the assembled frame; {Tuile::FakeScreen}
overrides it (and `print`) to capture into `prints` instead of stdout, and
exposes the populated `buffer` for assertions (`row_text` / `row_ansi` /
`region_text` / `region_ansi` / `cell`).

**Invariants you must preserve:**

- A component must not draw outside its `rect`.
- It is *not* required to
  fully tile its rect: {Tuile::Component#repaint}'s default clears the
  background whenever the direct children leave gaps in `rect` (e.g. a form
  layout with mixed-width fields), and re-invalidates those children
  **whether or not they tile**. Subclasses should `super` from their own
  `repaint` to inherit that behavior; only components that paint their entire
  rect themselves (currently {Tuile::Component::Window} for
  border-plus-content, and {Tuile::Component::List} for explicit row-by-row
  paint) opt out.
- **The re-invalidation is a *cascade*, and a container must never dead-end
  it.** A clearing container wipes its **whole** rect — every descendant's
  cells, not just the gaps — but notifies only its *direct* children, so the
  notice has to keep travelling down. A container that paints nothing of its
  own therefore has to re-invalidate its children even when they tile it
  perfectly, or the grandchildren under a cleared ancestor are never
  repainted and their content silently vanishes until the next unrelated
  repaint. This is why the tiling case skips the *clear* but not the
  *invalidate*; `component_spec`'s "re-invalidates its children even when
  they tile" and `tab_sheet_spec`'s "keeps the pane painted when the strip
  takes focus" are the guards (`D-repaint-cascade`).
- **Never blank a cell you are about to paint over — that is what makes the
  minimal diff minimal.** `Cell#set` flips the dirty flag only on a real
  content change, so `clear_background` + paint-the-same-glyph marks the cell
  dirty anyway and `flush` re-emits it. Harmless for a static widget (a
  {Tuile::Component::Checkbox} genuinely needs the clear for the dead tail past
  its `extent`), decisive for an animated one: `super` from
  {Tuile::Component::ProgressBar}'s `repaint` re-emitted its *entire* row five
  times a second instead of the one or two cells that moved (`D-progress-bar`
  has the measurement). A component that paints part of its rect passes the rest
  to `clear_background(area)` and skips `super`.
- Don't call `Screen#repaint` directly from a component; just
  `invalidate` and let the loop coalesce.
- **A one-row caption widget highlights and hit-tests its *extent*, not its
  `rect`** — a form column routinely hands a field a rect far wider than the
  glyph, and a click on the blank tail must not activate it (the tail still
  *focuses*: click-to-focus is ungated by geometry). `extent` is deliberately
  *not* a `Component` method; each widget's arithmetic is its own, and
  `D-boolean-fields` owns both that and the rule that the extent must not vary
  with `bg_color`. A checkable row inside a {Tuile::Component::List} is the
  other case: it hit-tests its full width, never past the last painted row.

### Threading rule (the load-bearing one)

**The UI is confined to one thread at a time. While an event loop runs
that is the loop's thread; when none runs it is the thread that created
the `Screen`.** So an app assembles its tree on its own thread, hands
ownership to the loop for the duration of `run_event_loop`, and gets it
back for teardown. *All* UI mutations — `rect=`, `active=`, `content=`,
`items=`, `invalidate`, `screen.focused=` — obey it, and violating it
raises {Tuile::Error}.

**Enforcement is mostly *transitive*, and a new component should not add
its own guard.** `Screen#invalidate` calls `check_locked`, and
`Component#invalidate` reaches it whenever the component is attached — so
any mutator ending in an `invalidate` is already protected, which is
almost all of them (`Layout#add`, `Box#spacing=`, `Component#rect=`,
`Label#text=`, `List#lines=` … none call `check_locked` themselves). The
same early return when *detached* is what lets a tree be assembled with no
`Screen` in the process at all. Only a handful of component-level call sites are
explicit — `grep -rn 'check_locked' lib/tuile/component` lists them — and they
are fail-fast exceptions: methods that do
substantial work *before* reaching `invalidate` and would otherwise
corrupt state and then raise. Don't read "most UI methods call
`check_locked`" as an instruction to sprinkle it; `box_spec`'s "thread
confinement, inherited through invalidate" context pins the real
mechanism.

Invariants:

- **The loop need not run on the creating thread**, and the gem's own
  specs rely on that (`screen_spec`'s `with_real_screen` drives
  `event_loop` from a spawned thread). So `check_locked` must keep asking
  *two* questions — `EventQueue#running?` (is a loop active anywhere) and
  `#on_loop_thread?` (is it mine) — and fall back to the creating thread
  only when no loop runs. Collapsing it to a single "must be the creating
  thread" identity check breaks that pattern.
- **`event_queue.submit` only *runs* the block while a loop is draining
  the queue.** Before the first loop it defers (fires once the loop
  starts); after the loop returns it never runs at all — `run_loop`'s
  `ensure` clears the queue. That's why `check_locked`'s two failure
  messages differ: advising `submit` when no loop is running is advising a
  silent no-op. Don't unify them.
- **There is no `@pretend_ui_lock` and no lock-bypass in the fake.**
  Both are deleted: `FakeEventQueue#running?` is `false` (it never runs a
  loop), so the *real* `check_locked` admits the example thread on its own
  — a spec that mutates UI from a spawned thread raises, exactly as an app
  would. Don't re-add a `FakeScreen#check_locked` override.
- **A background thread can still slip through** by reading `running?` as
  false in the instant before the loop starts. Inherent, and `:idle` is
  single-threaded by construction (the app hasn't spawned anything yet, or
  has already joined it). Don't chase it.

`Screen#@@instance` is a class variable — the singleton survives
sub-classing (`FakeScreen < Screen`).

### Screen lifecycle states

`Screen#state` is `:idle` → `:running` → `:idle` → … → `:closed`, derived
(no stored phase beyond `@closed`):

- **`:idle`** — no loop running. Deliberately covers *both* ends of the
  screen's life, before the first `run_event_loop` and after it returns,
  because mutation rules are identical there. Don't split it into
  `building`/`stopped`: that would mean storing a flag to distinguish two
  states with the same rules, which invites a rule that shouldn't exist.
- **`:running`** — a `run_event_loop` is in progress. `:idle ⇄ :running`
  may cycle more than once; nothing depends on it, so it isn't guarded.
- **`:closed`** — terminal. The only state that changes *what* is legal:
  `check_locked` refuses everything, so components inherit the clear
  "Screen is closed" error for free.

Consequences to preserve:

- **The states are orthogonal to thread confinement.** Mutation legality
  is the same in `:idle` and `:running` (whoever owns the UI now), so the
  states never gate affinity — `:closed` is the sole exception.
- **A new `Screen`-level forwarder calls `check_locked` itself** rather than
  relying on the `ScreenPane` method it delegates to: after `close` there is no
  pane to forward to, and `NoMethodError for nil` is a bad error message.
  `Screen#content=` is the pattern.

`screen.rb`'s own rdoc carries the rest — `close`'s idempotence and its refusal
from `:running`, and why `run_event_loop`'s guard sits outside its
`begin`/`ensure` (both specced).

### Focus + shortcuts

`screen.focused = component` walks `parent` upward and marks the entire
chain root → focused as `active?`, deactivating everything else. The
flag is universal: every component carries it, but only components on
the current focus chain ever have it set true. Then `component.on_focus`
fires and the status-bar hint is rebuilt. Setting `nil` deactivates
everything.

`Component#focusable?` is independent of the active flag: it gates
*becoming* a focus target. Click-to-focus (`Component#handle_mouse`) and
the on_focus cascade in `HasContent` / `Layout` only forward focus to
focusable components, so clicking a {Tuile::Component::Label} doesn't
hijack focus from the surrounding window.

#### The key-dispatch ladder

A keystroke descends a **fixed priority ladder** of exactly three rungs.
Nothing about it is negotiated per component, and there is no gate, no
predicate and no mode flag anywhere in it:

```
Screen#handle_key
├─ 1. TAB / SHIFT_TAB  focus_next / focus_previous. Unconditional — no
│                      component ever sees Tab, not even a TextArea.
├─ 2. @global_shortcuts app-level registry (#register_global_shortcut).
│                      Printable keys, TAB/SHIFT_TAB and Screen::EDITING_KEYS
│                      raise at registration. Gated by over_popups vs. a
│                      modal popup.
└─ 3. DELIVERY         ScreenPane#handle_key → bubble_key, scoped to the
                       topmost modal popup or else the tiled content:
                       screen.focused, then up its ancestor chain to the
                       scope root; first handle_key returning true wins.
```

Invariants:

- **Tab is absolute.** It is claimed above everything, so focus can never
  be trapped inside a component that swallows it. Don't add a Tab handler;
  the registry rejects Tab bindings for the same reason.
- **The registry is the only mechanism above the tree, and nothing
  suppresses it** — so it must only ever accept keys no widget can need.
  That's why it rejects printables *and* `Screen::EDITING_KEYS` (`ENTER`,
  `BACKSPACE`, `DELETE`, the arrows) at registration. Adding a runtime gate
  here instead would re-create the wart `D-key-dispatch` deleted; if a new
  key turns out to be needed by every editable widget, reserve it, don't
  gate it.
- **Delivery bubbles *up*, and the scope root bounds it.** Ancestors see a
  key only after every descendant on the focus chain declined it. This is
  the *only* place scope-wide keys belong — a form's default button, or a
  layout's one-key jumps to its panes — and it needs no protection against
  hijacking typing, because a focused {Tuile::Component::TextField}
  consumes the key before the ancestor sees it. There is deliberately
  **no downward delegation**: neither `Layout#handle_key` nor
  `Window#handle_key` exists, and re-adding one would double-dispatch
  against the bubble.
- **There is no framework-level jump-to-widget mnemonic.**
  `Component#key_shortcut`, `find_shortcut_component` and the capture phase
  that scanned the scope subtree were **deleted** in 0.10.0 (`D-key-dispatch`),
  along with `Window`'s `[k]-Caption` border prefix. Do not reintroduce them:
  capture-before-delivery is what forced the cursor-ownership gate to exist,
  and the bubble subsumes the feature with better semantics (per-popup scope,
  free suppression, no lifecycle bookkeeping). An app wanting `1`/`2`/`3` to
  jump between panes writes a `handle_key` on its content layout. **Re-grow
  rule:** if the pattern proves ubiquitous, bring it back as *sugar over an
  ancestor's `handle_key`* (e.g. a `mnemonics` hash on `Layout`), never as a
  dispatch phase and never with a gate.
- **`Screen#cursor_position` is about the cursor only.** It says where to
  park the hardware cursor and nothing else; it is not a routing signal.
- **A component receives keys only while on the focus chain**, so
  `handle_key` must act on the key alone and never gate on its own
  `active?` state.

#### Paste rides its own path, beside the ladder

A paste is not a keystroke, and the whole mechanism exists to keep it from
becoming one (`D-bracketed-paste`; book ch5 for the *why*, the `Keys` and
`Component#handle_paste` rdoc for the API). `Screen#run_event_loop` enables DEC
mode 2004, the key thread turns `\e[200~`…`\e[201~` into one
`EventQueue::PasteEvent`, and `Screen#event_loop` routes it to
`Component#handle_paste` down the focus chain — same scoping as a key, none of
the rungs. Invariants:

- **Never route pasted text back through the ladder, and never replay it as
  keys.** Both re-create the ambiguity the mode removes: a `pasted?` flag on
  `KeyEvent` would put a runtime gate back on dispatch (`D-key-dispatch`), and a
  replay-when-unhandled fallback would hand a declining component eight ENTERs.
  Unhandled paste text is dropped.
- **`Keys.read_paste` must not loop on `Keys.getkey`.** A pasted `\e` would send
  the 5-byte gulp eating clipboard as an escape tail — the `\e[M` / `\e[?`
  failure one level up. It reads a byte at a time to the terminator, and a
  chunked read is equally wrong: it would over-read past `\e[201~` and swallow
  the keys typed behind the paste.
- **Two sanitizing layers, and the line between them is deliberate.**
  `Keys.normalize_paste` fixes *terminal* artifacts only (CR/CRLF → `\n`,
  UTF-8 scrub); what a *text buffer* may hold is the field's
  `preprocess_paste`. A new sanitization goes in whichever layer owns the
  reason, never both.
- **A new component overriding `handle_paste` gets the whole clipboard, once.**
  Insert it as one mutation — a per-character loop puts back the O(n)
  `on_change` storm that composing this event removed.

### Popup focus repair

When a popup closes, focus must land somewhere reasonable. The order
implemented in {Tuile::ScreenPane#on_child_removed}:

1. The now-topmost remaining popup, if any.
2. The focus snapshotted just before this popup was added — *if it's
   still attached*. Snapshots are stored in `@popup_prior_focus`.
3. The tiled `content`.
4. `nil`.

If a non-topmost popup closes while focus is in the topmost, focus is
left untouched, but `@popup_prior_focus` is rewritten so any popup that
remembered a focus *inside* the just-closed popup forwards to the
closing popup's own prior. This prevents stranded references to
detached components when popups close out of order. {Tuile::ScreenPane}
spec has the regression cases — read them before refactoring this.

### Non-modal overlays — two traps a *new* one will hit

A `Popup.new(modal: false)` is exempted from focus-grabbing, key scoping and
click-blocking, and both existing ones ({Tuile::Component::ListDropdown},
{Tuile::Component::Notification}) had to defuse the same two hazards. A third
will too; `D-notification` owns the reasoning.

- **It must not be focusable, and declaring that is not enough.**
  `Popup#focusable?` is `true` and `ScreenPane#handle_mouse` routes an in-rect
  click to the topmost popup containing it — so a click lands
  `Component#handle_mouse`'s `screen.focused = self` *inside a subtree that is
  not the key scope* (`modal_popup || content`). `bubble_key` then delivers to
  nobody and **every keystroke goes dead** until Tab recovers. So override
  `focusable?`/`tab_stop?` to `false` **and** override `handle_mouse`: without
  the second, the click is merely swallowed and the content beneath never sees
  it. Notification spends it on click-to-dismiss; the `handle_mouse` override
  must *replace*, never `super` or fall through to `HasContent#handle_mouse`
  (both end at the same focus assignment, one level down).
- **A *derived* position needs its own `reposition`.** `Popup#reposition` runs
  every layout pass and, for a non-modal popup, re-resolves the size while
  keeping the caller-assigned `rect.left`/`top`. Correct for an overlay someone
  placed by hand; wrong for anything computed from the screen or an anchor —
  after a SIGWINCH it sits at the stale column, off-screen entirely if the
  terminal narrowed. Override it and recompute the anchor there (Notification
  also rebuilds its content there, since its wrap width *is* its box width).
  **Closing is the other legal answer**, and {Tuile::Component::MenuBar} takes
  it: a cascade's panels are anchored to a strip segment *and* to each other, so
  re-anchoring means walking every level in depth order — the bar closes the
  cascade from its `rect=` instead. Don't "fix" that into a `reposition`
  override.

### Resize

Terminal resize is plumbed through the event queue, not handled
directly off the signal. `EventQueue#trap_winch` installs the sole
`SIGWINCH` handler and posts an `EventQueue::TTYSizeEvent` (carrying
the new `width` / `height`). `Screen#event_loop` catches it, assigns
the event to `Screen#size`, and runs `layout`, which resizes
`pane` to `(0, 0, size.width, size.height)`, invalidates the entire
tree, and repaints.

**React to resize via the normal invalidation path** — i.e. let your
parent reassign your `rect`, and recompute child layout in `rect=`.
Do **not** add your own `Signal.trap("WINCH")` in component code; only
one handler can win, and `EventQueue` owns it. If a component needs to
read the current viewport directly, use `Screen.instance.size` (seeded
at construction from `TTYSizeEvent.create`, so it's valid before the
first WINCH ever fires).

### Layout is top-down — no bottom-up sizing channel

**A component never advertises how big it wants to be; its parent
assigns its `rect`.** There is no `content_size`, no `Sizing` policy
type, no `min`/`preferred`/`max`, and no shrink-to-fit. A container
computes its children's rectangles in plain Ruby (in its `rect=`
override) and hands them down; content fills or scrolls within the rect
it's given. The book's chapter 3 is the long-form *why*.

This was an overhaul (v0.9.0): the earlier eager bottom-up
`content_size` channel — the reader, the protected `content_size=`
setter, and the `on_child_content_size_changed` parent hook — was
**deleted** along with `Sizing` and Popup content-auto-sizing. Do not
reintroduce it. **Re-grow rule:** if a genuine need to size against
content returns, bring it back as an *optional, read-only, caller-side
query* — "measure this so *I* can compute a rect and set it top-down" —
never as an automatic channel the framework consults. That keeps
measurement opt-in and top-down, which is what stops it re-becoming
`min`/`preferred`/`max`. (TextView specs probe `@lines.size`
directly for this reason — there is deliberately no public size getter.)

Two consumers that used to sit on that channel are now top-down:

- {Tuile::Component::Popup} sizes itself from `Popup#size=`
  (`Size | Fraction`, default `Fraction::HALF`, resolved against the
  screen each layout) — never from its content.
- The {Tuile::Component::Window} bottom border carries two purpose-fit members
  rather than one sized slot — `footer_text=` (border chrome, mirroring
  `caption` on top) and `footer=` (a focusable component spanning the inner
  width). Their precedence is in `window.rb`'s rdoc; what matters here is that
  a bottom-row widget is FILL by construction, so the footer never drives
  window size and one that doesn't fit is clipped.

#### Box layouts are sugar *over* that rule, not an exception to it

{Tuile::Component::Layout::Vertical} / `::Horizontal` (both on the abstract
`::Box`) let a caller declare each child's extent instead of computing it.
The whole design turns on staying additive — a `Box` is an `Absolute`
subclass with a `rect=` override, so it introduces no dispatch phase, no
framework hook and no child consultation, and could be deleted without
touching the foundation. Why each choice, and the roads not taken:
`D-box-layouts`. Usage: the `Box` rdoc and book ch3. Invariants:

- **There is no `Auto`, and adding one would reopen v0.9.0.** The
  vocabulary is `Fixed` / `Percent` / `Expand` — all parent-side
  arithmetic. Shrink-to-fit / `Pack` / `PREFERRED_SIZE` is the deleted
  bottom-up channel; the re-grow rule above still governs.
- **`align:` is legal only because the cross extent is caller-supplied.**
  Alignment needs *a* width, not *the child's* width — so it never
  measures. Never add an alignment that derives its own size; that is
  `Auto` by another name.
- **`Expand` is main-axis only and raises as `cross:`.** One child occupies
  a slot across the axis, so nothing competes and a weight has nothing to
  mean. Defaults: `Fixed[1]` main, `Percent[100]` cross.
- **`Percent` and `Expand` divide `extent - padding - spacing * (n - 1)`**,
  so two `Percent[50]` children fit exactly. Over-subscription **starves in
  declaration order and never raises** — a child with nothing left gets an
  empty rect and paints nothing.
- **The weighted-`Expand` remainder goes to the earliest children, one cell
  each** (five equal `Expand`s in 12 rows → `3,3,2,2,2`). Changing this changes
  rendering, and it is specced.
- **`spacing` / `padding` are box-global; grouped gaps come from nesting.**
  A `Vertical.new(spacing: 0)` inside a `Vertical.new(spacing: 1)` is the
  idiom (see the Checkbox and ProgressBar sampler panes). Don't add
  per-child spacing: a gap belongs to the *sequence*, and `GridBagConstraints`'
  eleven fields are the tripwire for this tuple growing past three.
- **Every child-list mutation relayouts.** `Box` overrides `remove` because
  in a box the siblings *move* — `Absolute` can leave them alone, this
  can't. `relayout` no-ops while `rect.empty?`, since `add` runs during
  construction long before a parent assigns a rect.
- **The constraint map is a per-child *attribute* map, not a second copy of
  ordering.** `@children` stays the sole ordering authority, so the map
  doesn't trip `D-tree-api`'s slot-desync rule the way `ScreenPane#popups`
  does. It is identity-keyed, and `remove` drops the entry.
- **A capped proportion is out of scope, by design.** `min(16, width / 3)`
  and `(width / 3).clamp(20, 40)` are unsayable in three constraints, and
  the sampler keeps a rect-callback `Absolute` for exactly those (its main
  split and two sidebars). That division — only the part needing arithmetic
  has any — is the intended pattern, not a gap to close with `Min`/`Max`.

### Theme

Built-in components read semantic colors from `Screen#theme`
({Tuile::Theme}, a frozen value type). The concepts and usage —
accents-only, dark/light, `Color`-only construction, `custom` tokens,
`ThemeDef` pairing, live OS flips — are the book (ch6) and the `Theme` /
`Screen#theme=` / `#theme_def=` / `#detect_scheme` rdoc. Invariants:

- **Read theme values at paint time; never cache them in an ivar.** A
  `theme=` restyles everything through one invalidate-all pass, so a cached
  accent strands on the old scheme. (Also why the inherent-bg widgets
  re-read their well each paint — see Background color.)
- **No global bg/fg token.** Non-accent cells inherit the terminal default
  (the light-theme strategy); a theme carries accents only (`D-bg-inherit`).
- **Startup scheme detection must stay in `Screen#initialize`.** The OSC 11
  reply lands on stdin, which the key thread owns once the loop runs — so it
  cannot move later. {FakeScreen} overrides the private `detect_scheme` to
  pin `:dark`, keeping specs deterministic and off the test runner's TTY.
- **A custom `ThemeDef` survives OS appearance flips; a bare `theme=` is
  transient.** Live flips ride mode 2031 and re-pick `theme_def.for(scheme)`;
  a one-off `theme=` doesn't participate and reverts on the next flip.
- **`on_theme_changed` is for app-rendered *content*.** A {Tuile::StyledString}
  in `Label#text` / `List#lines=` / `TextView#text` bakes its colors at
  construction, and only the app knows which were theme-derived (vs. inherent
  to the data, e.g. log-level colors) — so the app rebuilds them in the hook
  (subclasses `super`; stock assemblies set the `on_theme_changed=` proc).
  Built-in chrome and `Theme::Ref` backgrounds skip it — they resolve live.
- **Don't make {Tuile::StyledString} theme-aware to dodge that hook.** It's a
  pure frozen value type with a `parse(to_ansi(x)) == x` round-trip and zero
  `Screen` dependency; a theme ref would break all three.
- **Specs:** an app's spec_helper reassigns `ThemeDef.default` once so every
  `Screen.fake` resolves its custom tokens; gem specs that touch it must
  restore `ThemeDef::DEFAULT` in `after`.

### Background color (opt-in, inherited)

`Component#bg_color` (a `Color`, a `Theme::Ref`, or `nil`; default `nil`)
is an opt-in background, inherited down the tree and resolved **at paint
time**: `effective_bg_color` reads `@bg_color` (resolving a `Theme::Ref`
against `screen.theme`), else the parent's, else `nil` (terminal default).
Never cache it — same reason as theme accents. The rationale and
roads-not-taken live in DECISIONS.md (`D-bg-inherit`, `D-theme-ref`); the
invariants that must not break:

- **Terminal cells are opaque; inheritance is resolve-at-paint, not
  paint-order.** `Buffer#write_cell` stores a span's `Style` wholesale, so
  a glyph with `bg: nil` writes terminal-default and clobbers any fill
  underneath — "parent fills, child paints on top" does *not* yield
  inherited text. The effective bg must be baked into every painted cell.
- **Self-painters paint through `Component#draw_text` / `#draw_char`, not
  `screen.buffer.set_*`.** Those wrappers apply `effective_bg_color` via
  `StyledString#under_bg` (fill-unset: sets bg only on spans that have
  none — distinct from `with_bg`, which overrides every span). This is the
  single choke point; bypassing it drops inheritance. `grep -rln 'draw_text'
  lib/tuile` lists the self-painters currently routed through it.
- **Three camps, don't mix them.** (1) *Gap-leavers* (default `repaint` →
  `clear_background`): served automatically — the fill uses
  `effective_bg_color`. (2) *Content self-painters*: route through
  `draw_text`/`draw_char` (above). (3) *Inherent-bg widgets*
  ({Component::TextField}/{Component::TextArea} wells): opt out — they
  paint an explicit bg over their whole rect, so `under_bg` no-ops on
  them and the tint can't bleed in. They **must not** set `bg_color`, and
  must keep reading their well from the theme at paint time — storing it
  would cache a theme value in an ivar (see Theme).
- **`bg_color=` invalidates the whole subtree** (`on_tree`), not just
  self — inheriting descendants must re-resolve. Over-invalidation is
  free on the wire (the flush emits only changed cells); pruning the
  invalidation set is a deferred optimization, not a correctness need.
- **A `Theme::Ref` bg is live-resolved and rides the theme-change
  repaint.** `bg_color = Theme.ref(:token)` stores the *ref* and re-resolves
  it against `screen.theme` each paint, so it tracks flips with no
  `on_theme_changed` hook. It reaches a built-in chrome or a `custom` token
  (chrome wins a name clash) but never *adds* one, so it can't reintroduce
  the banned global bg/fg token (`D-theme-ref`); the setter validates
  eagerly (KeyError at assignment). It stays current only because `theme=`
  invalidates the whole tree — if that is ever pruned, `Theme::Ref`
  backgrounds must still be invalidated on theme change (guarded in
  `screen_spec`).
- **`nil` means inherit-upward, not a sentinel.** No `INHERIT` constant;
  the terminal default is the root of the chain. There is deliberately no
  opt-*out* ("force terminal-default despite a tinted ancestor") — add a
  `:default`/`Color::TERMINAL_DEFAULT` sentinel only if a real need
  appears.
- **`Label#bg` predates this and is a distinct knob** (override-*all* via
  `with_bg`, vs `bg_color`'s fill-unset inheritance). They compose (a set
  `#bg` bakes explicit span bgs that `under_bg` leaves alone, so it wins
  locally); the overlap is a known wart pending a consolidation decision.

### Items and rendering (`List`)

{Tuile::Component::List} holds *items* (any objects, one row each) and a
`renderer` (item → row); the callbacks hand back the item. Why a renderer
rather than a shared base for the five composers, and why lazy rather than
eager: `D-list-items`. Usage: the `List` rdoc and book ch7. Invariants:

- **The renderer runs at paint time, on any frame.** Only the rows in the
  viewport are rendered, each memoized until the cache is dropped. So a
  renderer must be a pure, cheap function of its item — work that reaches a
  service belongs in the item, not in the renderer.
- **Search renders without memoizing.** `select_next` scans through the
  uncached path on purpose: one failed scan over a long list would
  otherwise grow the cache to one row per item. Invisible in the code and
  silent under test, so `list_spec` asserts the cache is still empty after a
  failed scan — don't "simplify" the scan onto the cached path.
- **Every input to a row's geometry must drop the cache.** Today that is
  `items=`, `renderer=`, `on_width_changed` and `scrollbar_visibility=`. A
  new thing that changes what a row looks like owes a `drop_row_cache`, or
  it will paint stale rows with nothing in the diff to notice.
- **Don't add an `:auto` scrollbar mode.** Visibility would become a function of
  `rect.height` while the padded-row cache is rebuilt from the width-only
  `on_width_changed`, so a height-only resize would flip the scrollbar, shrink
  `content_width` and leave every row a column off — silently, with nothing in
  the diff to notice. A caller that knows both the row count and the height it
  chose sets the mode itself; `ListDropdown#anchor_to` is the worked example
  (`D-select`).
- **`refresh_rows` is for a renderer whose *inputs* changed** — the same
  proc and the same items producing different rows, which no setter can
  detect (a group's selection marker). Not `content.renderer =
  content.renderer`, and not a rebuild of every row.
- **One item is one row.** A multi-line rendering keeps its first line — a
  `\n` reaching the buffer corrupts the frame, and splitting would break the
  index-is-the-item identity everything else rests on.
- **There are no appenders, and adding one reopens the provider question.**
  `add_item` / `add_items` / `add_line` / `add_lines` were **removed** in
  0.12.0: an append is a statement about a collection the `List` owns, and a
  lazily-sourced provider owns nothing to append to. So the items are always
  assigned whole — an app that grows a list keeps its own array and re-assigns
  it (`list.items = mine`, or the spec helper's
  `list.lines = list.items + more`) — and a `List` stays a snapshot of a
  collection. Two consequences: incremental append lives on
  {Tuile::Component::TextView} (which keeps its eight mutators, and is what
  {Tuile::Component::LogWindow} uses), and a re-assignment drops the whole row
  cache where an append used to preserve it, so a tailing app re-renders its
  viewport per row rather than nothing. **Re-grow rule:** an appender may come
  back only as sugar over a provider that can express it, never as a mutation
  of `@items`.
- **`lines=` / `build_lines` are not a compatibility shim.** They split on
  `\n`, rstrip, and store the resulting `StyledString`s *as the items* under
  the default renderer, which is the honest API for a log or a static report —
  and is why a line-populated list's callbacks are unchanged. `build_lines`
  yields a plain growing `Array` and assigns it through `lines=`; the buffer
  must stay readable mid-build (a builder records `buffer.size` as the row a
  `Cursor::Limited` may land on). **There is no `lines` reader**, and
  `ListDropdown` has no `lines=` / `lines` either — both were the naming wart,
  deprecated and then deleted inside 0.12.0 (`D-list-items`): read `items`, and
  a spec asserting what a list *shows* asserts the painted buffer. Don't
  re-add a reader — the name lies once a `renderer` is set, and a getter that
  rendered instead would force a full render.
- **`List` measures nothing for its own size.** No width reader, no
  "widest item" query: {Tuile::Component::Select} measures its labels
  caller-side and assigns the rect it computed. Adding a size query here
  reopens the top-down layout rule.

### Input values (`HasValue`) and the composed fields

Input components share the {Component::HasValue} value seam
(`value` / `value=` / `empty?` / `clear` + `on_value_change`). Why it's
deliberately thin, and typed rather than String-only: `D-has-value`, with
`D-integer-field` for the composed-field shape and `D-float-field` for the
naming rule and the deliberate duplication. **Each field's own rules — a parse's
leniency, a `value=` coercion, an input filter, a dropdown's measured width —
live in its rdoc and its `D-` entry, not here.** What follows is the part a
*new* component can break: the seams, and the composition recipes.

#### The seams: what carries a value, and what may include the mixin

- **`caption` is chrome, `text` is value — don't cross them.**
  {Component::HasCaption} holds app-authored chrome (a `Window` title, a
  `Button` label); `text` is the user-editable value ({Component::HasValue},
  which `AbstractStringField` aliases `text` onto). A new component picks by
  that test, and may carry both — which is why they're two mixins. Two rules
  on the caption seam: it stays a *mixin* (a tree walk finds "the Button
  captioned Submit" via `is_a?(HasCaption)` + a caption compare, so per-class
  accessors would break lookup), and an includer reads it through `caption`,
  never `@caption` — the ivar is nil until the first non-empty set.
- **`HasValue` is the input-field mixin, not just a value seam.** It also
  carries `focusable? = true` (overridable). But **not** `tab_stop?` — that
  diverges and stays out of the mixin: the leaf editable field
  (`AbstractStringField`) is a tab stop (`true`); a wrapper composing one is
  *not* (`false`, inherited from
  `Component`), because its inner field carries the stop and a tab-stop
  wrapper wrapping a tab-stop field would double-stop Tab (`cycle_focus`
  collects stops via `on_tree`). The rule is "exactly one stop per widget", not
  "a wrapper never claims one": {Tuile::Component::Select} wraps nothing and so
  claims `true` itself, like {Tuile::Component::Checkbox} — had its face been an
  (inert, non-tab-stop) `Label` child, it would still have had to claim it, or
  nothing would and Tab could never reach it (`D-select`).
  **So a component with a `value` that isn't a *field* stays out of the mixin**
  — {Tuile::Component::ProgressBar} keeps `value` / `fraction` / `percent` as
  plain accessors, since including it would make a display widget focusable and
  enrol a read-only report in the seam a forms layer iterates (`D-progress-bar`).
- **A component's value is typed, not stringly.** `ComboBox#value` is the
  *selected item* (of whatever type `items` holds), never the display
  string; `IntegerField#value` is an `Integer`/`nil`; a text input's value
  *is* its text. Model-mapping is a layer above, never field state.
  **A typed field is named after the Ruby class of its value** —
  `Integer`→`IntegerField`, `Float`→`FloatField` — so the name is derivable and
  says the precision out loud (`D-float-field`; not `NumberField`, which names
  Vaadin's widget category rather than this field's value).
- **What counts as *empty* is per-component**, and `empty_value` is where it is
  declared: `nil` for a numeric field, `""` for a text input, `false` for a
  {Tuile::Component::Checkbox}, a frozen empty `Set` for a
  {Tuile::Component::CheckboxGroup}.
- **`items` is chrome; `value` is authoritative and may hold what `items`
  doesn't.** `items=` never touches `value` and never fires
  `on_value_change`; an absent value simply renders nothing selected and
  survives intact, so a form saved without edits changes nothing silently.
  Keeping the two in sync is the app's job — the framework has **no reconcile
  step, no clamp and no silent drop**, in any items-plus-value component
  (`D-combobox`, `D-checkbox-group`, `D-radio-group`).

#### Composition: a typed field wraps a field, a group wraps a `List`

- **A typed field composes an `AbstractStringField`; it does not subclass
  one.** `ComboBox`, `IntegerField`, `FloatField` and `BigDecimalField` hold a
  `TextField` as their single {Component::HasContent} child, so their face
  carries only the typed `value` seam, never the widget's `String`-typed
  `text`/`value`. `HasContent` (rather than a hand-rolled
  `children`/`rect=`/`on_focus` shell, or a bespoke shared base) is what makes
  `content`/`content=` public on them; each defines a `layout(field)` hook to
  size the inner field.
- **A group composes a `List`, and a new composer owes four things.**
  `CheckboxGroup` / `RadioGroup` hold a `List` of their items — that is where
  the cursor, scrolling, scrollbar and per-row hit-testing come from — and own
  only the `List#renderer` that paints the marker in front of the label. All
  four are needed, and `radio_group.rb` is the model:
  1. **Install a cursor** (`list.cursor = List::Cursor.new`). A bare `List` has
     `Cursor::None` at position `-1`, so arrows, Enter and the highlight are all
     dead without it — and any path resolving `items[position]` needs a range
     guard, since `-1` otherwise reaches the *last* item.
  2. **Paint from `rect.left + 1`** — rows carry `List`'s one-column gutter.
  3. **Re-render through `List#refresh_rows`**, never by rebuilding rows, when
     what moved is the renderer's *input* (the selection) rather than the items.
  4. **Clamp the cursor when the item set shrinks.** `List#items=` deliberately
     leaves a stale cursor alone, so it strands off-content (no highlight, dead
     Enter) and a key resolving `items[position]` gets `nil` — which for a
     single-valued widget silently *clears* the selection.
- **Duplicate rather than DRY a shallow shell.** `FloatField` is a deliberate
  near-copy of `IntegerField`, `BigDecimalField` a third; `Select` and
  `RadioGroup` share no code, which is a third copy of the
  `items=` / `item_label=` / `label_for` shell. Each time the base would need
  two or three hooks over ~15 lines — the converter strategy `D-integer-field`
  kept out of the field layer, reached through inheritance instead of a setter
  (`D-float-field`, `D-select`). A **fourth** copy is when to re-argue it; three
  is not a signal to fold now.

#### What the rest of the widget set owes the framework

Per-widget behavior is each widget's rdoc; these three cross the file boundary.

- **A dropdown driver supplies its own width.** `ListDropdown#anchor_to` owns the
  vertical placement (it flips above/below, slides horizontally, and toggles the
  scrollbar), but `width:` is caller-supplied — `ComboBox` keeps the field's
  width, `Select` passes a measured one. Same shape as `D-box-layouts`' "`align:`
  is legal only because the cross extent is caller-supplied", and it is what
  keeps `anchor_to` from measuring content. A third driver repeats that
  measurement; it does not push it down (`D-select`).
- **`Select` claims Enter, Space, ESC, `ListDropdown::MOVE_KEYS` and the mouse —
  nothing else**, so every other printable bubbles to the app and a form's
  `s`-to-save keeps working while a Select has focus. That is the whole reason it
  exists next to a `ComboBox`, whose field eats printables unconditionally.
  Adding a printable here is the one change that would break the contract
  (`D-select`).
- **The `[x] `/`[ ] ` glyphs are a documented convention, not constants** — a
  group component painting checkable rows repeats the literals rather than
  importing them from {Tuile::Component::Checkbox} (`D-boolean-fields`).
  Space *and* Enter toggle, standalone and in a row alike; which widgets let
  Enter through to an ancestor is per widget, tabulated in book ch5.

### Nomenclature — one word per concept

Definitions live in TERMINOLOGY.md; the choice and the roads not taken live in
`D-scroll-nomenclature`. What must not break:

- **`row` is the terminal grid unit, everywhere, no exceptions.** A wrapped unit
  of text *is* a row — wrapping is the operation that turns text into rows. This
  is settled against the standards, which call a screen row a *line* (ECMA-48
  `IL`/`DL`, terminfo `lines`, POSIX `LINES`): that word is unavailable to Tuile
  because Tuile also holds text with `\n` in it, and ECMA-48 never did.
- **`line` means exactly what `String#lines` returns**, and is never a
  coordinate. It is not a Tuile convention a reader must memorize — it is Ruby's
  word, which is what defuses the row≈line synonym problem.
- **The two space rules.** An object with only one row space leaves `row`
  unqualified ({Tuile::Buffer} is the grid; `TextArea::WrappedText` is content);
  a component holding both qualifies the viewport one (`row_in_viewport`), so its
  bare `row` and its `scroll_top_row` are content-space.
- **A new component must not invent a third vocabulary.** Every scroller says
  `scroll_top_row` / `viewport_rows` / `row_in_viewport`; a widget holding domain
  objects says `items` and renders them with a `renderer`.
- **`spec/tuile/nomenclature_spec.rb` is the guard, and it holds no allowlist.**
  It fails on any of `set_line`, `draw_line`, `top_line`, `physical_line`,
  `hard_line`, `display_row`, `screen_row`, `viewport_lines` in `lib/`. If a
  future rename needs an exception there, the rename is wrong — the list holds
  only because none of those words has a legitimate use left. `line_count` is
  deliberately *not* on it ({Tuile::Component::TextView::Region#line_count}
  counts `\n` units and is correct): a word that is right in one space and wrong
  in another is the glossary's job, not a grep's.

### Geometry primitives

`Point`, `Size`, `Rect` are `Data.define` value types (frozen,
structural equality). `Rect#contains?` uses **half-open** edges
(`x >= left && x < left + width` — right/bottom are exclusive).
`Rect#empty?` includes width==0 *and* width<0.

### Glyph width — the ambiguous-width bet

All measurement goes through `StyledString#display_width`
(`unicode-display_width`), which counts East-Asian-**Ambiguous** characters
as **one** column. Tuile bets on that globally — `Window`'s border and
`VerticalScrollBar`'s `█` are Ambiguous, and nothing is designed to survive
them measuring 2. The invariants below run measuring → the index/column
trap → wrapping and the caret.

Where the *why* lives: `D-ambiguous-width` owns the bet itself, the
per-component glyph rulings, and the detect-and-swap path to take if
ambiguous-as-wide ever needs supporting; `D-text-field-axes` owns the
two-axes rule, `TextField`'s horizontal scrolling and its `max_text_length`
(which counts **characters**, knowingly — it is the one input measure that
does not use the edit unit); `D-text-area-columns` owns the cluster-iterating
wrap; `D-cluster-width` owns the emoji policy, the >2-column cluster and the
two-measurement-routes rule; `D-cluster-caret` owns the boundary-locked caret,
and records the rejected boundary-table and cluster-array designs.

#### Measuring

- **Never measure with `String#length`; never hand-roll a width table.**
  Use `display_width` / `slice` / `ellipsize`, so the whole framework
  shares one answer and one future migration point.
- **A new component defaults to ASCII when the pretty glyph is Ambiguous**,
  offering the glyph as an opt-in knob (`mask_char=`, a future `glyphs=`).
  This keeps the Ambiguous inventory small and enumerable, which is the only
  thing that keeps the bet cheap to reverse.
- **Ink overflow is a different problem, don't conflate them.** A glyph can
  measure 1 everywhere and still be *drawn* wider than the cell by a
  fallback font (`☑` in Alacritty). That's cosmetic — coordinates stay
  correct — and it is a font-coverage argument, not a width one.
- **Measure per grapheme cluster, and pass the one emoji policy.** The unit a
  terminal draws is the cluster, not the character: `"👍🏽"` is two codepoints
  measuring 2 columns, so summing its parts gives 4 and lets it overrun its
  cell. Every `Unicode::DisplayWidth.of` call in the gem therefore passes
  `emoji: StyledString::EMOJI_WIDTH` (`:rgi`), and the inventory is small enough
  to audit in one grep — `grep -rn 'DisplayWidth.of' lib` — which is how to check
  it rather than trusting a count written here. **A new call site without that
  argument is a bug** (`D-cluster-width`).
  Two consequences worth keeping straight:
  - **A cluster is *not* capped at two columns.** A non-RGI ZWJ sequence is one
    cluster that terminals draw as separate parts, so it measures 4.
    `Buffer#put_char` models an arbitrary continuation run for exactly this,
    and `blank_left_partner` / `blank_right_partner` walk the whole run rather
    than assuming a 2-cell glyph.
  - **Never iterate `each_char` to measure or slice.** Per-character walks both
    mis-total a sequence and cut clusters apart — a slice that drops a
    combining mark returns a *different letter* (`"abé"` → `"abe"`), and the
    painter silently drops a mark with no base. {Tuile::StyledString}'s wrap and
    slice internals walk `each_grapheme_cluster`; the triples they pass around
    are named `glyphs`, not `chars`, to keep that honest.
- **Two measurement routes exist, and a spec pins them together.**
  {Tuile::StyledString#display_width} measures a whole string in one gem call
  (the gem's ASCII fast path makes that the quick route for the common case)
  while {Tuile::Buffer} measures cluster-by-cluster as it
  paints. They agree — verified over a corpus in `styled_string_spec` — and if a
  change ever breaks that agreement, layout and paint disagree, which is the
  whole bug class these notes exist to prevent. Don't "unify" them by making
  `display_width` sum clusters; that is the slow path.

#### Index vs. column — the axis trap

- **A text index is not a column; convert, never conflate.** The trap this
  bet sets, and the one that already bit both text inputs: a caret/offset
  counts *characters* into a `String`, while a rect, a cursor position and a
  `MouseEvent` count *columns*. They agree only for one-column glyphs. Both
  {Tuile::Component::TextField} and {Tuile::Component::TextArea} now name the
  two axes in their rdoc and convert explicitly; the measurement primitive is
  `columns_of` (per-grapheme-cluster, via the memoized
  {Tuile::Buffer.display_width}) and **every** width measurement in an input
  goes through it (`D-text-field-axes`, `D-text-area-columns`). It lives on
  `AbstractStringField` and is deliberately mirrored, one line, on
  `TextArea::WrappedText`, which is not a component and so can't inherit it —
  the rule is "per-cluster via `Buffer.display_width`", not "one method".
  Symptoms
  to recognize, because they travel together: a cursor placed at
  `rect.left + caret`, a pad computed as `rect.width - text.length` (which
  overruns the rect), and a capacity or wrap rule counting characters against a
  column budget.
- **A {Tuile::Component::TextField} subclass that paints something other than
  `text` overrides `display_text`, never `repaint`.** Same bug class one level
  up — there index vs. column, here edit buffer vs. painted glyphs: the privates
  that place the cursor, size the scroll window and resolve a click all measure
  `display_text`, so overriding the paint alone leaves them measuring the buffer
  while the cells show the substitute, a drift that *grows* along the string and
  stays silent until a glyph isn't one column wide. The contract is **one display
  character per `text` character, in order**, nothing enforces it at runtime, so
  a subclass pins it with a spec ({Tuile::Component::PasswordField} is the only
  implementor today). **Re-grow rule:** a display↔text *index map* is
  deliberately not built — a formatting field (digit grouping, a `dd/mm/yyyy`
  mask) *inserts* characters, so it composes a `TextField` the way
  {Tuile::Component::IntegerField} does and keeps the separators on its own side
  of the seam. If a real caller ever appears, add a hook *pair*; never loosen
  `display_text`.

#### Wrapping and the caret

- **A wrap must iterate grapheme clusters, and every branch must advance by at
  least one.** A combining mark has to add zero columns *and* stay attached to
  its base across a row break, and `"\r\n"` is a *single* cluster. A branch that
  measures zero and doesn't consume hangs the UI thread outright — that is how
  `area.text = File.read(crlf_file)` used to lock up, and why
  `wrapped_text_spec`'s "exotic whitespace" context wraps its examples in a
  `Timeout`. Add a spec there for any new whitespace branch.
- **The wrap is a value, and the viewport is not part of it.**
  `TextArea::WrappedText` is a snapshot of `(text, width)` — it owns the wrap
  *and* every index↔row/column conversion, and it is where a new wrap-level
  question gets answered. What must stay out of it is `scroll_top_row`: the
  viewport is stateful across edits and needs `Rect#height`, so folding it in
  would re-couple the wrap to a rect and cost the screen-free specs that are the
  whole reason the class exists (`wrapped_text_spec` installs no `Screen`). The
  class is private to `TextArea` and stays that way until a second caller
  actually exists — `TextView` is *not* one, it wraps {Tuile::StyledString}
  spans and rewraps incrementally. **An outside caller needing a wrap-level
  answer gets a forwarding reader on `TextArea`, never the object**
  ({Tuile::Component::TextArea#caret_row} / `#row_count` are the two): `@wrap`
  is a cache nilled on every text or width change, so a handed-out reference
  answers confidently about text the widget no longer holds — the same
  cache-in-an-ivar failure the theme and `bg_color` rules forbid
  (`D-text-area-rows`).
- **The caret counts characters but is always on a cluster boundary, and every
  edit steps by a whole cluster.** The two rules are one design: `caret=` *and*
  `text=`'s clamp both snap forward to the smallest boundary `>= index`, which
  makes a mid-cluster caret unrepresentable, which is what lets LEFT/RIGHT and
  BACKSPACE/DELETE assume a boundary and move or delete exactly one cluster —
  uniformly, with no per-script rules. A new string field inherits this from
  {Tuile::Component::AbstractStringField} and must not route around it; why the
  snap is forward, why both write sites are needed, and why insertion stays
  character-native are in that class's rdoc and `D-cluster-caret`.

## Testing

`spec/tuile/**/<file>_spec.rb` mirrors `lib/tuile/**/<file>.rb` (so
`lib/tuile/component/window.rb` ↔ `spec/tuile/component/window_spec.rb`).
Specs are
wrapped in `module Tuile` so unqualified references (`Component`,
`Screen`, …) resolve via lexical scope. Assertions are minitest-style
(`assert`, `assert_equal`, `assert_raises`, `refute_*`) wired through
rspec-core via `config.expect_with :minitest`.

`spec/examples/` holds end-to-end tests for the runnable scripts under
`examples/`: each spawns its target script in a pseudo-TTY via
`PTY.spawn`, waits for a known glyph to confirm the first paint landed,
sends a key, and asserts a clean exit. Linux/macOS only — Ruby's stdlib
`PTY` isn't on Windows. They run as part of `rake spec`.

**Pace the keys in a PTY test — never write a burst.** {Keys.getkey}
reads one key, and on a leading `\e` gulps a *fixed* 5 bytes to complete
an escape sequence (see its rdoc). So bytes that arrive in the *same*
read burst get merged into one bogus "key": `write("\eq")` is read as one
unknown sequence, not ESC then `q`; `write("\e[B\e[B")` glues two Down
arrows; a trailing `write("q")` sent with others can be swallowed into a
partial sequence. A real human types with millisecond gaps, so this only
bites tests (and pasted input). The fix is to send one key/sequence at a
time and force a round-trip between them — `readpartial` a frame, or a
short `sleep` — exactly as the sampler PTY test walks the nav list. In
particular ESC-then-key: write `"\e"`, drain the repaint it triggers,
*then* write the next key. This is inherent terminal ESC-ambiguity, not a
bug to "fix" in `getkey` — a timeout-based reader would add latency to
every ESC; don't.

**The one sanctioned burst is a bracketed paste.** `\e[200~…\e[201~` is written
in a single `write` on purpose: a real paste is a gapless burst, that fidelity is
the thing under test, and `Keys.read_paste` drains the payload raw so nothing in
it can be mistaken for a key (`D-bracketed-paste`). Everything *around* it — the
navigation keys before, the quit key after — still gets the pacing below.

**And the *first* key needs the same gap.** Seeing the first frame proves
the main thread painted, not that the key thread reached its first
`$stdin.getch` — and the raw-mode flip discards typeahead, so a key
written in that window is silently dropped and the test hangs waiting for
a repaint that never comes. Sleep before the first key too
(`file_commander_spec` measures it: 0 fails, 50 ms is enough).

The `Screen.fake` / `Screen.close` `before`/`after` pair is the standard
setup — it installs a {Tuile::FakeScreen} (160×50, in-memory `prints`
buffer, no terminal IO) and resets the singleton between
examples. Without it, code that touches `Screen.instance` will see
state leaked from the previous test. The fake runs no event loop, so the
ordinary `check_locked` admits the example thread on its own — a spec that
mutates UI from a *spawned* thread raises, exactly as an app would.

For **painted content**, assert against `Screen.instance.buffer`: after a
`component.repaint` (or `Screen#repaint`), the painted cells live in the
buffer. Use `buffer.region_text(rect)` (Array of plain rows) /
`buffer.region_ansi(rect)` (Array of ANSI-rendered rows, byte-identical to
the old per-row print) scoped to the component's `rect`, or `cell(x, y)`
for a single cell's `grapheme` / `style`. `Screen.instance.prints` now holds
only cursor/housekeeping escapes and the assembled frame string (cursor +
sync wrapper) — assert `prints.join` against it for cursor behavior, not
for content. `Screen.instance.invalidated?(c)` and `invalidated_clear` are
the test-only hooks for verifying invalidation.

`FakeEventQueue` runs submitted blocks synchronously and discards
posted events; it lets specs drive the system without a real loop.

## Commands

```sh
bundle exec rake check                       # full pre-commit suite: spec + rubocop + sig (also the default task)
bundle exec rake spec                        # run all specs (unit + examples)
bundle exec rspec spec/tuile/list_spec.rb    # run one file
bundle exec rspec spec/tuile/list_spec.rb:42 # run a specific example
COVERAGE=true bundle exec rake spec          # specs + SimpleCov report at coverage/index.html
bundle exec rubocop                          # lint (Metrics/* size cops violate freely; we accept those)
bundle exec rake sig                         # regenerate + validate sig/tuile.rbs via sord (commit it if it changes)
bundle exec rake benchmark                   # display-width / repaint micro-benchmarks
```

`rake check` (== the default `rake`) is what to run before committing —
it is the same `spec` + `rubocop` + `sig` the release gate re-runs. `rake
sig` can dirty the tree by regenerating `sig/tuile.rbs`; commit the result.
The release procedure itself lives in `RELEASING.md`.

Coverage at 0.11.0 sits at ~97% line / ~91% branch. The remaining gap is
in real-terminal runtime paths (`Screen#run_event_loop`,
`EventQueue#start_key_thread`, the WINCH trap) that need raw-mode stdin
and a real signal handler — not worth mocking. Coverage is not gated;
treat the number as a signal, not a target.

CI (`.github/workflows/ci.yml`) runs `rspec` on Ruby 3.3 / 3.4 / 4.0, and
separately gates **`sig/` drift**: it re-runs `rake sig` and fails on
`git diff --exit-code sig/`. So a change that alters any public signature
must ship the regenerated `sig/tuile.rbs` in the same commit — the local
`rake check` is what keeps you ahead of that job.

## Common pitfalls

- **Calling UI from a background thread.** Use
  `screen.event_queue.submit { … }`. The `check_locked` raise is a
  guardrail, not a feature — fix the call site, don't bypass it.
- **Mutating `children` / `popups` arrays.** Always go through
  `add` / `remove` / `add_popup` / `remove_popup` / `content=` /
  `footer=`. They handle parent pointers, focus repair, and
  invalidation.
- **Expecting `repaint` to happen synchronously.** It happens once per
  event-loop tick (when `EmptyQueueEvent` fires). Specs trigger it via
  `Screen#repaint` directly; production code should not.
- **Adding `require 'tuile/foo'` inside source files.** Zeitwerk
  resolves it; explicit requires bypass the loader and create dual-load
  hazards. The only `require`s that belong inside `lib/tuile/` files
  are gem-level deps you genuinely need at file-load time — and most of
  those are already hoisted into `lib/tuile.rb`.
  **The one that must *not* be hoisted** is `big_decimal_field.rb`'s
  `require "bigdecimal"` — Tuile's single *optional* dependency, cost-free only
  because Zeitwerk loads that file on the first reference to the constant. Three
  pieces hold it up (the in-file `require`, `loader.do_not_eager_load` in
  `lib/tuile.rb`, and no gemspec entry), all pinned by specs in
  `big_decimal_field_spec`. A *second* optional dependency needs its own
  argument, not this precedent (`D-bigdecimal-field`).
- **Adding a second top-level constant to a `lib/tuile/foo.rb` file.**
  Zeitwerk expects `foo.rb` to define exactly one top-level
  `Tuile::Foo`. Nested constants inside it (`Foo::Bar`) are fine. If
  you have a sibling top-level class, give it its own file.
- **Logging from gem code.** Use `Tuile.logger`, not `$log` or
  `TTY::Logger`. The default is `Logger.new(IO::NULL)`, so the gem is
  silent unless the host app sets `Tuile.logger = ...`. The accessor
  targets the stdlib `Logger` interface — `TTY::Logger` duck-types it,
  so virtui can pass its existing logger straight in. To route logs
  *into* a {Tuile::Component::LogWindow}, construct the host's logger with
  `Component::LogWindow::IO.new(window)` as its output.
- **Touching `@@instance` directly.** Use `Screen.instance` /
  `Screen.close` / `Screen.fake`. The class variable is part of the
  singleton-survives-subclassing contract.
