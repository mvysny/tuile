# Tuile — AGENTS.md

## What this is

Tuile is a small component-oriented terminal-UI framework for Ruby. You build
your interface as a tree of components — windows, lists, text fields, popups —
and Tuile runs a single-threaded event loop that dispatches keys and mouse
events, then repaints everything that was invalidated since the last tick. The
name is French for "roof tile": small pieces that compose into a larger whole.

## Promises

What the pitch commits to and cannot give up. **Owner-written** — an agent proposes, in
conversation or as a drafted line in `design/ideas/`, and never edits or retires one.

- **A retained tree, not a redraw loop.** An app mutates components and never writes a frame: no
  per-frame rebuild, no immediate-mode redraw, no model/update/view pass of its own.

## Design docs

Rationale and reference live under `design/`. Each file has one audience and *what it is allowed
to own*; every file's preamble carries its own gate, entry shape and how to cite it.

| File | Owns | Loaded? |
|---|---|---|
| `README.md` | a prospective user at the front door: positioning, install, one hello-world, routing onward | — |
| `AGENTS.md` (this) | what you must not break from a distance; the module map; this table | **every turn** |
| `book/` | a learner reading in order: the *concepts* and the *why*, narrative, order-dependent | — |
| rdoc / YARD headers | per-symbol technical truth, complete standalone on rubydoc.info; defers *motivation* to the book, never *usage* | source of truth |
| `design/architecture.md` | how the pieces compose — wiring, threads, the flows, where to start; normative | lazy |
| `design/decisions.md` | why this and not that — `D_` entries, a question and its current answer | lazy |
| `design/research.md` | what the terminal, the gems and the neighbouring toolkits actually do — `R_` entries, each claim with provenance | lazy |
| `design/terminology.md` | the house vocabulary: one line per term, looked up by word — definitions only | lazy |
| `design/releasing.md` | the release runbook | lazy |
| `design/ideas/` | not yet decided — one file per idea, `ls` is the index, deleted on graduation | transient |
| `CHANGELOG.md` | what changed and what you must do about it — one sentence per entry, append-only per release | — |

**Every fact lives in exactly one of these; the others link to it.** A one-line restatement that
saves a jump is fine — repeat the *fact*, defer the *explanation*; a compressed `D_` reads like a
summary and is really a third copy. Slugs are `D_` in `decisions.md` and `R_` in `research.md`,
and a durable doc cites no other (`Q_` open questions stay inside `design/ideas/`).

A CHANGELOG entry is one sentence — `Add` / `Fix` / `**Breaking:**`, the symbol, what changed,
≈40 words; a trailing See `D_<slug>` doesn't count, and a breaking entry earns a second sentence
for the migration only. Group `Add`, then `Fix`, then `**Breaking:**`; a themed release may carry
a ≤3-sentence preamble under its version heading, once.

### Ideas & their graduation

An idea graduates the moment it is acted on, and graduation is not done until its file (and any
sidecar folder `design/ideas/<name>/`) is gone. Where the lasting nuggets land:

- the choice made + the roads not taken → a `D_` entry if it passes that file's gate; else a
  comment at the site of the choice
- a promise the pitch makes → a proposal for the owner, who writes the line above; the invariant
  that keeps one → a line in this file
- a new component, or a changed responsibility → a component owes **four** registrations: rdoc, the
  CHANGELOG, the README's Components table, and `component_contract_spec`'s catalog (that last one
  fails the build rather than rotting)
- how the pieces work together — wiring, a flow crossing several → `design/architecture.md`
- verified behaviour of the terminal, a gem we sit on or a neighbouring toolkit →
  `design/research.md`, with a provenance marker
- how one class works and why it is shaped so → its rdoc
- what a learner needs in order → `book/`; what a user needs at the door → `README.md`
- a house word's definition → `design/terminology.md`
- a cross-cutting invariant → one line in this file

## Invariants

Widget-set recipes (a new field, a new group, an overlay) are in `lib/tuile/component/AGENTS.md`;
testing invariants are in `spec/AGENTS.md`. The box layouts' own rules are `Box`'s rdoc and
`D_box_layouts`.

### Handler naming

- **Two prefixes: `handle_foo` is the override point, `on_foo` the listener slot.** No name
  carries both, and there is no third family. See `D_handler_naming`.
- **A slot is a {Tuile::Listeners} — a list declared with `listener :on_foo`, no `on_foo=` and no
  `clear`.** Append, and remove your own; deleting the setter is what makes a claimed slot
  unbreakable rather than merely discouraged. Read the slot, never `@on_foo` — it is built on first
  read and nil until asked. See `D_listeners`.
- **No `on_` method is *defined* in `lib/`, reader or writer** — every reader is macro-generated,
  and a writer is the replace operation that was deleted.
- **An empty list is meaningful, and each slot's rdoc says what its empty means** — a key-claiming
  slot declines the key, `Screen#on_error` re-raises. A widget that must *install* something while
  claimed takes `listener`'s transition block, the sole hook the setter's deletion left.
- **Every slot fires one {Tuile::Event}**, a frozen `Data.define` including the marker, nested
  beside whatever fires it and mandating no members; a listener taking no parameters is called with
  none, one needing two raises at registration.
- **`handle_` marks the override point and says nothing about the return; a trailing `?` does** —
  exactly the handlers a dispatcher *routes* take it and return a verdict: `handle_key?`,
  `handle_text_input_key?`, `MenuBar#handle_mnemonic?`. The test is "is there an alternative
  delivery this answer chooses between?"; `nomenclature_spec` holds the set.
- **Calling a `handle_…?` delivers the event; it is not a probe** — the `?` is `Set#add?`'s
  "did it happen", never "would you", so no `can_handle?` is ever asked ahead of delivery.
- **Everything else returns `void`, and a manufactured `false` is worse than nothing** — it reads
  as "I didn't handle that" at a site that just did the work. `handle_paste` is in this half: it
  reaches the focused component and stops, so a decliner has nowhere to hand it on. See `D_bracketed_paste`.
- **An override calls `super`, empty base body or not** — that is what keeps both upgrade
  directions additive, so neither the hook nor the slot has to ship first. The carve-out is a hook
  whose base body does real work and whose override *replaces* it (`handle_child_removed`,
  `ConfirmWindow#handle_focus`), and it is stated at the site.

### The tree

- **`Screen` is the service and stays out of the tree; `ScreenPane` is the UI root and defines
  attachedness.** New machinery on one, new tree semantics on the other. See `D_tree_first`.
- **`attached?` is `root.is_a?(ScreenPane)` — one axis, no `Screen` consulted**, so a tree
  assembles with no screen in the process. Don't reintroduce `root == screen.pane`. See `D_tree_first`.
- **Reparent only through `add_child(child, at:)` / `remove_child` / `detach_child`**, which write
  the array and the parent pointer in one call; `children` is read-only to callers. See `D_tree_api`.
- **Those three plus `children`, `parent` and `parent=` are `final`**, checked once per class at the
  first `new` — an override by `def`, `define_method`, `include` or `prepend` raises
  {Tuile::Error}. See `D_final_tree`.
- **`parent=` is the sole firing site for `handle_attached` / `handle_detached`**, at most once per
  component per transition, whatever the hooks do to the tree. See `D_attach_hooks`.
- **A hook may assume no geometry, no repaired focus and no settled ex-parent** — release resources,
  don't inspect the tree; a raising hook leaves the tree undefined and is a bug to fix, not to guard.
- **A hook-owned resource is synced from an invariant, not toggled by the hooks** — one idempotent
  sync over a condition, the sole writer; a third mutation site turns the naive pair into a 2×2.
- **A framework-invoked hook is called with `__send__`, so an override may be any visibility** —
  `handle_theme_changed`, `handle_locale_changed`, `handle_blur`, `handle_focus`; write `&:handle_theme_changed`
  instead and an app subclass that groups its override under `protected` raises mid-walk, after
  which every later component misses the hook. See `D_hook_visibility`, `D_on_blur`.
- **`Screen#close` unmounts the tree, so teardown fires `handle_detached`; a process exiting without it
  fires nothing** — these are lifecycle hooks, not destructors, and there is no `at_exit`. See `D_attach_hooks`.
- **Named slots are readers over the array, never a second copy** — `ScreenPane#popups` is the one
  exception, bounded to two mutators and pinned by a drift assertion. See `D_tree_api`.
- **A per-child *attribute* map, not a second copy of ordering** — `Box`'s constraints and
  `TabSheet`'s panes key one by identity; `children` stays the sole ordering authority. See `D_tree_api`.
- **Order is maintained at insert, so the index is part of the contract** — content at `at: 0`,
  chrome appended, popups appended; changing an index changes paint and Tab order.
- **A container with several swappable regions gives each one a {Tuile::Component::Slot}, wired at
  construction**, so the insert index never has to be computed; an empty slot keeps its rect and
  clears it rather than collapsing, and is never detached. See `D_slots`.
- **A slot swap notifies last** — `detach_child`, rewire, then `handle_child_removed(old)`, so the
  default focus repair sees the new occupant.
- **`visible = false` is as-if-detached but *in* the tree: no lifecycle hook fires**, and the rect,
  constraints, state and any running resource survive. See `D_visibility`.
- **The visible flag is ancestor-inclusive, so every *reachability* walk goes through
  `on_shown_tree`** — a plain `on_tree` plus a per-component test puts a field under a hidden panel
  back in the Tab cycle. Plain `on_tree` stays right for framework fan-out (lifecycle, theme,
  locale, invalidation), which a hidden component still gets.
- **A child's `visible=` marks *and* invalidates its parent** — it vacated cells the parent owns and
  may have changed how the parent divides its space. See `D_relayout`.
- **`Fixed[0]` is a collapse, not a hide** — it paints nothing but keeps its tab stops, its keys and
  its `spacing` gap. See `D_empty_ancestor`.

### Repaint

- **A component paints onto the {Tuile::Canvas} its `repaint` was handed — a required parameter,
  never `Screen#canvas` by name**, which carries no background and so drops inheritance silently.
- **`Canvas` is final and frozen; what varies is its {Tuile::Canvas::Backend}** — a new paint
  *target* includes that module ({Tuile::Buffer} does, unadapted); a new piece of paint *state* is a
  field on the canvas, changed only inside `with(bg_color:) { … }`, which yields a derived canvas,
  leaves the receiver alone and raises without a block. See `D_canvas`.
- **A `repaint` paints at `(0, 0)`, and a region argument is `local_rect`** — never `rect`, which
  is measured in the parent, so through a translating canvas it lands in the *neighbour*.
  `canvas_spec` greps. See `D_canvas`.
- **Components never write escape sequences and never call `Screen#repaint`** — they `invalidate`,
  and paint their styled cells when the loop asks. Keeps **a retained tree, not a redraw loop**.
- **A component must not draw outside its `rect`**, need not fill it, and cannot:
  {Tuile::Screen#clip_for} bounds it by its own rect and every ancestor's, and the canvas carries
  the fold beside `origin` in backend coordinates. So a parent may hand out a rect it will not show
  in full, and a scrolled-away child paints into nothing. See `D_clip`.
- **A component owns no part of the clip, and a re-grown hook may only narrow** — a bound a
  component could widen is not a bound, which is why `clip_rect` and `effective_clip` were built and
  deleted; the deferred shape is a container's `clip_rect_for(child)`. See `D_clip`.
- **The default `repaint` clears the gaps *and* re-invalidates the children; opting out means
  skipping the clear, never the cascade** — call `invalidate_children`, or grandchildren under a
  cleared ancestor silently vanish. See `D_repaint_cascade`, `D_component_contract`.
- **Never blank a cell you are about to paint over** — `Cell#set` only dirties on a real change, so
  a redundant clear re-emits the cell; that cost 925 bytes per unchanged `Window` repaint. See `D_progress_bar`.
- **A container assigns *every* child a rect on every pass, including when its own rect is empty** —
  a `return if rect.empty?` strands children at stale coordinates for the next full repaint. See `D_empty_ancestor`.
- **`Screen#repaint`'s drain filter is the backstop, not the fix** — it drops anything with an empty
  rect on its ancestor chain; don't promote it to a public `Component#paintable?`.
- **A layer repaints whole whenever anything beneath it repaints** — tiled invalidation re-paints
  every popup above in stacking order, per drain iteration; popups overdraw, no layer clips another.
- **A widget that paints less than its `rect` declares an `extent`** and then paints, clears,
  hit-tests and anchors against that; `nil` (undeclared) is not `rect.size`. See `D_extent`.
- **Declaring one is the whole job — `repaint` still just calls `super`**, which blanks the rect
  outside the extent. The arithmetic is each widget's own and must not vary with `bg_color`. See
  `D_boolean_fields`.
- **That saving is a *leaf*'s — a container's extent is blanked too**: an extent narrows which cells
  are yours, never whether your gaps are wiped. A container painting its own face ink overrides
  `clear_inside_extent`. See `D_extent`.
- **`Buffer#flush` is the sole quantization point** — a `Color` degrades to the terminal's depth at
  the wire, never at a declaration site, because a parsed color has no declaration site. See `D_color_depth`.

### The UI thread

- **The UI is confined to one thread: the loop's while one runs, else the thread that created the
  `Screen`.** Every mutation obeys it — `rect=`, `active=`, `content=`, `items=`, `invalidate`,
  `focused=` — and violating it raises {Tuile::Error}; background work marshals back with
  `screen.event_queue.submit { … }`. See `D_screen_lifecycle`.
- **Enforcement is transitive through `invalidate`; don't sprinkle `check_locked`.** The handful of
  explicit call sites are fail-fast methods that do real work before reaching `invalidate`
  (`grep -rn check_locked lib/tuile/component`).
- **`check_locked` must keep asking two questions** — is a loop running anywhere, and is it mine —
  because the loop need not run on the creating thread, and the gem's own specs rely on that.
- **`event_queue.submit` only *runs* the block while a loop is draining** — before the first loop it
  defers, after the last it never runs; that is why the two failure messages differ. Don't unify them.
- **There is no lock bypass in the fake.** `FakeEventQueue#running?` is false, so the real
  `check_locked` admits the example thread on its own; don't add a `FakeScreen#check_locked`.
- **`:idle` deliberately covers both ends of the screen's life** — the mutation rules are identical
  there. `:closed` is the only state that changes what is legal. See `D_screen_lifecycle`.
- **A new `Screen`-level forwarder calls `check_locked` itself** rather than relying on the
  `ScreenPane` method it delegates to; after `close` there is no pane, and `NoMethodError for nil`
  is a bad error message.
- **Resize is plumbed through the event queue** — `EventQueue` owns the sole `SIGWINCH` trap, so
  never add one in component code; react by recomputing child rects in your `relayout`.

### Focus, keys and paste

- **`screen.focused=` is the sole firing site for `handle_blur`, then `handle_focus`, then
  `scroll_to_visible`, then `Screen#on_focus_changed`** — the outer two are edge-triggered and the
  middle two are not, which is what lets a container forward focus into its content. See `D_on_blur`.
- **Scroll-into-view is a request that climbs from the child — `Component#scroll_to_visible`, a rect
  re-expressed one level at a time — and no container polls for it**; an override scrolls the
  minimum, then `super`s with the rect where that left it.
- **A focus target still showing nothing after that request is logged, never raised** — a shrunk
  terminal causes it legitimately. A *hidden* one raises, in `focused=` and `scroll_to_visible` alike.
- **`focusable?` gates *becoming* a target and is independent of `active?`** — clicking a
  {Tuile::Component::Label} must not hijack focus from the window around it.
- **{Tuile::Mouse::Router} owns every mouse walk; a component only answers handlers** — no `super`
  discipline, no hit test of its own, and a container hand-rolls nothing. See `D_mouse_dispatch`.
- **A press bubbles from the innermost component under the pointer until one claims it, and the
  claimant is grabbed** — its `handle_mouse_up` / `handle_mouse_drag` then reach it wherever the
  pointer goes, until the up, any key or the next press. A wheel notch and a move bubble the same
  way and grab nothing.
- **The router focuses the innermost `focusable?` on the path before any handler runs** — ungated by
  geometry, so a press on a widget's dead tail focuses it; the handlers bubble only along the prefix
  whose `local_extent_rect` contains the point, which is why no widget hit-tests any more. See `D_extent`.
- **A mouse event reaches a component in *its* coordinates, and `cursor_position` answers in them** —
  the router converts as it descends, and uses `to_local` for a grab; `event.x - rect.left` is
  the mistake. See `D_relative_rect`.
- **Activate on the press: no click is synthesized, and an `UpEvent` carries no button** — a release
  is losable over ssh and tmux, and the grab it reaches already knows its button. See `D_mouse_dispatch`.
- **Enter/exit and `handle_mouse_move?` need `capture_mouse: :hover`, and hover is suspended while
  grabbed** — `handle_mouse_exit` may arrive thirty seconds late or never (no terminal reports the
  pointer leaving), so it must stay cosmetic and never become a commit point.
- **The mouse is additive: no capability may be reachable only through it.** Every gesture owes a
  key that already does the job. See `D_mouse`.
- **Chrome the pointer grabs is a child component, never a column test in its owner** — the child
  inherits the router's hit test, the grab and the drag, and holds no authority: it asks through a
  listener and is told. A drag also needs `capture_mouse: :drag`. See `D_draggable_scrollbar`.
- **Both wire encodings are requested and parsed, and nothing above {Tuile::Mouse.parse} can tell
  which arrived** — SGR is asked for unconditionally (there is no capability check to build a ladder
  on) and a terminal that ignores it keeps sending X10, so the button SGR names on a release is
  dropped to match. `Keys.getkey` drains `\e[<` a byte at a time; it is variable-length, and no gulp
  width fits. See `R_mouse_reporting`.
- **A keystroke descends a fixed three-rung ladder — Tab, the global registry, then delivery — with
  no gate, predicate or mode flag anywhere in it.** The ban is on dispatch *structure* — nothing
  consulted before delivery — not on the `?` a routed handler's name carries. See `D_key_dispatch`.
- **Tab and Shift+Tab are claimed above everything**, so focus can never be trapped; no component
  ever sees them, not even a `TextArea`, and the registry rejects Tab bindings.
- **The registry is the only mechanism above the tree and nothing suppresses it**, so it accepts
  only keys no widget can need — printables and `Screen::EDITING_KEYS` raise *at registration*. A
  runtime gate here is the wart `D_key_dispatch` deleted; reserve a key, don't gate it.
- **Delivery bubbles *up* to the scope root, `ScreenPane#key_scope` (topmost modal popup, else content)** —
  the only home for scope-wide keys. There is deliberately **no downward delegation**: neither
  `Layout#handle_key?` nor `Window#handle_key?` exists.
- **Below all three rungs, an unhandled `q` or ESC stops the loop**, so a scope root binding bare
  `q` must return `true` or the app quits. See `D_quit_key`.
- **There is no framework jump-to-widget mnemonic** — `key_shortcut` and the capture phase were
  deleted in 0.10.0; an app writes a `handle_key?` on its content layout. Re-grow only as sugar over
  an ancestor's `handle_key?`, never as a dispatch phase. See `D_key_dispatch`.
- **There is no general key *callback*** — override `handle_key?` and `super` for the rest; one
  callback slot cannot be shared, and a pre-dispatch veto is the capture phase again. The *named*
  ones stay (`on_enter`, `on_key_up`, `on_key_down`, `on_escape`), each claiming one key. See `D_no_key_interceptor`.
- **`Screen#cursor_position` is about the cursor only** — it is not a routing signal.
- **A component receives keys only while on the focus chain**, so `handle_key?` acts on the key alone
  and never gates on its own `active?`.
- **A paste is its own event: it goes to `Screen#focused` and stops** — no bubble, never replayed as
  keys, and unhandled text is dropped. See `D_bracketed_paste`.
- **`Keys.read_paste` reads a byte at a time to the terminator** — a chunked read over-reads past
  `\e[201~` and swallows the keys typed behind the paste.
- **Two sanitizing layers, and the line is deliberate** — `Keys.normalize_paste` fixes *terminal*
  artifacts, `preprocess_paste` decides what a *text buffer* may hold; a new rule goes in whichever
  owns the reason, never both.
- **An input filter goes on `insert_text`, never on a key seam** — a key handler never sees a paste,
  which is how all three numeric fields shipped broken until 0.15.0. See `D_input_filters`.
- **Popup focus repair has a fixed order, and an out-of-order close rewrites the snapshots** so no
  saved focus strands inside a detached popup ({Tuile::ScreenPane#handle_child_removed} carries the
  order; read `screen_pane_spec`'s regression cases before refactoring it).

### Layout

- **A component never advertises how big it wants to be; its parent assigns its `rect`.** No
  `content_size`, no `Sizing`, no min/preferred/max, no shrink-to-fit — a container computes
  rectangles in plain Ruby in its `relayout`. Keeps the retained-tree promise; See `D_box_layouts`.
- **{Tuile::Component#relayout} is the sole place a container assigns its children's rects** —
  *`relayout` : geometry :: `repaint` : ink*: framework-invoked, idempotent, never called directly.
  Every other input to it ends in `invalidate_layout`. See `D_relayout`.
- **A mutation marks; nothing lays out inline** — `Screen#dispatch` settles after every event, so no
  pass sees a container mid-configuration. A rect read in the *same* turn that dirtied it is stale;
  `Component#flush_layout` is the force-now. See `D_deferred_layout`.
- **A detached tree defers too, and remembers** — the mark survives on the component,
  `handle_attached` hands it to the {Tuile::Screen}, and a tree with no screen gets its rects from an
  explicit `flush_layout`. No second, synchronous mode, and a sixth force-now `flush_layout` in
  `lib/` is the falsifier. See `D_deferred_layout`.
- **A `rect` is measured inside its parent, and a component's own coordinates are one space** — what
  it paints in *and* what its children sit in, so a container divides `local_rect` and adds no
  offset of its own; `component_spec` greps for one. See `D_relative_rect`.
- **Screen space is asked for by name** — `absolute_rect`, `absolute_extent_rect`, `to_screen`,
  `to_local`; derived per call, never cached, three callers (the canvas origin, an overlay's anchor,
  a spec reading the buffer). See `D_relative_rect`.
- **`size` / `width` / `height` are reports, not requests** — shorthand for the assigned `Rect`
  field, with deliberately no writer, and no container consults them. See `D_declared_size`.
- **The deleted bottom-up channel must not return under a new name.** Re-grow rule: measurement may
  come back only as an *optional, read-only, caller-side query*, never as a channel the framework
  consults. A box a component *asks for* is spelled `declared_size`, not `size`.
- **The pane owns no chrome and Tuile reserves no row** — `content` gets the whole terminal, and an
  app drives its own status line from `Screen#on_focus_changed`. A hint channel may come back only
  as a query the app *pulls*, never as a framework-placed row. See `D_status_bar`.

### Theme and locale

- **Read the theme at paint time; never cache a token in an ivar** — `theme=` restyles everything
  through one invalidate-all pass, and a cached accent strands on the old scheme.
- **A theme carries accents only — there is no global bg/fg token.** Non-accent cells inherit the
  terminal default. See `D_bg_inherit`, `D_no_hint_color`.
- **A chrome token exists only for a color *built-in chrome* paints, in more than one place** — a
  color an app applies to its own text is a `custom` token, one a component varies per instance is a
  slot taking a `Theme::Ref`. The test is who paints it, not how specific the name sounds. See `D_color_slots`.
- **`handle_theme_changed` is for app-rendered *content*** — a {Tuile::StyledString} bakes its colors at
  construction and only the app knows which were theme-derived; built-in chrome and `Theme::Ref`
  backgrounds resolve live and skip it.
- **Don't make {Tuile::StyledString} theme-aware** — it is a frozen value type with a
  `parse(to_ansi(x)) == x` round-trip and no `Screen` dependency; a theme ref breaks all three.
- **Startup scheme detection stays in `Screen#initialize`** — the OSC 11 reply lands on stdin, which
  the key thread owns once the loop runs.
- **The live background re-probe is three files agreeing**: the query is written from the event-loop
  thread (which also owns `emit`), `Keys.getkey` drains `\e]` replies a byte at a time, and
  `Screen#print` flushes. See `D_background_rgb`.
- **{Tuile::Locale} holds formatting *conventions* and never prose** — that sentence is what keeps
  it ~8 members instead of an i18n subsystem, and it is the gate a new member passes. See `D_locale`.
- **A component reads `Component#locale`, never `screen.locale`** — the protected reader answers
  `Locale::ISO` when there is no screen, which is what keeps the screen-free-tree guarantee true.
- **A locale-derived knob is nil-means-inherit**; one that *snapshots* at construction silently
  stops following, and nothing raises.
- **Something *pushed* owes a `handle_locale_changed`** — anything pulled at paint or parse time needs
  no hook, but a value written into another widget when the conventions were last read does.
- **Detection normalizes at the boundary, never at the consumer** — and note the asymmetry: a probe
  widens silently (no author to tell), an assignment raises (there is one).

### Background

- **A widget with a well owes an `extent`, and a composer owes `default_bg_color` and its face's
  `BG_INHERIT` as a pair** — either half alone fails silently, and no spec catches it. The resolved
  chain is `design/architecture.md`'s. See `D_bg_surface`.
- **There is one background knob and no foreground one** — `Label#bg` and `content_fg_color` were
  each built and deleted; app-authored content carries its colors in its own `StyledString`. See
  `D_bg_surface`.

### Text and glyph width

- **Never measure with `String#length` and never hand-roll a width table** — use
  `StyledString#display_width` / `slice` / `ellipsize`, so the framework shares one answer and one
  migration point. See `D_ambiguous_width`.
- **Tuile bets globally that terminals render East-Asian-Ambiguous glyphs as one column**, and
  nothing is designed to survive them measuring 2. See `D_ambiguous_width`.
- **A new component defaults to ASCII when the pretty glyph is Ambiguous**, offering the glyph as an
  opt-in knob — that is what keeps the inventory enumerable and the bet cheap to reverse.
- **A glyph knob validates at assignment that it took one cluster, one column wide** — a wide glyph
  pushes every painted row past `rect.width`, silently. See `D_scrollbar_ink`.
- **Every `Unicode::DisplayWidth.of` in the gem passes `emoji: StyledString::EMOJI_WIDTH`** — audit
  with `grep -rn 'DisplayWidth.of' lib`; a call site without it is a bug. See `D_cluster_width`.
- **A cluster is not capped at two columns** — a non-RGI ZWJ sequence measures 4, which is why
  `Buffer#put_char` models an arbitrary continuation run.
- **Never `each_char` to measure or slice** — a per-character walk mis-totals a sequence and cuts
  clusters apart, and a slice that drops a combining mark returns a *different letter*.
- **The two measurement routes agree, and a spec pins them together** — `display_width` measures a
  whole string in one gem call, `Buffer` measures cluster-by-cluster as it paints; don't "unify"
  them onto the slow path.
- **A text index is not a column; convert, never conflate.** A caret counts characters into a
  `String`; a rect, a cursor position and a `Mouse::Event` count columns. Every width measurement in
  an input goes through `columns_of`. See `D_text_field_axes`, `D_text_area_columns`.
- **A wrap iterates grapheme clusters and every branch advances by at least one** — `"\r\n"` is a
  single cluster, and a branch that measures zero without consuming hangs the UI thread outright.
- **The caret counts characters but is always on a cluster boundary**, which is what lets every edit
  move or delete exactly one cluster with no per-script rules. See `D_cluster_caret`.
- **Ink overflow is a different problem** — a glyph can measure 1 everywhere and still be *drawn*
  wider by a fallback font; that is font coverage, not width.

### Nomenclature

Definitions are `design/terminology.md`; the choice and the roads not taken are
`D_scroll_nomenclature`.

- **`row` is the terminal grid unit, everywhere, no exceptions** — a wrapped unit of text *is* a
  row, and `line` means exactly what `String#lines` returns and is never a coordinate.
- **An object with one row space leaves `row` unqualified; one holding both qualifies the viewport
  one** (`row_in_viewport`), so its bare `row` and its `scroll_top_row` are content-space.
- **A new component must not invent a third vocabulary** — every scroller says `scroll_top_row` /
  `viewport_rows` / `row_in_viewport`, a horizontal one says `left_column` and keeps it private, and
  a widget holding domain objects says `items` with a `renderer`.
- **The `on_` prefix is reserved for listener slots** — never a traversal or a predicate; a walk is
  `walk_` (`walk_tree`, `walk_shown_tree`) and a thread test reads `in_loop_thread?`. `each_` is
  wrong for the walks: they take a block and return nothing.
- **`spec/tuile/nomenclature_spec.rb` is the guard and holds no allowlist** — if a rename needs an
  exception there, the rename is wrong.

### Geometry

- **`Rect#contains?` uses half-open edges** (right and bottom exclusive) and **`Rect#empty?`
  includes a negative width**; `Point` / `Size` / `Rect` are frozen `Data.define` value types.

## Module map

One line per directory; `ls` is the file index, and each class's rdoc says what it is.

- `lib/tuile/` — the runtime: `Screen`, `ScreenPane`, `Component`, the queue, the buffer, theme,
  locale, the value types.
- `lib/tuile/component/` — the widget set, `Tuile::Component::*`: fields, lists, overlays.
  Rules: `lib/tuile/component/AGENTS.md`
- `lib/tuile/component/layout/` — the box layouts: `Box`, `Vertical`, `Horizontal`.
- `spec/` — one spec per source file mirroring `lib/tuile/`, the contract suite, and the PTY-based
  system tests for `examples/`. Rules: `spec/AGENTS.md`
- `book/` — the guide, read cover to cover: ten chapters plus `book/README.md`.
- `design/` — the lazy docs; see *Design docs* above.
- `examples/` — runnable demos: `hello_world.rb`, `sampler.rb`, `file_commander.rb`.
- `benchmark/` — display-width and repaint micro-benchmarks (`rake benchmark`).
- `sig/tuile.rbs` — sord-generated RBS signatures; `rake sig` regenerates, CI fails on drift.
- `tasks/` — extra rake tasks, loaded by the `Rakefile`.

## Conventions

- **Ruby on the TTY toolkit, nothing else.** `tty-cursor` and `tty-screen` are the substrate;
  Tuile owns the tree, the loop, the back buffer and the theme, and inherits the terminal's
  palette, font and glyph widths rather than overriding them.
- **Zeitwerk loads everything from `lib/`; never `require_relative` inside the gem.** Explicit
  requires bypass the loader and create dual-load hazards. The one in-file `require` that must *not*
  be hoisted is `big_decimal_field.rb`'s `require "bigdecimal"` — Tuile's single optional dependency,
  cost-free only because Zeitwerk loads that file lazily. See `D_bigdecimal_field`.
- **One top-level constant per file**: `lib/tuile/foo.rb` defines exactly `Tuile::Foo`. Nested
  constants inside it are fine; a sibling top-level class gets its own file.
- **Log through `Tuile.logger`, never `$log` or `TTY::Logger` directly.** The default is
  `Logger.new(IO::NULL)`, so the gem is silent unless the host sets one.
- **Reach the singleton through `Screen.instance` / `.close` / `.fake`, never `@@instance`** — the
  class variable is part of the singleton-survives-subclassing contract (`FakeScreen < Screen`).
- **Ruby 3.3+.** Rubocop's `Metrics/*` size cops are violated freely and that is accepted.
- **Pre-1.0: break APIs freely**, with a `**Breaking:**` CHANGELOG line carrying the migration —
  no compat shims, no deprecation cycle.
- **A public signature change ships the regenerated `sig/tuile.rbs` in the same commit** — CI runs
  `rake sig` and fails on any `git diff` under `sig/`.

## Commands

```sh
bundle exec rake check                       # spec + rubocop + sig + design tripwires (the default task)
bundle exec rake spec                        # all specs (unit + PTY examples)
bundle exec rspec spec/tuile/list_spec.rb    # one file
bundle exec rspec spec/tuile/list_spec.rb:42 # one example
COVERAGE=true bundle exec rake spec          # + SimpleCov report at coverage/index.html
bundle exec rubocop                          # lint alone
bundle exec rake sig                         # regenerate + validate sig/tuile.rbs (commit the result)
bundle exec rake design_tripwires            # the doc-layer checks alone
bundle exec rake benchmark                   # display-width / repaint micro-benchmarks
```

`rake check` is what to run before committing; it is the same suite the release gate re-runs, and
`rake sig` can dirty the tree. CI (`.github/workflows/ci.yml`) runs `rspec` on Ruby 3.3 / 3.4 / 4.0
and a separate `check` job that also fails on `sig/` drift. Coverage is not gated — treat the
number as a signal. The release runbook is `design/releasing.md`.

## Skills this project follows

- **Component-oriented programming:** self-sufficient components that may reach a service directly,
  no MVC/MVP/MVVM layers, inherit to *be* a component and never to share code; the `cop` skill has
  the rules.

## Maintenance of this file

Loaded every turn; cap 36 KB, a directory's own `AGENTS.md` 10 KB. Over it, in this order:
delete what has no home — status, history, class lists, what the code already says; trim each
line to its fact plus one clause and send the explanation home — why → `design/decisions.md`,
how across symbols → `design/architecture.md`, how in one symbol → its rdoc, what upstream does
→ `design/research.md`, a learner's path → `book/`; only then a directory's own `AGENTS.md`,
peripheral directories first, never the core. Never paraphrase a lazy entry into a line here, and
never rewrite the whole file shorter — both are lossy. `design/verify_design_tripwires.sh` (also
`rake design_tripwires`, part of `rake check`) checks the caps, the cites, the question headings
and the `CLAUDE.md` symlinks. `CLAUDE.md` is a symlink to `AGENTS.md` beside every one of them —
never a file with content, even though Claude Code's `#` shortcut and `/init` target it by name.

*Doc layout seeded from the `design-docs` skill (mvysny, `~/.claude/skills`); this project needs
nothing from it.*
