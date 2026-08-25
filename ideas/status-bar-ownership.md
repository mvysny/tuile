# The status bar belongs to the app, not the framework

**Status:** decided 2026-08-25, unimplemented. Supersedes this file's previous
contents ("The tiled status-bar hint never reaches the widget", 2026-08-24),
which proposed *fixing* the hint plumbing. The survey done to pick a fix
concluded the plumbing should be **deleted** instead, and the bar handed to the
app behind a focus-change hook.

## The original gap — now evidence, not the problem

`Screen#refresh_status_bar` builds the tiled hint from `active_window` — the
innermost active {Window} — which doesn't override `keyboard_hint`, so nothing
walks down to the *focused* component. Every widget-level hint is dead in a
tiled pane.

It is wider than "tiled". `Popup#keyboard_hint` forwards to
`@content&.keyboard_hint` — the *direct* content only — so a `Select` inside a
`Vertical` inside a `Popup` (the normal case) is just as dead. Of the seven
built-in `keyboard_hint` implementations, only `Window`, `Popup` and
`PickerWindow` (a `Window`) are reachable in any configuration. `MenuBar`,
`Tabs`, `Select` and `ComboBox` are unreachable **everywhere**.

## What the downstream survey found

Two consumers, using **disjoint halves** of the mechanism — which is why nobody
noticed the above.

- **virtui** — the `Window#keyboard_hint` path, idiomatically. `SystemWindow`
  (`"h Help"`) and `VmWindow` (`"p Power  v run Viewer  m Memory  d toggle Disk
  stat  / Search"`, switching to `"ESC close search"` while searching). Every
  advertised key is one that window handles in its own `handle_key`. Registers
  zero global shortcuts. `examples/file_commander.rb` uses the same path.
- **pikuri-tui** — the `register_global_shortcut(hint:)` path, exclusively.
  Three apps (chat/code/computer) plus the shared log UI, all feeding
  `^K menu` / `^K ⚠ menu (2)` / `^C cancel` through the registry, all pinned by
  specs. Never overrides `keyboard_hint` anywhere.

**Neither app has ever wanted a *widget's* hint.** virtui advertises
window-level app keys; pikuri advertises global app keys. Across four apps,
zero demand for `Select`'s or `ComboBox`'s keys in a bar. So the seam is not
merely unused by four of its seven implementors — the thing it was designed to
carry is something no app wants carried.

## The two smoking guns

**1. An app routes presentation updates through the dispatch registry.**
`pikuri-tui/lib/shared/log/ui.rb:88` re-registers a global keybinding to update
a status-bar string, and documents the technique:

```ruby
# {Tuile::Screen} replaces the binding in place on re-register, so this is
# also how the hint stays in sync with the counter — #on_error_logged and
# #reset_error_count both call back here (without a block) after touching
# the count.
def install_shortcut(&open_menu)
  @open_menu = open_menu if open_menu
  @screen.register_global_shortcut(Tuile::Keys::CTRL_K, hint: menu_hint, &@open_menu)
end
```

The bar is write-only from the app's side, so a *text* change had to be
expressed as a *binding* change. That is the design inverted, not a missing
feature.

**2. The one reachable widget hint is also stale.** `MenuBar#keyboard_hint`
switches to `"↑↓ move  ⏎ select"` when the cascade opens — but the cascade is a
non-focusable `ListDropdown`, so focus never changes, so `refresh_status_bar`
never runs (it fires from `focused=`, `theme=` and the two registry mutators,
not from `add_popup`). Opening a menu doesn't update the bar; *closing* it does,
via focus repair. Dead twice over: unreachable, and asymmetrically stale even if
it were reachable.

Worth recording so it isn't re-proposed: MenuBar's hint isn't too *long*
(`←→ menu  ⏎ open`) — it's redundant, and it changes as you navigate, so a
working version would make the bottom row flicker while you use the menu.

## Why deletion, not a better hint source

- **The bar is a layout special case that `Box` layouts already obsoleted.**
  `ScreenPane#layout` hardcodes `height - 1` for content and reserves the bottom
  row — v0.1-era architecture from before `Vertical`/`Fixed` existed. Today an
  app-owned bar is `Vertical.new.tap { _1.add(main, Expand); _1.add(bar,
  Fixed[1]) }`, and the app gets what the framework cannot offer: two rows, a
  bar at the top, its own styling, a file-commander function-key strip, or
  nothing at all.
- **It is the same shape the top-down re-grow rule already governs.** That rule
  says a deleted bottom-up channel may return only as an *optional, read-only,
  caller-side query*, never as an automatic channel the framework consults.
  `keyboard_hint` is currently an automatic channel; deleting it and letting an
  app declare its own is that rule applied.
- **The framework bakes an app policy.** `refresh_status_bar` unconditionally
  prefixes `"q quit"` in the tiled case (verified: a `Window` with a focused
  `MenuBar` yields a bar reading exactly `"q quit"`). pikuri's three apps quit
  via `^K → q`; their bar reads `q quit  ^K menu` while `q` typed into the
  focused input just types a `q`.
- **The book documents behavior that does not exist.** `book/05-focus.md:273`
  ("The status bar writes itself") says it is "driven by focus" and shows "the
  focused context's own advertised hint". It is driven by an
  `is_a?(Component::Window)` scan over the active chain; focus only triggers the
  rebuild. A reader who follows the book and overrides `keyboard_hint` on a
  focusable widget gets nothing.
- **There is a live decision arguing the opposite of the book.**
  `D-boolean-fields` records "hints are a window/popup-level affordance;
  per-field hints would drown the status bar." Any fix had to overrule it;
  deletion retires the question.

## The change

**Delete:** `ScreenPane#status_bar` and the `height - 1` reservation in
`ScreenPane#layout`; `Screen#refresh_status_bar` and `#global_shortcut_hints`;
`Screen#active_window` (one consumer — this line — and zero downstream users);
`Component#keyboard_hint` and all seven overrides (`Window` has none; `Popup`,
`PickerWindow`, `MenuBar`, `Tabs`, `Select`, `ComboBox`, `Notification`); the
`hint:` parameter on `register_global_shortcut`; the hardcoded `"q quit"`.
`ScreenPane`'s popup insert anchor (`at: @children.index(@status_bar)`) becomes
a plain append.

**Add:** one focus-change notification on `Screen` — `on_focus_changed=` as a
plain proc, matching the `on_theme_changed=` style stock assemblies already use.
Fired from `focused=`. ~5 lines.

**Keep:** `Theme#hint` — still the right styling helper for an app-drawn bar.
`Popup#handle_key`'s `q`/ESC close — dispatch, not presentation.

## Counter-arguments, and the rulings

- *Batteries-included.* `book/01-first-app.md:120` currently says "you never
  created a status bar, yet the app has one", and `hello_world_spec` asserts on
  `q quit`. **Ruled:** worth losing. A bar the app cannot drive is not a
  battery, and ch1 gains a better story once the bar is three lines of
  `Vertical`.
- *Third-party components.* If Tuile grows a component ecosystem, a widget
  telling its host "here are my keys" is genuinely useful — Textual's
  `BINDINGS`/`Footer`, already on record as steal-candidate #1 in
  `D-key-dispatch`. **Ruled:** that argues for a *query an app pulls*, not a
  channel the framework pushes. Deleting now does not foreclose it; the re-grow
  rule above is the form it would take.

## Open questions

- **The `q`/ESC quit fallback in `Screen#event_loop`** (`screen.rb:820`,
  `@event_queue.stop if !handled && ["q", Keys::ESC].include?(key)`) is the same
  class of baked app policy, but it is *dispatch*, not presentation, and it is
  separable. Rule on it on its own; do not smuggle it into this change.
- **Hook shape** — a single `on_focus_changed=` proc, or a listener list? A
  proc matches `on_theme_changed=`; a list would admit a debug overlay
  alongside a bar. Start with the proc; a list is additive.

## Migration

Both apps grow their own bar, ~15 lines each. pikuri's is a net *simplification*
— `install_shortcut` splits back into a real registration plus a direct
`bar.text =`, and the re-registration rdoc paragraph goes away. virtui keeps its
two `keyboard_hint` methods verbatim and calls them itself from the hook.

In-repo: three examples (`hello_world`, `file_commander`, `sampler`), `book/01`
and `book/05` (whose "The status bar writes itself" section goes — it documents
behavior that never existed), a `D-` entry, a **breaking** CHANGELOG entry, and
`sig/` regeneration.
