# frozen_string_literal: true

module Tuile
  # The structural root of the {Screen}'s component tree.
  #
  # {Screen} is a singleton runtime owner (event loop, lock, terminal IO,
  # invalidation set). All actual UI lives under a {ScreenPane}: the tiled
  # {#content}, the modal {#popups} stack, and the bottom {#status_bar}.
  # Putting them under a single Component parent gives focus traversal a real
  # root, makes {Component#attached?} a one-liner, and lets popup-focus repair
  # fall out of the standard {Component#on_child_removed} hook.
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
      @status_bar = Component::Label.new
      # Added first and never removed, so it is always the last child — which is
      # the anchor `add_popup` inserts against.
      add_child(@status_bar)
    end

    # @return [Component, nil] the tiled content component.
    attr_reader :content
    # @return [Array<Component>] overlay popups in stacking order; last is
    #   topmost. Holds both modal popups and non-modal overlays
    #   ({Component::Popup#modal?}). The array must not be mutated by callers.
    attr_reader :popups
    # @return [Component::Label] the bottom status bar.
    attr_reader :status_bar

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

    # Adds a popup and invalidates it for repaint. A modal popup is centered
    # and grabs focus; a non-modal overlay ({Component::Popup#modal?} false) is
    # left wherever the caller positions it and does *not* take focus, so the
    # component that was focused keeps the cursor and keeps receiving keys —
    # the overlay floats above the content, driven from app code.
    #
    # The *whole subtree* is invalidated, not just the popup wrapper (which
    # paints nothing on its own): a reopened popup may land on cells that the
    # tiled content has since overpainted, and if its rect is unchanged from
    # last time its content components won't re-invalidate themselves — so
    # without this the popup's contents would stay blank on reopen.
    # @param window [Component::Popup]
    # @return [void]
    def add_popup(window)
      raise TypeError, "expected Popup, got #{window.inspect}" unless window.is_a? Component::Popup
      raise ArgumentError, "#{window} already has a parent #{window.parent}" unless window.parent.nil?

      @popup_prior_focus[window] = screen.focused
      @popups << window
      add_child(window, at: @children.index(@status_bar))
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

    # @return [Component::Popup, nil] the topmost *modal* popup, or nil when
    #   only non-modal overlays (or no popups) are open. This is the "modal
    #   owner": the popup that scopes key dispatch, blocks mouse clicks, owns
    #   the status bar, and confines Tab cycling. Non-modal overlays are
    #   excluded — they float above the content without capturing input.
    def modal_popup = @popups.reverse_each.find(&:modal?)

    # Re-lays out children whenever the pane's own rect changes.
    # @param new_rect [Rect]
    # @return [void]
    def rect=(new_rect)
      super
      layout
    end

    # Lays out content (full pane minus the bottom row) and the status bar
    # (bottom row). Each popup re-resolves its {Component::Popup#size} against
    # the new screen via {Component::Popup#reposition} — so a {Fraction} size
    # tracks resize — repositioning itself (modal popups recenter; non-modal
    # overlays keep the top-left their owner assigned).
    # @return [void]
    def layout
      return if rect.empty?

      @content.rect = Rect.new(rect.left, rect.top, rect.width, [rect.height - 1, 0].max) unless @content.nil?
      @popups.each(&:reposition)
      @status_bar.rect = Rect.new(rect.left, rect.top + rect.height - 1, rect.width, 1)
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

    # Mouse events check popups in reverse stacking order (topmost first), and
    # fall through to content only when no popup is hit *and* no modal popup is
    # open. This preserves modal click-blocking — an open modal eats clicks
    # even outside its rect — while a non-modal overlay blocks nothing: clicks
    # inside it route to it (e.g. click-to-select), clicks elsewhere reach the
    # content beneath.
    # @param event [MouseEvent]
    # @return [void]
    def handle_mouse(event)
      clicked = @popups.reverse_each.find { _1.rect.contains?(event.point) }
      clicked = @content if clicked.nil? && modal_popup.nil?
      clicked&.handle_mouse(event)
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

    # Delivers `key` to {Screen#focused} and bubbles it up the ancestor chain,
    # stopping at (and including) `scope`. Delivers to no one — returning false
    # — when focus is nil or sits outside `scope`; the latter is what makes an
    # open popup modal, since focus is always inside it and content beneath
    # never receives keys.
    # @param key [String]
    # @param scope [Component] the modal scope root (topmost popup or content).
    # @return [Boolean] true if some component on the chain handled the key.
    def bubble_key(key, scope)
      chain = []
      cursor = screen.focused
      until cursor.nil?
        chain << cursor
        break if cursor.equal?(scope)

        cursor = cursor.parent
      end
      return false unless chain.last.equal?(scope)

      chain.each { |c| return true if c.handle_key(key) }
      false
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
