# 5. Focus and the keyboard

**Status: stub.**

The runtime chapter on input. Explains how focus moves through the tree
and the precise order in which a keystroke is offered to components.
Assumes the event loop from chapter 4.

Will cover:

- The focus chain: `screen.focused = component` marks the whole chain
  root → focused as `active?` and deactivates everything else; `nil`
  deactivates all.
- `focusable?` gates *becoming* a focus target (independent of active);
  click-to-focus and the on-focus cascade only forward to focusable
  components, so clicking a `Label` doesn't steal focus.
- The key-dispatch order, first handler wins: Tab / Shift+Tab (screen
  level, per modal scope) → global shortcuts
  (`register_global_shortcut`, `over_popups:`) → a component's
  `key_shortcut` (subtree lookup, suppressed while a text field owns the
  hardware cursor) → `handle_key` (override, return true/false, call
  `super`).
- How that cursor-ownership suppression lets a focused `TextField`
  swallow printable keys without sibling shortcuts hijacking them.
- `keyboard_hint` and how the status bar composes hints (tiled vs popup).
