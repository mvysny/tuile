# frozen_string_literal: true

module Tuile
  class Component
    # A {Component::Tabs} strip on its top row plus the pane belonging to the
    # selected tab underneath it:
    #
    #   ␣Details␣│␣Payment␣│␣Shipping␣
    #   the selected tab's pane fills the rest of the rect
    #
    #   sheet = Component::TabSheet.new
    #   sheet.add_tab("Details", details_form)     # selected, and shown
    #   sheet.add_tab("Payment", payment_form)
    #   sheet.select_next                          # shows payment_form
    #   sheet.on_tab_selected = ->(index, tab) { log("now on #{tab&.caption}") }
    #
    # Tab lands on the strip first and enters the pane on the next press, which
    # is the browser's order; switching tabs does *not* move focus into the new
    # pane, but if focus was inside the pane that just went away it lands back
    # on the strip.
    #
    # == Hidden panes are detached
    # Only the selected tab's pane is in the component tree — the others are
    # detached, which is how Tuile hides a component (there is no visibility
    # flag, and an empty rect gates painting only). Consequences worth
    # designing around:
    #
    # - A hidden pane is invisible to *everything*: the Tab cycle, focus
    #   cascades, repaint, the cursor, `on_tree` walks. No gates anywhere.
    # - Its state survives, because state is ivars — scroll position, caret,
    #   list cursor, text are all exactly as the user left them, and mutating a
    #   hidden pane is safe (`invalidate` while detached is a silent no-op).
    # - {Component#on_detached} / {Component#on_attached} fire on every switch,
    #   so a pane holding a mounted-lifetime resource — a {Component::ProgressBar}'s
    #   ticker — releases it while hidden and re-acquires it on return. A pane
    #   that must keep something alive while hidden can't; that something
    #   belongs in the model the pane renders, not in the pane.
    #
    # == Implementation details
    # `children` is `[strip, pane]`, the strip pinned at index 0, so pre-order
    # traversal gives the strip-then-pane Tab order for free. The swap follows
    # the slot-swap recipe {Component#detach_child} documents — detach, rewire,
    # `on_child_removed` last, so the focus repair sees the new occupant.
    #
    # Panes live in an identity-keyed `Tab => Component` map here rather than in
    # a slot on {Tabs::Tab}: the strip's tab array stays the sole ordering
    # authority, and the strip itself stays ignorant of panes. One idempotent
    # `sync_pane` is the sole writer of the visible pane, deriving it from
    # `strip.selected` on every call, so registering a pane and selecting a tab
    # can happen in either order.
    #
    # The sheet owns the strip's `on_tab_selected` (that is what drives the
    # swap); an app's listener goes on {#on_tab_selected} here, which fires
    # after the pane has been swapped in.
    class TabSheet < Component
      # An app's own selection listener, called after the pane has been swapped
      # in — `(index, tab)`, or `(nil, nil)` once the last tab is gone. Same
      # contract as {Tabs#on_tab_selected}: it reports that the selection
      # changed, whatever changed it.
      # @return [Proc, nil]
      attr_accessor :on_tab_selected

      # @param separator [String, StyledString] the strip's separator; see
      #   {Tabs#separator=}.
      def initialize(separator: Tabs::DEFAULT_SEPARATOR)
        super()
        @panes = {}.compare_by_identity
        @strip = Tabs.new(separator:)
        add_child(@strip)
        @strip.on_tab_selected = lambda do |index, tab|
          sync_pane
          @on_tab_selected&.call(index, tab)
        end
      end

      # @return [Tabs] the strip. Reach through it for the rest of its API —
      #   `sheet.strip.separator = "|"` — but leave its `on_tab_selected` alone:
      #   the sheet drives the pane swap through it, and {#on_tab_selected} is
      #   where an app's listener goes.
      attr_reader :strip

      # @return [Component, nil] the pane currently in the tree — the selected
      #   tab's, `nil` while the sheet has no tabs.
      attr_reader :pane

      # Adds a tab and the pane to show while it is selected. The first tab
      # added becomes the selection, so its pane is shown immediately.
      # @param caption [String, StyledString, nil] parsed as {Tabs::Tab#caption=}
      #   parses it.
      # @param pane [Component] shown while this tab is selected, detached while
      #   it isn't.
      # @raise [TypeError] when `pane` isn't a {Component}.
      # @raise [ArgumentError] when `pane` is already this sheet's pane for
      #   another tab — a component has one parent, so two tabs cannot share it.
      # @return [Tabs::Tab] the new tab's handle.
      def add_tab(caption, pane)
        raise TypeError, "expected Component, got #{pane.inspect}" unless pane.is_a?(Component)

        forget_removed_tabs
        if @panes.each_value.any? { |existing| existing.equal?(pane) }
          raise ArgumentError, "#{pane} is already a pane of this TabSheet"
        end

        tab = @strip.add_tab(caption)
        @panes[tab] = pane
        sync_pane
        tab
      end

      # Removes a tab and forgets its pane, detaching it if it was the visible
      # one. The strip re-selects as {Tabs#remove_tab} describes, and this
      # sheet shows whatever it lands on.
      # @param tab [Tabs::Tab] one of this sheet's tabs.
      # @raise [ArgumentError] when the tab isn't on this sheet's strip.
      # @return [Component, nil] the pane that tab owned.
      def remove_tab(tab)
        pane = @panes[tab] # read first: the strip's own removal may prune the entry
        @strip.remove_tab(tab)
        @panes.delete(tab)
        pane
      end

      # @param tab [Tabs::Tab, nil]
      # @return [Component, nil] the pane registered for `tab`; `nil` for a
      #   removed tab, a tab of another sheet, or `nil`.
      def pane_for(tab)
        return nil unless tab&.attached?

        @panes[tab]
      end

      # @return [Array<Tabs::Tab>] the strip's tabs, in order.
      def tabs = @strip.tabs

      # @return [Tabs::Tab, nil] the selected tab.
      def selected = @strip.selected

      # @param tab [Tabs::Tab] one of this sheet's tabs.
      # @return [void]
      def selected=(tab)
        @strip.selected = tab
      end

      # @return [Integer, nil] the selected tab's position.
      def selected_index = @strip.selected_index

      # @param index [Integer] a position in `0...tabs.size`.
      # @return [void]
      def selected_index=(index)
        @strip.selected_index = index
      end

      # Selects the next tab, clamping at the last one.
      # @return [Boolean] `false` only when there are no tabs.
      def select_next = @strip.select_next

      # Selects the previous tab, clamping at the first one.
      # @return [Boolean] `false` only when there are no tabs.
      def select_previous = @strip.select_previous

      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        super
        @strip.rect = Rect.new(rect.left, rect.top, rect.width, [rect.height, 1].min)
        layout_pane
      end

      # Forwards to whichever child the click landed on — the strip's row, or
      # the pane below it.
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        children.each do |child|
          child.handle_mouse(event) if child.rect.contains?(event.point)
        end
      end

      # Sends focus to the strip: a sheet is a container, and the strip is where
      # a tab switch is driven from. The pane is a Tab press away.
      # @return [void]
      def on_focus
        super
        screen.focused = @strip
      end

      # Lands focus on the strip rather than on `self` when the focused pane is
      # swapped out — a bare container can't use keys, and the user's last
      # action was a tab switch.
      # @param child [Component]
      # @return [void]
      def on_child_removed(child)
        super
        screen.focused = @strip if attached? && screen.focused.equal?(self)
      end

      private

      # Makes the visible pane match `strip.selected`, swapping if it doesn't.
      # Idempotent and the sole writer of `@pane`: it derives everything from
      # current state, so {#add_tab} can register a pane after the strip has
      # already selected its tab.
      # @return [void]
      def sync_pane
        forget_removed_tabs
        wanted = @panes[@strip.selected]
        return if wanted.equal?(@pane)

        old = @pane
        detach_child(old) unless old.nil?
        @pane = wanted
        unless wanted.nil?
          add_child(wanted) # appended: the strip stays at index 0
          wanted.invalidate
          layout_pane
        end
        invalidate
        on_child_removed(old) unless old.nil?
      end

      # Drops entries whose tab is gone. {Tabs::Tab#remove} takes a tab off the
      # strip without passing through {#remove_tab}, and a detached tab can never
      # be selected again, so its entry is dead weight — it pins the pane against
      # garbage collection and makes {#add_tab} reject that pane as still in use.
      # Idempotent and the only cleaner, because the rule it enforces is an
      # invariant ("every key is a live tab of my strip") rather than a step in
      # one code path.
      # @return [void]
      def forget_removed_tabs
        @panes.delete_if { |tab, _pane| !tab.attached? }
      end

      # @return [void]
      def layout_pane
        return if @pane.nil?

        @pane.rect = Rect.new(rect.left, rect.top + 1, rect.width, [rect.height - 1, 0].max)
      end
    end
  end
end
