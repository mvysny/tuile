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
      @status_bar.parent = self
    end

    # @return [Component, nil] the tiled content component.
    attr_reader :content
    # @return [Array<Component::PopupWindow>] modal popup windows in stacking
    #   order; last is topmost. The array must not be mutated by callers.
    attr_reader :popups
    # @return [Component::Label] the bottom status bar.
    attr_reader :status_bar

    def focusable? = false

    # Children for tree traversal: content first, popups in stacking order,
    # status bar last.
    def children = [*[@content].compact, *@popups, @status_bar]

    # Replaces the tiled content. Wipes focus first (the new tree starts
    # fresh), detaches the old content, then attaches the new one and
    # re-lays out.
    # @param content [Component]
    def content=(content)
      raise unless content.is_a? Component
      raise unless content.parent.nil?
      return if @content == content

      screen.focused = nil
      old = @content
      old&.parent = nil
      @content = content
      content.parent = self
      layout
    end

    # Adds a popup, centers it, focuses it, and invalidates it for repaint.
    # @param window [Component::PopupWindow]
    # @return [void]
    def add_popup(window)
      raise unless window.is_a? Component::PopupWindow
      raise unless window.parent.nil?

      @popup_prior_focus[window] = screen.focused
      @popups << window
      window.parent = self
      window.center
      screen.focused = window
      screen.invalidate(window)
    end

    # Removes a popup. If the popup held focus, focus shifts to the now-topmost
    # remaining popup, falling back to the focus snapshotted when the popup
    # was opened (if still attached), then to {#content}, then to nil.
    # @param window [Component::PopupWindow]
    # @return [void]
    def remove_popup(window)
      raise "window is not a popup" unless @popups.delete(window)

      prior = @popup_prior_focus.delete(window)
      # Detach first so the popup becomes its own root; then any prior
      # pointing *inside* that popup is detectable via `p.root == window`.
      window.parent = nil
      # If any other popup recorded its prior focus inside the popup we're
      # removing, forward it to *our* prior so chained closures still climb
      # back to the original owner instead of stopping at a detached
      # component.
      @popup_prior_focus.transform_values! { |p| p && p.root == window ? prior : p }

      @removing_popup_prior = prior
      on_child_removed(window)
    ensure
      @removing_popup_prior = nil
    end

    # @param window [Component::PopupWindow]
    # @return [Boolean] true if this pane currently hosts the popup.
    def has_popup?(window) = @popups.include?(window) # rubocop:disable Naming/PredicatePrefix

    # Re-lays out children whenever the pane's own rect changes.
    # @param new_rect [Rect]
    # @return [void]
    def rect=(new_rect)
      super
      layout
    end

    # Lays out content (full pane minus the bottom row) and the status bar
    # (bottom row). Popups self-position via {Component::PopupWindow#center}.
    # @return [void]
    def layout
      return if rect.empty?

      @content.rect = Rect.new(rect.left, rect.top, rect.width, [rect.height - 1, 0].max) unless @content.nil?
      @popups.each(&:center)
      @status_bar.rect = Rect.new(rect.left, rect.top + rect.height - 1, rect.width, 1)
    end

    # Pane paints nothing itself; its children paint over the entire rect.
    # @return [void]
    def repaint; end

    # Topmost popup is modal: it eats keys. Falls through to content only
    # when no popup is open.
    def handle_key(key)
      topmost = @popups.last
      return topmost.handle_key(key) unless topmost.nil?
      return @content.handle_key(key) unless @content.nil?

      false
    end

    # Mouse events check popups in reverse stacking order (topmost first), and
    # fall through to content only when no popup is hit *and* there are no
    # popups open. This preserves modal click-blocking: an open popup eats
    # clicks even outside its rect.
    # @param event [MouseEvent]
    # @return [void]
    def handle_mouse(event)
      clicked = @popups.rfind { it.rect.contains?(event.x, event.y) }
      clicked = @content if clicked.nil? && @popups.empty?
      clicked&.handle_mouse(event)
    end

    # Focus repair when a child detaches. Default {Component#on_child_removed}
    # would refocus to `self` (the pane), which isn't a useful focus target.
    # Instead, route focus to the now-topmost popup, then to the prior focus
    # snapshotted when this popup was opened (if still attached), then to
    # content, then nil.
    # @param child [Component]
    # @return [void]
    def on_child_removed(child)
      return unless attached?

      f = screen.focused
      return if f.nil?

      cursor = f
      while cursor
        if cursor == child
          fallback = @popups.last
          fallback ||= @removing_popup_prior if @removing_popup_prior&.attached?
          fallback ||= @content
          screen.focused = fallback
          return
        end
        cursor = cursor.parent
      end
    end
  end
end
