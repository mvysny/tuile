# frozen_string_literal: true

module Tuile
  # The structural root of the {Screen}'s component tree.
  #
  # {Screen} is a singleton runtime owner (event loop, lock, terminal IO,
  # invalidation set). All actual UI lives under a {ScreenPane}: the tiled
  # {#content} and the {#popups} stack. Putting them under a single Component
  # parent gives focus traversal a real root, makes {Component#attached?} a
  # one-liner, and lets popup-focus repair fall out of the standard
  # {Component#on_child_removed} hook.
  #
  # The pane owns no chrome of its own — no status bar, no reserved row.
  # {#content} gets the full pane rect, and an app that wants a status line
  # builds one into its own layout and drives it from
  # {Screen#on_focus_changed=} (`D_status_bar`).
  #
  # The pane is not a {Component::Layout}: popups deliberately overlap content
  # (Z-ordered, full overdraw, no clipping) and key/mouse dispatch follows
  # modal-popup rules rather than active-child dispatch.
  class ScreenPane < Component
    def initialize
      super
      @popups = []
      # Per-popup snapshot of {Screen#focused} taken just before the popup was
      # added. Restored when the popup closes so focus returns to where the
      # user was, instead of falling through to {#content} and getting
      # cascaded to the first focusable child.
      @popup_prior_focus = {}
    end

    # @return [Component, nil] the tiled content component.
    attr_reader :content
    # @return [Array<Component::Overlay>] the open overlays in stacking order;
    #   last is topmost. Holds both {Component::Popup} modals and bare
    #   {Component::Overlay}s ({Component::Overlay#modal?}). The array must not
    #   be mutated by callers.
    attr_reader :popups

    def focusable? = false

    # Replaces the tiled content. Wipes focus first (the new tree starts
    # fresh), detaches the old content, then attaches the new one and
    # re-lays out.
    # @param content [Component]
    def content=(content)
      raise TypeError, "expected Component, got #{content.inspect}" unless content.is_a? Component
      raise ArgumentError, "#{content} already has a parent #{content.parent}" unless content.parent.nil?
      return if @content == content

      screen.focused = nil
      remove_child(@content) unless @content.nil?
      @content = content
      add_child(content, at: 0) # the tiled layer paints beneath everything else
      layout
    end

    # Adds an overlay and invalidates it for repaint. A {Component::Popup} is
    # centered and grabs focus; a bare {Component::Overlay} is left wherever
    # the caller positioned it and does *not* take focus, so the component that
    # was focused keeps the cursor and keeps receiving keys — the overlay
    # floats above the content, driven from app code.
    #
    # The *whole subtree* is invalidated, not just the overlay wrapper (which
    # paints nothing on its own): a reopened popup may land on cells that the
    # tiled content has since overpainted, and if its rect is unchanged from
    # last time its content components won't re-invalidate themselves — so
    # without this the overlay's contents would stay blank on reopen.
    # @param window [Component::Overlay] any overlay, modal or not.
    # @return [void]
    def add_popup(window)
      raise TypeError, "expected Overlay, got #{window.inspect}" unless window.is_a? Component::Overlay
      raise ArgumentError, "#{window} already has a parent #{window.parent}" unless window.parent.nil?

      @popup_prior_focus[window] = screen.focused
      @popups << window
      add_child(window) # appended: popups paint over the tiled content
      if window.modal?
        window.center
        screen.focused = window
      end
      window.on_tree { |c| screen.invalidate(c) }
    end

    # Removes a popup. If the popup held focus, focus shifts to the now-topmost
    # remaining popup, falling back to the focus snapshotted when the popup
    # was opened (if still attached), then to {#content}, then to nil.
    # @param window [Component]
    # @return [void]
    def remove_popup(window)
      raise Tuile::Error, "#{window} is not an open popup on this pane" unless @popups.delete(window)

      prior = @popup_prior_focus.delete(window)
      @removing_popup_prior = prior
      remove_child(window)
      # Runs after the detach, so a prior pointing *inside* the removed popup is
      # detectable via `p.root == window`: forward it to *our* prior, so chained
      # closures climb back to the original owner instead of stopping at a
      # detached component.
      @popup_prior_focus.transform_values! { |p| p && p.root == window ? prior : p }
    ensure
      @removing_popup_prior = nil
    end

    # Unmounts everything: each child is detached — firing {Component#on_detached}
    # down its subtree — and every slot is emptied. Terminal; the pane isn't
    # reusable afterwards, and {Screen#close} is its only caller.
    #
    # Deliberately not named `close` ({Component::Popup#close} already means
    # "remove *me* from the pane"), and deliberately not a generic
    # `Component#remove_all_children`: a slot container calling that would empty
    # `@children` while `#content` / `#footer` still pointed at detached
    # components, which is the desync the tree API exists to prevent.
    # @return [void]
    def detach_all
      screen.focused = nil # …so the focus repair in on_child_removed has nothing to do
      children.dup.each { detach_child(_1) }
      @content = nil
      @popups.clear
      @popup_prior_focus.clear
    end

    # @param window [Component]
    # @return [Boolean] true if this pane currently hosts the popup.
    def has_popup?(window) = @popups.include?(window) # rubocop:disable Naming/PredicatePrefix

    # @return [Component::Popup, nil] the topmost modal overlay, or nil when
    #   only bare {Component::Overlay}s (or none) are open. This is the "modal
    #   owner": the popup that scopes key dispatch, blocks mouse clicks, and
    #   confines Tab cycling. Bare overlays are excluded — they float above the
    #   content without capturing input.
    def modal_popup = @popups.reverse_each.find(&:modal?)

    # Re-lays out children whenever the pane's own rect changes.
    # @param new_rect [Rect]
    # @return [void]
    def rect=(new_rect)
      super
      layout
    end

    # Gives {#content} the whole pane rect — the pane reserves nothing for
    # itself. Each popup re-resolves its {Component::Popup#declared_size} against the new
    # screen via {Component::Popup#reposition} — so a {Fraction} size tracks
    # resize — repositioning itself (modal popups recenter; non-modal overlays
    # keep the top-left their owner assigned).
    # @return [void]
    def layout
      return if rect.empty?

      @content&.rect = rect
      @popups.each(&:reposition)
    end

    # Pane paints nothing itself; its children paint over the entire rect.
    # @return [void]
    def repaint; end

    # Delivers a key to {Screen#focused}, then bubbles it up the focus chain —
    # the first component whose `handle_key` returns true wins.
    #
    # Bubbling stops at the *scope* root: the topmost *modal* popup when one is
    # open, else the tiled {#content}. Focus that is nil or sits outside the
    # scope receives nothing, which is what keeps an open modal popup modal.
    # Non-modal overlays are never the scope: focus stays in the content
    # beneath them, and the overlay is driven by app code (which forwards keys
    # to it explicitly), so it doesn't appear in this path at all.
    #
    # Because an ancestor sees a key only after every descendant on the chain
    # declined it, the scope root is the natural home for scope-wide fallbacks
    # — a form's default button, or a layout's one-key jumps to its panes (a
    # focused {Component::TextField} consumes the key first, so typing is never
    # hijacked).
    # @param key [String]
    # @return [Boolean] true if the key was handled.
    def handle_key(key)
      scope = modal_popup || @content
      return false if scope.nil?

      bubble_key(key, scope)
    end

    # Delivers pasted text to {Screen#focused} — and to nobody else.
    #
    # Scoped exactly like {#handle_key} (focus that is nil or sits outside the
    # modal scope receives nothing, which is what keeps a popup modal) but
    # **not bubbled**: an ancestor is never offered a paste its descendant
    # declined, and unhandled text is dropped. Why keys bubble and pastes
    # don't: `D_bracketed_paste`.
    # @param text [String]
    # @return [Boolean] true if the focused component consumed it.
    def handle_paste(text)
      scope = modal_popup || @content
      return false if scope.nil?

      chain = focus_chain(scope)
      return false if chain.nil?

      chain.first.handle_paste(text)
    end

    # Mouse events check popups in reverse stacking order (topmost first), and
    # fall through to content only when no popup is hit *and* no modal popup is
    # open. This preserves modal click-blocking — an open modal eats clicks
    # even outside its rect — while a non-modal overlay blocks nothing: clicks
    # inside it route to it (e.g. click-to-select), clicks elsewhere reach the
    # content beneath.
    #
    # A left click also *dismisses* the open popups it landed outside of that
    # asked for it ({Component::Overlay#close_on_outside_click?}). That is a
    # second thing happening on a click, but not a second dispatch: the click is
    # still delivered exactly once, down one chain, and a dismissed popup is
    # closed rather than told.
    #
    # "Outside" is measured against the {Component::Overlay#owner} chain, not
    # against one rect and not against stacking order: the popup the click hit
    # is kept, and so is every popup that one *belongs to*, transitively. That
    # is what stops a dialog being dismissed by a click on a dropdown its own
    # field opened, and a menu cascade being dismissed by a click on one of its
    # own deeper panels. Order carries no meaning here — between unrelated
    # overlays it is merely the order they opened in — so ownership is declared
    # rather than inferred from the stack.
    #
    # Two halves of the ordering are load-bearing, and both are specced:
    #
    # - **Snapshot before routing.** A popup the delivered click *opens* must
    #   not be in the set (it would immediately dismiss itself — every
    #   {Component::Select} would be unopenable by mouse).
    # - **Close after routing.** A widget toggling its own overlay from a click
    #   on its face closes it during delivery, and {Component::Popup#close} is
    #   idempotent, so the dismissal no-ops. Close *first* and the widget sees
    #   a shut overlay and reopens it — a Select's dropdown could then never be
    #   dismissed by clicking the Select.
    #
    # The snapshot is a fresh array for a third reason: a handler may close
    # further popups, and `@popups` must not be mutated mid-iteration.
    # @param event [MouseEvent]
    # @return [void]
    def handle_mouse(event)
      hit = @popups.reverse_each.find { _1.rect.contains?(event.point) }
      dismissable = event.button == :left ? @popups - kept_by(hit) : []

      clicked = hit || (@content if modal_popup.nil?)
      clicked&.handle_mouse(event)

      dismissable.each { _1.close if _1.close_on_outside_click? }
    end

    # Focus repair when a child detaches. Default {Component#on_child_removed}
    # would refocus to `self` (the pane), which isn't a useful focus target.
    # Instead, route focus to the first interactable widget in the now-topmost
    # modal popup; falling back to the focus snapshotted when this popup was opened
    # (if still attached and still focusable); then to the first interactable
    # widget in {#content}; then to {#content} itself; then nil.
    #
    # "First interactable widget" = first {Component#tab_stop?} in pre-order;
    # if a scope has no tab stops at all (a borderless ESC-to-close popup, or
    # tiled content made entirely of {Label}s), we focus the scope's root so
    # `q`/ESC still has somewhere to dispatch from.
    # @param child [Component]
    # @return [void]
    def on_child_removed(child)
      return unless attached?

      f = screen.focused
      return if f.nil?

      cursor = f
      while cursor
        if cursor == child
          fallback = first_tab_stop_or_root(modal_popup)
          if fallback.nil? && @removing_popup_prior&.attached? && @removing_popup_prior.focusable?
            fallback = @removing_popup_prior
          end
          fallback ||= first_tab_stop_or_root(@content)
          screen.focused = fallback
          return
        end
        cursor = cursor.parent
      end
    end

    private

    # The overlays a click counts as landing *inside*: the one it hit, plus
    # every overlay that one belongs to, up the {Component::Overlay#owner}
    # chain. An owner is any component, so it is resolved to the overlay
    # enclosing it (an overlay resolves to itself) — which keeps the
    # relationship a live tree question rather than one frozen when the overlay
    # opened. The `include?` guard makes a mis-wired cycle terminate instead of
    # hanging the UI thread.
    # @param hit [Component::Overlay, nil] the overlay the click landed in, if any.
    # @return [Array<Component::Overlay>]
    def kept_by(hit)
      kept = []
      overlay = hit
      while overlay && !kept.include?(overlay)
        kept << overlay
        overlay = enclosing_popup(overlay.owner)
      end
      kept
    end

    # @param component [Component, nil]
    # @return [Component::Overlay, nil] `component` itself when it is an
    #   overlay, else the nearest overlay above it, else nil.
    def enclosing_popup(component)
      component = component.parent until component.nil? || component.is_a?(Component::Overlay)
      component
    end

    # Delivers `key` to {Screen#focused} and bubbles it up the ancestor chain,
    # stopping at (and including) `scope`. Delivers to no one — returning false
    # — when focus is nil or sits outside `scope`; the latter is what makes an
    # open popup modal, since focus is always inside it and content beneath
    # never receives keys.
    # @param key [String]
    # @param scope [Component] the modal scope root (topmost popup or content).
    # @return [Boolean] true if some component on the chain handled the key.
    def bubble_key(key, scope)
      chain = focus_chain(scope)
      return false if chain.nil?

      chain.each { |c| return true if c.handle_key(key) }
      false
    end

    # {Screen#focused} and its ancestors up to and including `scope`.
    # @param scope [Component] the modal scope root (topmost popup or content).
    # @return [Array<Component>, nil] the chain, innermost first; nil when
    #   focus is nil or sits outside `scope`.
    def focus_chain(scope)
      chain = []
      cursor = screen.focused
      until cursor.nil?
        chain << cursor
        break if cursor.equal?(scope)

        cursor = cursor.parent
      end
      chain.last.equal?(scope) ? chain : nil
    end

    # First {Component#tab_stop?} in `root`'s subtree (pre-order), falling
    # back to `root` itself when the subtree has no tab stops. Returns `nil`
    # if `root` is `nil`.
    # @param root [Component, nil]
    # @return [Component, nil]
    def first_tab_stop_or_root(root)
      return nil if root.nil?

      root.on_tree { |c| return c if c.tab_stop? }
      root
    end
  end
end
