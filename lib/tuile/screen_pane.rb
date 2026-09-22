# frozen_string_literal: true

module Tuile
  # The structural root of the {Screen}'s component tree.
  #
  # {Screen} is a singleton runtime owner (event loop, lock, terminal IO,
  # invalidation set). All actual UI lives under a {ScreenPane}: the tiled
  # {#content} and the {#popups} stack. Putting them under a single Component
  # parent gives focus traversal a real root, makes {Component#attached?} a
  # one-liner, and lets popup-focus repair fall out of the standard
  # {Component#handle_child_removed} hook.
  #
  # The pane owns no chrome of its own — no status bar, no reserved row.
  # {#content} gets the full pane rect, and an app that wants a status line
  # builds one into its own layout and drives it from
  # {Screen#on_focus_changed} (`D_status_bar`).
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
      # Where each open popup wants to be, and the anchor rect its last
      # placement used (`:lost` once the anchor went away) — see #relayout.
      @placements = {}.compare_by_identity
      @placed_anchors = {}.compare_by_identity
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
    end

    # Adds an overlay at `placement` and invalidates it for repaint; the next
    # settle gives it its rect. A {Component::Popup} grabs focus; a bare
    # {Component::Overlay} does *not*, so the component that was focused keeps
    # the cursor and keeps receiving keys — the overlay floats above the
    # content, driven from app code.
    #
    # The *whole subtree* is invalidated, not just the overlay wrapper (which
    # paints nothing on its own): a reopened popup may land on cells that the
    # tiled content has since overpainted, and if its rect is unchanged from
    # last time its content components won't re-invalidate themselves — so
    # without this the overlay's contents would stay blank on reopen.
    # @param window [Component::Overlay] any overlay, modal or not.
    # @param placement [Component::Overlay::Placement, nil] where it wants to
    #   be; `nil` takes its {Component::Overlay#default_placement}.
    # @raise [TypeError] if `placement` does not include
    #   {Component::Overlay::Placement}.
    # @return [void]
    def add_popup(window, placement = nil)
      raise TypeError, "expected Overlay, got #{window.inspect}" unless window.is_a? Component::Overlay
      raise ArgumentError, "#{window} already has a parent #{window.parent}" unless window.parent.nil?

      placement ||= window.default_placement
      check_placement(placement)
      @popup_prior_focus[window] = screen.focused
      @placements[window] = placement
      @popups << window
      add_child(window) # appended: popups paint over the tiled content
      screen.focused = window if window.modal?
      window.walk_tree { |c| screen.invalidate(c) }
    end

    # @param popup [Component::Overlay] an open popup.
    # @return [Component::Overlay::Placement, nil] where it wants to be; `nil`
    #   if it isn't open here.
    def placement(popup) = @placements[popup]

    # Moves an open popup; it takes the new rect on the next settle.
    # {Component::Overlay#placement=} is the usual way in.
    # @param popup [Component::Overlay] an open popup.
    # @param placement [Component::Overlay::Placement] where it wants to be.
    # @raise [ArgumentError] if `popup` isn't open on this pane.
    # @raise [TypeError] if `placement` does not include
    #   {Component::Overlay::Placement}.
    # @return [void]
    def constrain(popup, placement)
      raise ArgumentError, "#{popup} is not an open popup on this pane" unless has_popup?(popup)

      check_placement(placement)
      return if @placements[popup] == placement

      @placements[popup] = placement
      invalidate_layout
    end

    # Removes a popup. If the popup held focus, focus shifts to the now-topmost
    # remaining popup, falling back to the focus snapshotted when the popup
    # was opened (if still attached), then to {#content}, then to nil.
    # @param window [Component]
    # @return [void]
    def remove_popup(window)
      raise Tuile::Error, "#{window} is not an open popup on this pane" unless @popups.delete(window)

      prior = @popup_prior_focus.delete(window)
      @placements.delete(window)
      @placed_anchors.delete(window)
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

    # Unmounts everything: each child is detached — firing {Component#handle_detached}
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
      screen.focused = nil # …so the focus repair in handle_child_removed has nothing to do
      children.dup.each { detach_child(_1) }
      @content = nil
      @popups.clear
      @popup_prior_focus.clear
      @placements.clear
      @placed_anchors.clear
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

    # The root of the current **key scope**: the topmost modal popup when one
    # is open, else the tiled {#content}. Keys bubble up to it and no further,
    # a paste reaches only a focus chain inside it, and Tab cycles only the
    # stops beneath it — so a component outside it is one the keyboard cannot
    # reach at all. The mouse resolves against a *point* instead
    # ({#mouse_root_at}).
    # @return [Component, nil] nil when the pane holds neither.
    def key_scope = modal_popup || @content

    # Gives {#content} the whole pane rect — the pane reserves nothing for
    # itself — and each popup the rect its placement asks for, in stacking
    # order, so a submenu is placed after the panel it hangs from.
    #
    # Re-running it moves nothing that stood still: a placement is a rule, so
    # a second popup opening re-derives the first one's rect unchanged.
    # @return [void]
    def relayout
      return if rect.empty?

      @content&.rect = local_rect
      @popups.each { place(_1) }
    end

    # Pane paints nothing itself; its children paint over the entire rect.
    # @param _canvas [Canvas] see {Component#repaint}.
    # @return [void]
    def repaint(_canvas); end

    # Delivers a key to {Screen#focused}, then bubbles it up the focus chain —
    # the first component whose `handle_key?` returns true wins.
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
    def handle_key?(key)
      scope = key_scope
      return false if scope.nil?

      bubble_key(key, scope)
    end

    # Delivers pasted text to {Screen#focused} — and to nobody else.
    #
    # Scoped exactly like {#handle_key?} (focus that is nil or sits outside the
    # modal scope receives nothing, which is what keeps a popup modal) but
    # **not bubbled**: an ancestor is never offered a paste its descendant
    # declined, and unhandled text is dropped. Why keys bubble and pastes
    # don't: `D_bracketed_paste`.
    # @param text [String]
    # @return [void]
    def handle_paste(text)
      scope = key_scope
      return if scope.nil?

      chain = focus_chain(scope)
      return if chain.nil?

      chain.first.handle_paste(text)
    end

    # Where {Mouse::Router} starts its walk for a pointer at `point`: the
    # topmost popup containing it, else {#content} — unless a modal popup is
    # open, which eats the event even outside its rect. A non-modal overlay
    # blocks nothing: a point outside it reaches the content beneath.
    # @api private
    # @param point [Point]
    # @return [Component, nil]
    def mouse_root_at(point) = popup_at(point) || (@content if modal_popup.nil?)

    # Runs the press delivery in the block, then *dismisses* the open popups a
    # left press landed outside of that asked for it
    # ({Component::Overlay#close_on_outside_click?}). A dismissed popup is
    # closed rather than told.
    #
    # "Outside" is measured against the {Component::Overlay#owner} chain, not
    # against one rect and not against stacking order: the popup the press hit
    # is kept, and so is every popup that one *belongs to*, transitively. That
    # is what stops a dialog being dismissed by a click on a dropdown its own
    # field opened, and a menu cascade being dismissed by a click on one of its
    # own deeper panels. Order carries no meaning here — between unrelated
    # overlays it is merely the order they opened in — so ownership is declared
    # rather than inferred from the stack.
    #
    # Two halves of the ordering are load-bearing, and both are specced:
    #
    # - **Snapshot before the block.** A popup the delivered press *opens* must
    #   not be in the set (it would immediately dismiss itself — every
    #   {Component::Select} would be unopenable by mouse).
    # - **Close after the block.** A widget toggling its own overlay from a press
    #   on its face closes it during delivery, and {Component::Popup#close} is
    #   idempotent, so the dismissal no-ops. Close *first* and the widget sees
    #   a shut overlay and reopens it — a Select's dropdown could then never be
    #   dismissed by clicking the Select.
    #
    # The snapshot is a fresh array for a third reason: a handler may close
    # further popups, and `@popups` must not be mutated mid-iteration.
    # @api private
    # @param point [Point]
    # @param left [Boolean] whether the press was the left button; no other
    #   button dismisses.
    # @yield the press delivery.
    # @return [void]
    def dismissing_popups_outside(point, left:)
      dismissable = left ? @popups - kept_by(popup_at(point)) : []
      yield
      dismissable.each { _1.close if _1.close_on_outside_click? }
    end

    # Focus repair when a child detaches. Default {Component#handle_child_removed}
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
    def handle_child_removed(child)
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

    # The pane's rect is the screen's to assign, since no parent's pass could.
    # @return [Screen]
    def placer = screen

    # Rejects a non-placement where the app named it, rather than mid-pass: the
    # layout is deferred, so the `NoMethodError` from a missing `rect_for` would
    # otherwise surface a turn later, under this file's backtrace.
    # @param placement [Object]
    # @raise [TypeError] unless it includes {Component::Overlay::Placement}.
    # @return [void]
    def check_placement(placement)
      return if placement.is_a?(Component::Overlay::Placement)

      raise TypeError, "#{placement.class} must include Tuile::Component::Overlay::Placement"
    end

    # A placement's {Component::Overlay::Placement#anchor} in screen
    # coordinates: a `Rect` passes through, a component resolves while it is on
    # screen, and `nil` means either unanchored or gone — {#place} tells those
    # apart by whether an anchor was declared at all.
    # @param anchor [Component, Rect, nil]
    # @return [Rect, nil]
    def resolve_anchor(anchor)
      return anchor if anchor.nil? || anchor.is_a?(Rect)

      ScreenPane.__send__(:effectively_visible?, anchor) ? anchor.absolute_extent_rect : nil
    end

    # Whether `component` is genuinely on screen: {Component#visible?} is its
    # own flag alone, so a field under a hidden panel is still `visible?`
    # itself. {Component#walk_shown_tree} is the same rule for walks.
    # @param component [Component]
    # @return [Boolean]
    def self.effectively_visible?(component)
      node = component
      until node.nil?
        return false unless node.visible?

        node = node.parent
      end
      component.attached?
    end
    private_class_method :effectively_visible?

    # @param popup [Component::Overlay]
    # @return [void]
    def place(popup)
      placement = @placements.fetch(popup)
      anchor = placement.anchor
      anchor_rect = resolve_anchor(anchor)
      unless anchor.nil?
        return lose_anchor(popup) if anchor_rect.nil?

        @placed_anchors[popup] = anchor_rect
      end
      popup.rect = placement.rect_for(popup, rect.size, anchor_rect)
    end

    # Leaves a popup whose anchor was detached or hidden at its last rect. It
    # warns, once, because closing the popup is its owner's job and an owner
    # that forgot leaves it floating over nothing.
    # @param popup [Component::Overlay]
    # @return [void]
    def lose_anchor(popup)
      return if @placed_anchors[popup] == :lost

      @placed_anchors[popup] = :lost
      Tuile.logger.warn("#{popup} lost its anchor; left where it was — close it when the anchor goes")
    end

    # Whether an anchored popup's anchor now resolves elsewhere than where its
    # last placement read it. {Screen#flush_layout} asks once the queue is
    # empty, because this pass runs *before* the content it anchors to, so a
    # settle that moved the content handed the pass a stale anchor.
    # @return [Boolean]
    def anchors_moved?
      return false if rect.empty? # #relayout places nothing then, so nothing would record

      @popups.any? do |popup|
        anchor = @placements[popup].anchor
        !anchor.nil? && (resolve_anchor(anchor) || :lost) != @placed_anchors[popup]
      end
    end

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

    # @param point [Point]
    # @return [Component::Overlay, nil] the topmost popup containing `point`.
    def popup_at(point) = @popups.reverse_each.find { _1.rect.contains?(point) }

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

      chain.each { |c| return true if c.handle_key?(key) }
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
    # if `root` is `nil`, or if `root` is itself hidden — there is nothing in
    # there to focus, so the caller falls through to its next candidate.
    # @param root [Component, nil]
    # @return [Component, nil]
    def first_tab_stop_or_root(root)
      return nil if root.nil? || !root.visible?

      root.walk_shown_tree { |c| return c if c.tab_stop? }
      root
    end
  end
end
