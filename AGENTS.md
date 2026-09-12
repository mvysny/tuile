# AGENTS.md

**This file is an index, not a manual.** It is loaded on every turn of every session, so it holds
only what a contributor breaks *from a distance* — a cross-cutting invariant, the map that says
where to look, the conventions that would otherwise be guessed — and nothing else. Each entry is
one line: the rule, at most one clause of what goes wrong, and See `D_<slug>` when a decision entry
carries the argument. **The explanation is never here**: the per-symbol truth is the rdoc, the
*why we chose it* is `design/decisions.md`, the concept is `book/`. Adding a line? Copy the shape
of its neighbour and trim to the section's first line. **Cap: 34 KB here, 10 KB in a nested file**
(`git ls-files '*AGENTS.md'` lists them) — over it, *move, don't summarise*: a compressed `D_`
entry reads like a summary and is really a third copy; `design/verify_design_tripwires.sh` checks.
`CLAUDE.md` is exactly the line `@AGENTS.md`, beside every `AGENTS.md`; nothing else goes in it,
even though Claude Code's `#` shortcut and `/init` target it by name.

## What Tuile is

A small component-oriented terminal-UI framework for Ruby, built on the TTY toolkit
(`tty-cursor`, `tty-screen`). An app builds a tree of {Tuile::Component}s under a singleton
{Tuile::Screen}, which runs the event loop, dispatches keys and mouse, and repaints what was
invalidated. Tuile owns the tree, the loop, the back buffer and the theme; the terminal owns the
palette, the font and the glyph widths, and Tuile inherits rather than overrides them. The name
is French for "roof tile". Published at <https://github.com/mvysny/tuile>; extracted from
[virtui](https://github.com/mvysny/virtui)'s `lib/ttyui/` in 0.1.0, so virtui shows up in the
commit history.

## Design docs

Rationale and reference live under `design/`. Each file has one audience and *what it is allowed
to own*; every file's preamble states its entry shape and how to cite it. This section is the
whole contract — nothing outside the repo is needed to follow it.

| File | Owns | Loaded? |
|---|---|---|
| `README.md` | a prospective user at the front door: positioning, install, one hello-world, routing onward | — |
| `AGENTS.md` (this) | what you must not break from a distance; the module map; this table | **every turn** |
| `book/` | a learner reading in order: the *concepts* and the *why*, narrative, order-dependent | — |
| rdoc / YARD headers | per-symbol technical truth, complete standalone on rubydoc.info; defers *motivation* to the book, never *usage* | source of truth |
| `design/requirements.md` | what Tuile promises — `R_` entries, stated not argued, owner-written | lazy |
| `design/architecture.md` | **the map** of the code as it is — wiring, flows, where to start; **the code is the truth** | lazy |
| `design/decisions.md` | why this and not that — `D_` entries, roads not taken | lazy |
| `design/research.md` | verified facts about the terminal and the gems we sit on, each claim `[docs]` / `[src]` / `[verified]` / `[unverified]` | lazy |
| `design/comparison.md` | the neighbouring toolkits sized up as wholes, and what is reachable from Ruby | lazy |
| `design/terminology.md` | the house vocabulary: one line per term, looked up by word — definitions only | lazy |
| `design/releasing.md` | the release runbook | lazy |
| `design/ideas/` | not yet decided — one file per idea, `ls` is the index, deleted on graduation | transient |
| `CHANGELOG.md` | what changed and what you must do about it — one sentence per entry, append-only per release | — |

Rules that keep the split from drifting:

- **One home per fact; the others link.** A one-line restatement that saves a jump is fine — repeat
  the *fact*, defer the *explanation*. Compressing a `D_` entry into a bullet here is a third copy.
- **`decisions.md` argues, `requirements.md` states, `research.md` is about *them* not us,
  `architecture.md` and `comparison.md` describe and never argue.** A paragraph explaining *why* in
  any file but `decisions.md` has drifted; move it and cite the `D_`. So don't migrate the survey
  tables out of `decisions.md`, and don't argue a Tuile decision in `comparison.md`.
- **A `D_` is earned by what happened, not by having had an alternative:** it shaped what Tuile is
  (reverse it and the README's first paragraph changes), or it cost research the next person would
  otherwise redo. A testing library, a coverage tool, the CI host, a version bump — a comment at
  the site of the choice, never an entry. Only decisions already taken; ideas, TODOs and open
  questions go to `design/ideas/`. A shipped decision that is reversed keeps its entry as a
  tombstone. Nothing about `design/` itself or its tooling is an entry.
- **An `R_` is a promise the README's pitch makes, made an official rule — and the owner writes
  it.** An agent never adds, edits or retires one; it proposes, in conversation or as a drafted
  entry in `design/ideas/`. The ruler: allow the opposite everywhere — is it still the pitched
  project? "A retained tree, not a redraw loop" → no → `R_`. "Every UI mutation on the loop's
  thread", "every background goes through `draw_text`" → broken in places, still Tuile → an
  *invariant*: one line in this file, named in the promise's *Enforced by*.
- **An invariant is one line here, and nothing more:** the rule, at most one clause of consequence,
  `T_<slug>` if tripwired, See `D_<slug>` only when a `D_` exists — no fork, no cite; the agent has
  the code. Exceptions live in the owning directory's `AGENTS.md`. A line that will not fit belongs
  in the chokepoint's rdoc.
- **A CHANGELOG entry is one sentence** — `Add` / `Fix` / `**Breaking:**`, the symbol, what
  changed, ≈40 words; a trailing See `D_<slug>` doesn't count. A breaking entry earns a second sentence,
  for the migration only. Group `Add`, then `Fix`, then `**Breaking:**`; a themed release may carry
  a ≤3-sentence preamble under its version heading, once.
- **Slugs:** `D_` decisions, `R_` requirements, `T_` tripwires (cited from a requirement's
  *Enforced by* or a seam line here, defined by the check), `Q_` open questions inside
  `design/ideas/` only — a durable doc never cites a `Q_`. Underscores throughout, backticked in
  prose, cited by slug never by position; `grep '^## D_' design/decisions.md` is the index.
- **`design/verify_design_tripwires.sh`** (also `rake design_tripwires`, part of `rake check`) fails
  on any cited `D_` / `R_` without a heading, a `T_` without a check, an oversized `AGENTS.md`, or a
  `CLAUDE.md` that isn't the shim.

*Layout seeded from the `design-docs` and `agents-md` skills (mvysny, `~/.claude/skills`); this
project needs nothing from them.*

### Ideas & their graduation

An idea graduates the moment it is acted on, and graduation is not done until its file (and any
sidecar folder `design/ideas/<name>/`) is gone. Where the lasting nuggets land:

- the choice made + the alternatives rejected → a `D_` entry if it passes the gate; else a comment
  at the site of the choice
- a promise the pitch makes → a proposal for the owner, who writes the `R_`; the invariant that
  keeps one → a line in this file
- a new component, or a changed responsibility → one line in the module map — and a component owes
  **five** registrations: rdoc, the CHANGELOG, its directory's map line, the README's Components
  table, and `component_contract_spec`'s catalog (that last one fails the build rather than rotting)
- how the pieces work together — wiring, a flow crossing several → `design/architecture.md`
- verified behaviour of the terminal or a gem we sit on → `design/research.md`, with a marker
- how one class works and why it is shaped so → its rdoc
- what a learner needs in order → `book/`; what a user needs at the door → `README.md`
- a house word's definition → `design/terminology.md`
- a cross-cutting invariant → one line in this file
- work deferred *as a consequence of a logged decision* → that entry's *Consequences*

## Invariants

Widget-set recipes (a new field, a new group, an overlay, a `Box` constraint) are in
`lib/tuile/component/AGENTS.md`; testing invariants are in `spec/AGENTS.md`.

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
- **`parent=` is the sole firing site for `on_attached` / `on_detached`**, at most once per
  component per transition, whatever the hooks do to the tree. See `D_attach_hooks`.
- **A hook may assume no geometry, no repaired focus and no settled ex-parent** — release resources,
  don't inspect the tree; a raising hook leaves the tree undefined and is a bug to fix, not to guard.
- **A hook-owned resource is synced from an invariant, not toggled by the hooks** — one idempotent
  sync over a condition, the sole writer; a third mutation site turns the naive pair into a 2×2.
- **A framework-invoked hook is called with `__send__`, so an override may be any visibility** —
  `on_theme_changed`, `on_locale_changed`, `on_blur`, `on_focus`; write `&:on_theme_changed`
  instead and an app subclass that groups its override under `protected` raises mid-walk, after
  which every later component misses the hook. See `D_hook_visibility`, `D_on_blur`.
- **`Screen#close` unmounts the tree, so teardown fires `on_detached`; a process exiting without it
  fires nothing** — these are lifecycle hooks, not destructors, and there is no `at_exit`. See `D_attach_hooks`.
- **Named slots are readers over the array, never a second copy** — `ScreenPane#popups` is the one
  exception, bounded to two mutators and pinned by a drift assertion. See `D_tree_api`.
- **Order is maintained at insert, so the index is part of the contract** — content at `at: 0`,
  chrome appended, popups appended; changing an index changes paint and Tab order.
- **A container with several swappable regions gives each one a {Tuile::Component::Slot}, wired at
  construction**, so the insert index never has to be computed; an empty slot keeps its rect and
  clears it rather than collapsing, and is never detached. See `D_slots`.
- **A slot swap notifies last** — `detach_child`, rewire, then `on_child_removed(old)`, so the
  default focus repair sees the new occupant.
- **`visible = false` is as-if-detached but *in* the tree: no lifecycle hook fires**, and the rect,
  constraints, state and any running resource survive. See `D_visibility`.
- **The visible flag is ancestor-inclusive, so every *reachability* walk goes through
  `on_shown_tree`** — a plain `on_tree` plus a per-component test puts a field under a hidden panel
  back in the Tab cycle. Plain `on_tree` stays right for framework fan-out (lifecycle, theme,
  locale, invalidation), which a hidden component still gets.
- **A container with layout arithmetic owes an `on_child_visibility_changed`**, or a hidden child
  keeps its slot and its gap.
- **`Fixed[0]` is a collapse, not a hide** — it paints nothing but keeps its tab stops, its keys and
  its `spacing` gap. See `D_empty_ancestor`.

### Repaint

- **Components never write escape sequences and never call `Screen#repaint`** — they `invalidate`,
  and paint styled cells into `Screen#buffer` when the loop asks. Keeps `R_retained_tree`.
- **A component must not draw outside its `rect`**, and need not fill it.
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
  every popup above in stacking order, per drain iteration; popups overdraw, there is no clipping.
- **A widget that paints less than its `rect` declares an `extent`** and then paints, clears,
  hit-tests and anchors against that; `nil` (undeclared) is not `rect.size`. See `D_extent`.
- **Declaring one is the whole job — `repaint` still just calls `super`**, which blanks the rect
  outside the extent, so the widget stops re-emitting cells it is about to redraw. The arithmetic
  is each widget's own and must not vary with `bg_color`. See `D_boolean_fields`.
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
  never add one in component code; react by recomputing child rects in your `rect=`.

### Focus, keys and paste

- **`screen.focused=` is the sole firing site for `on_blur`, then `on_focus`, then
  `Screen#on_focus_changed`** — the outer two are edge-triggered, `on_focus` is not, which is what
  lets a container forward focus into its content. See `D_on_blur`.
- **`focusable?` gates *becoming* a target and is independent of `active?`** — clicking a
  {Tuile::Component::Label} must not hijack focus from the window around it.
- **`Component#handle_mouse` routes down the tree by default, so a new container hand-rolls
  nothing** — the walk lived three times before 0.14.0. See `D_slots`.
- **A widget that resolves clicks calls `super` *first*, then acts** — `super` is what fires
  `on_blur`, a commit point, so acting first silently drops the abandoned field's last edit; then
  hit-test `extent_rect`, not `rect`.
- **The mouse is additive: no capability may be reachable only through it.** Every gesture owes a
  key that already does the job. See `D_mouse`.
- **A keystroke descends a fixed three-rung ladder — Tab, the global registry, then delivery — with
  no gate, predicate or mode flag anywhere in it.** See `D_key_dispatch`.
- **Tab and Shift+Tab are claimed above everything**, so focus can never be trapped; no component
  ever sees them, not even a `TextArea`, and the registry rejects Tab bindings.
- **The registry is the only mechanism above the tree and nothing suppresses it**, so it accepts
  only keys no widget can need — printables and `Screen::EDITING_KEYS` raise *at registration*. A
  runtime gate here is the wart `D_key_dispatch` deleted; reserve a key, don't gate it.
- **Delivery bubbles *up* to the scope root (the topmost modal popup, else the tiled content)** —
  the only home for scope-wide keys. There is deliberately **no downward delegation**: neither
  `Layout#handle_key` nor `Window#handle_key` exists.
- **Below all three rungs, an unhandled `q` or ESC stops the loop**, so a scope root binding bare
  `q` must return `true` or the app quits. See `D_quit_key`.
- **There is no framework jump-to-widget mnemonic** — `key_shortcut` and the capture phase were
  deleted in 0.10.0; an app writes a `handle_key` on its content layout. Re-grow only as sugar over
  an ancestor's `handle_key`, never as a dispatch phase. See `D_key_dispatch`.
- **There is no general key *callback*** — override `handle_key` and `super` for the rest; one
  callback slot cannot be shared, and a pre-dispatch veto is the capture phase again. The *named*
  ones stay (`on_enter`, `on_key_up`, `on_key_down`, `on_escape`), each claiming one key. See `D_no_key_interceptor`.
- **`Screen#cursor_position` is about the cursor only** — it is not a routing signal.
- **A component receives keys only while on the focus chain**, so `handle_key` acts on the key alone
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
  saved focus strands inside a detached popup ({Tuile::ScreenPane#on_child_removed} carries the
  order; read `screen_pane_spec`'s regression cases before refactoring it).

### Layout

- **A component never advertises how big it wants to be; its parent assigns its `rect`.** No
  `content_size`, no `Sizing`, no min/preferred/max, no shrink-to-fit — a container computes
  rectangles in plain Ruby in its `rect=`. Keeps `R_retained_tree`; See `D_box_layouts`.
- **`size` / `width` / `height` are reports, not requests** — shorthand for the assigned `Rect`
  field, with deliberately no writer, and no container consults them. See `D_declared_size`.
- **The deleted bottom-up channel must not return under a new name.** Re-grow rule: measurement may
  come back only as an *optional, read-only, caller-side query*, never as a channel the framework
  consults. A box a component *asks for* is spelled `declared_size`, not `size`.
- **The pane owns no chrome and Tuile reserves no row** — `content` gets the whole terminal, and an
  app drives its own status line from `Screen#on_focus_changed=`. A hint channel may come back only
  as a query the app *pulls*, never as a framework-placed row. See `D_status_bar`.

### Theme and locale

- **Read the theme at paint time; never cache a token in an ivar** — `theme=` restyles everything
  through one invalidate-all pass, and a cached accent strands on the old scheme.
- **A theme carries accents only — there is no global bg/fg token.** Non-accent cells inherit the
  terminal default. See `D_bg_inherit`, `D_no_hint_color`.
- **A chrome token exists only for a color *built-in chrome* paints, in more than one place** — a
  color an app applies to its own text is a `custom` token, one a component varies per instance is a
  slot taking a `Theme::Ref`. The test is who paints it, not how specific the name sounds. See `D_color_slots`.
- **`on_theme_changed` is for app-rendered *content*** — a {Tuile::StyledString} bakes its colors at
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
- **Something *pushed* owes an `on_locale_changed`** — anything pulled at paint or parse time needs
  no hook, but a value written into another widget when the conventions were last read does.
- **Detection normalizes at the boundary, never at the consumer** — and note the asymmetry: a probe
  widens silently (no author to tell), an assignment raises (there is one).

### Background

- **The background chain resolves at paint time, in four levels** — `error_bg_color || @bg_color ||
  default_bg_color || parent.effective` — with `BG_INHERIT` skipping the widget's own level. Never
  cache the result. See `D_bg_surface`, `D_bg_inherit`.
- **Terminal cells are opaque, so the effective bg must be baked into every painted cell** —
  "parent fills, child paints on top" does not yield inherited text.
- **Self-painters paint through `Component#draw_text` / `#draw_char`, not `screen.buffer.set_*`** —
  that is the single choke point applying the chain, and bypassing it drops inheritance.
- **Exactly one background well per widget, and the owned widget is *told*** — a composer declares
  `default_bg_color` *and* sets its face `bg_color = BG_INHERIT`; never derive this from position in
  the tree. See `D_bg_surface`.
- **A widget's own background colors its `extent`, never the dead tail**, or a one-row field inside a
  `Popup` floods 24 rows.
- **`bg_color=` invalidates the whole subtree**, since inheriting descendants must re-resolve;
  over-invalidation is free on the wire.
- **`BG_STATES` is closed and framework-defined** — a key is added when Tuile grows the *state*,
  never so an app can invent one; that is the CSS pseudo-class road `D_bg_surface` declined.
- **There is one background knob and no foreground one** — `Label#bg` was deleted, and
  `content_fg_color` was built and deleted: app-authored content carries its colors in its own
  `StyledString`. See `D_bg_surface`, `D_has_validation`.

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
  `String`; a rect, a cursor position and a `MouseEvent` count columns. Every width measurement in
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
- **`spec/tuile/nomenclature_spec.rb` is the guard and holds no allowlist** — if a rename needs an
  exception there, the rename is wrong.

### Geometry

- **`Rect#contains?` uses half-open edges** (right and bottom exclusive) and **`Rect#empty?`
  includes a negative width**; `Point` / `Size` / `Rect` are frozen `Data.define` value types.

## Module map

One line per directory; the per-file map is in that directory's own `AGENTS.md`.

- `lib/tuile/` — the runtime: `Screen`, `ScreenPane`, `Component`, the queue, the buffer, theme,
  locale, the value types.
- `lib/tuile/component/` — the widget set, `Tuile::Component::*`: layouts, fields, lists, overlays.
- `spec/tuile/` — one spec per source file, mirroring `lib/tuile/`, plus the contract suite.
- `spec/examples/` — PTY-based system tests for the `examples/` scripts (Linux/macOS only).
- `book/` — the guide, read cover to cover: ten chapters plus `book/README.md`.
- `design/` — the lazy docs; see *Design docs* above.
- `examples/` — runnable demos: `hello_world.rb`, `sampler.rb`, `file_commander.rb`.
- `benchmark/` — display-width and repaint micro-benchmarks (`rake benchmark`).
- `sig/tuile.rbs` — sord-generated RBS signatures; `rake sig` regenerates, CI fails on drift.
- `tasks/` — extra rake tasks, loaded by the `Rakefile`.

## Conventions

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

## Skills

- **Component-oriented programming:** self-sufficient components that may reach a service directly,
  no MVC/MVP/MVVM layers, inherit to *be* a component and never to share code; the `cop` skill has
  the rules.
