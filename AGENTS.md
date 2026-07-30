# AGENTS.md

Orientation for coding agents working on Tuile. Read this before making
changes; the architecture has invariants that are not obvious from any
single file.

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

Tuile's prose lives in five kinds of document, each with a distinct
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
| **AGENTS.md** (this file) | a contributor / coding agent | invariant-focused | "what you must not break" |
| **DECISIONS.md** | a contributor asking "why this way?" | one coherent, mutable entry per live decision | the *why-we-chose*, incl. roads not taken |

Rules that make six documents survivable:

- **Single source of truth per fact.** Each fact has one home; the
  others link to it rather than restating it. The book owns concepts;
  rdoc owns the per-symbol technical truth; the README owns pointers +
  quickstart; AGENTS.md owns invariants; DECISIONS.md owns the *why we
  chose it and not the alternative*. When tempted to explain something
  twice, link instead.
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
  the book; per-component API migrates to rdoc.

**The graduation pipeline.** `ideas/*.md` is transient by design — a
scratchpad "for the two of us," not user docs. It is still a vital part
of the mechanism: it's where rationale is born. On graduation — once the
idea is implemented and stable — it *moves* to its final destinations and
the `ideas/` note is retired: the **user-facing half** graduates into the
book (rewritten for the reader), the **invariant / must-not-break half**
graduates into AGENTS.md, and the **decision half** — the choice made and
the alternatives rejected — graduates into DECISIONS.md (which may already
carry an entry recorded when the decision was *made*, ahead of
implementation). The worked example is the top-down
layout overhaul (the C64 "why simple layouting is enough" argument): it
was designed in `ideas/simpler-layouting.md`, then on completion its
reader-half graduated into book chapter 3, its invariant-half into the
"Layout is top-down" section below, and the idea note was retired — the
pipeline run start to finish.

## Layout

```
lib/tuile.rb                       gem entry point: requires, Zeitwerk loader
lib/tuile/version.rb               VERSION constant
lib/tuile/keys.rb                  Tuile::Keys (key constants + .getkey)
lib/tuile/{point,size,rect}.rb     geometry value types (Data.define)
lib/tuile/mouse_event.rb           Tuile::MouseEvent (parses xterm sequences)
lib/tuile/ansi.rb                  Tuile::Ansi (SGR constants — RESET)
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
lib/tuile/component/checkbox.rb         Tuile::Component::Checkbox — one-row boolean input; Space/click toggles
lib/tuile/component/layout.rb           Tuile::Component::Layout (+ Absolute)
lib/tuile/component/list.rb             Tuile::Component::List (+ Cursor / None / Limited)
lib/tuile/component/abstract_string_field.rb  Tuile::Component::AbstractStringField (abstract; String-valued base of TextField/TextArea)
lib/tuile/component/text_field.rb       Tuile::Component::TextField
lib/tuile/component/text_area.rb        Tuile::Component::TextArea (multi-line editor)
lib/tuile/component/text_view.rb        Tuile::Component::TextView (read-only scrollable wrapped prose)
lib/tuile/component/combo_box.rb        Tuile::Component::ComboBox — filtering dropdown; typed value via items + item_label; composes a TextField (HasContent) + a ListDropdown overlay
lib/tuile/component/list_dropdown.rb    Tuile::Component::ListDropdown (+ Menu) — reusable borderless non-focusable Popup-over-List; #move forwards scroll keys, #choose commits; driver owns geometry/filter/rows/ESC/Enter
lib/tuile/component/integer_field.rb    Tuile::Component::IntegerField — typed Integer/nil input; composes a digit-filtered TextField via HasContent
lib/tuile/component/window.rb           Tuile::Component::Window (border + content slot)
lib/tuile/component/popup.rb            modal overlay, self-sizing from content, ESC/q closes
lib/tuile/component/info_window.rb      window-of-static-lines convenience (tiled or popup)
lib/tuile/component/picker_window.rb    single-keystroke option picker
lib/tuile/component/log_window.rb       Tuile::Component::LogWindow + IO adapter for tty-logger
lib/tuile/vertical_scroll_bar.rb        character-grid scrollbar (rendering helper, not a Component)
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

### Singleton Screen, structural pane

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
- `attached?` — true iff `root == screen.pane`

`children` is read-only by convention (the array must not be mutated by
callers; containers expose `add` / `remove` / `content=` / `footer=` to
swap and reparent).

### Invalidation + repaint (read this twice)

Components do **not** paint immediately, and they do **not** write
escape sequences to the terminal. They call `invalidate` (a protected
method that records `self` in `Screen#@invalidated`), and when they do
paint they write styled cells into `Screen#buffer` (a {Tuile::Buffer}
back buffer) via `set_line` / `fill` / `set_char` — never `screen.print`.
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
  background and re-invalidates children whenever the direct children
  leave gaps in `rect` (e.g. a form layout with mixed-width fields).
  Subclasses should `super` from their own `repaint` to inherit that
  behavior; only components that paint their entire rect themselves
  (currently {Tuile::Component::Window} for border-plus-content, and
  {Tuile::Component::List} for explicit row-by-row paint) opt out.
- Don't call `Screen#repaint` directly from a component; just
  `invalidate` and let the loop coalesce.
- **A one-row caption widget highlights and hit-tests its *extent*, not its
  `rect`.** {Tuile::Component::Button} and {Tuile::Component::Checkbox} expose
  `extent` — `min(caption.display_width + 4, rect.width)` columns, one row —
  because a form column routinely hands a field a rect far wider than the
  glyph, and a click on the blank tail must not activate it (the tail still
  *focuses*: click-to-focus is ungated by geometry). **The extent must not vary
  with `bg_color`**, even though a tint paints that tail — a hit test that
  widens when an ancestor gains a background is a mode switch invisible in the
  code. `extent` is deliberately *not* a `Component` method: nothing generic
  consults it, and each widget's arithmetic is its own (`D-boolean-fields`).

### Threading rule (the load-bearing one)

The event queue is single-threaded. *All* UI mutations — `rect=`,
`active=`, `content=`, `add_line`, `invalidate`, `screen.focused=` —
must run on the thread that owns `Screen#run_event_loop`.

Background threads must marshal work back via
`screen.event_queue.submit { … }`. Most UI methods call
`screen.check_locked`, which raises `"UI lock not held"` if you violate
this. {Tuile::FakeScreen} short-circuits the check so tests can mutate
freely.

`Screen#@@instance` is a class variable — the singleton survives
sub-classing (`FakeScreen < Screen`).

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
`min`/`preferred`/`max`. (TextView specs probe `@hard_lines.size`
directly for this reason — there is deliberately no public size getter.)

Two consumers that used to sit on that channel are now top-down:

- {Tuile::Component::Popup} sizes itself from `Popup#size=`
  (`Size | Fraction`, default `Fraction::HALF`, resolved against the
  screen each layout) — never from its content.
- The {Tuile::Component::Window} bottom border carries one of two
  purpose-fit members rather than one sized slot: `footer_text=` (a
  {Tuile::StyledString}, border chrome embedded into the bottom border
  line at its own width with dashes filling the remainder, clipped to the
  inner width — mirrors `caption` on top, not a component, not focusable)
  and `footer=` (a focusable component always spanning the full inner
  width of the bottom row — the search-field case). Precedence: a
  `footer=` component present occupies the row and hides `footer_text`;
  absent, `footer_text` embeds. A bottom-row widget is always FILL by
  construction; the footer is decoration overlaying the border and never
  drives window size (one that doesn't fit is clipped).

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
  in `Label#text` / `List#lines` / `TextView#text` bakes its colors at
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
- **Self-painters paint through `Component#draw_line` / `#draw_char`, not
  `screen.buffer.set_*`.** Those wrappers apply `effective_bg_color` via
  `StyledString#under_bg` (fill-unset: sets bg only on spans that have
  none — distinct from `with_bg`, which overrides every span). This is the
  single choke point; bypassing it drops inheritance. Current
  self-painters routed through it: {Component::List}, {Component::Label},
  {Component::TextView}, {Component::Button}, {Component::Window}'s border.
- **Three camps, don't mix them.** (1) *Gap-leavers* (default `repaint` →
  `clear_background`): served automatically — the fill uses
  `effective_bg_color`. (2) *Content self-painters*: route through
  `draw_line`/`draw_char` (above). (3) *Inherent-bg widgets*
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

### Input values (`HasValue`), and the composed fields (`ComboBox`, `IntegerField`)

Input components share the {Component::HasValue} value seam
(`value` / `value=` / `empty?` / `clear` + `on_value_change`). Why it's
deliberately thin, and typed rather than String-only: `DECISIONS.md`
`D-has-value` (and `D-integer-field` for the composed-field shape).
Per-symbol usage and the `AbstractStringField` aliasing: their rdoc.
Invariants:

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
  (`AbstractStringField`) is a tab stop (`true`); a composing wrapper
  (`ComboBox`, `IntegerField`) is *not* (`false`, inherited from
  `Component`), because its inner field carries the stop and a tab-stop
  wrapper wrapping a tab-stop field would double-stop Tab (`cycle_focus`
  collects stops via `on_tree`).
- **A component's value is typed, not stringly.** `ComboBox#value` is the
  *selected item* (of whatever type `items` holds), never the display
  string; `IntegerField#value` is an `Integer`/`nil`; a text input's value
  *is* its text. Model-mapping is a layer above, never field state.
- **A typed field composes an `AbstractStringField`; it does not subclass
  one.** `ComboBox` and `IntegerField` hold a `TextField` as their single
  {Component::HasContent} child, so their face carries only the typed
  `value` seam, never the widget's `String`-typed `text`/`value`. Both
  include `HasContent` (rather than duplicating a hand-rolled
  `children`/`rect=`/`on_focus` shell, or sharing a bespoke base) — so
  `content`/`content=` are public on them, and the `layout(field)` hook
  each defines is what sizes the inner field.
- **`IntegerField#value` is a *derived parse* of the buffer**, recomputed on
  read (`Integer(text, 10)` rescued to `nil`) — the buffer is the single
  source of truth, `value=` just writes it. The digit filter is the inner
  field's `on_key`, consulted *before* insertion, so a rejected key never
  moves the caret. `fire_if_changed` re-emits `on_value_change` only when
  the parsed value actually changes (so `"7"`→`"07"` stays silent),
  honoring the seam's no-op-fire contract. Empty is `nil` here, `""` for a
  text input — empty is per-component.
- **ComboBox keeps two values, never conflated.** `value` is the committed
  selection (changes only on Enter/click — the sole `on_value_change`
  trigger); the field's `text` is a transient *query* that filters and
  reverts to the value's label on ESC/blur. Selection is by list **index**
  (`items[idx]`) so identity survives duplicate labels.
- **The `@suppressing_filter` guard.** Any programmatic write to the
  field's text (a `value=`, a commit's label write-back, a revert) must set
  it behind this flag, or the field's `on_change` refill springs the
  dropdown open; it also parks the caret at the end.
- **The dropdown is a {ListDropdown}, and its list is non-focusable.** Focus
  and caret stay in the field; the combo forwards *movement* keys via
  `ListDropdown#move` (Up/Down/PgUp/PgDn/^U/^D) and commits via `#choose`, and
  a click selects without stealing focus. ESC (revert-query) and Enter (commit)
  stay combo-owned — `ListDropdown#move` claims neither — because a different
  driver (e.g. a slash palette) wants different ESC/Enter tails. That split is
  the whole reason {ListDropdown} exists: the tinted, non-focusable
  Popup-over-List and the bug-prone key-forwarding live once, the geometry /
  filter / rows / commit stay with each driver.
- **Checkbox is two-state, one write path.** `value=` coerces to `true`/`false`
  (never `nil`), `empty_value` is `false`, and `checked?`/`checked=`/`toggle`
  are thin *delegators* to `value`/`value=` — never a second write path, which
  would double-fire or skip `on_value_change`. Delegators rather than `alias`
  deliberately: an alias freezes onto the body defined at alias time, so a
  subclass overriding `value=` (the tri-state flag-clearing rule below, when it
  lands) would silently not be reached through `checked=`. Enter is deliberately unhandled so a form's submit bubbles
  past a focused checkbox; don't add it. The `[x] `/`[ ] ` glyphs (three
  columns plus a space) are a **documented convention, not constants** — a group
  component painting checkable rows repeats the literals rather than importing
  them (`D-boolean-fields`).

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
them measuring 2. Invariants:

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

`D-ambiguous-width` in `DECISIONS.md` owns the *why*, the per-component
glyph rulings, and the detect-and-swap path to take if
ambiguous-as-wide ever needs supporting.

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

The `Screen.fake` / `Screen.close` `before`/`after` pair is the standard
setup — it installs a {Tuile::FakeScreen} (160×50, in-memory `prints`
buffer, no terminal IO, no UI lock) and resets the singleton between
examples. Without it, code that touches `Screen.instance` will see
state leaked from the previous test.

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

Coverage at 0.1.0 sits at ~97% line / ~88% branch. The remaining gap is
in real-terminal runtime paths (`Screen#run_event_loop`,
`EventQueue#start_key_thread`, the WINCH trap) that need raw-mode stdin
and a real signal handler — not worth mocking. There is no CI gate;
treat the number as a signal, not a target.

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
