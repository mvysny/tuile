# frozen_string_literal: true

module Tuile
  # A UI component which is positioned on the screen and draws characters into
  # its bounding rectangle (in {#repaint}).
  #
  # Painting is gated by attachment: a detached component (one whose {#root}
  # isn't {Screen#pane}) is never enqueued for repaint via {#invalidate}, and
  # any stale invalidation entries are filtered out at drain time. Subclasses
  # can paint freely in {#repaint} without re-asserting attachment.
  class Component
    def initialize
      @rect = Rect.new(0, 0, 0, 0)
      @active = false
      @on_theme_changed = nil
      @bg_color = nil
      @children = []
    end

    # @return [Rect] the rectangle the component occupies on screen.
    attr_reader :rect

    # Sets new position of the component. This is the absolute component
    # positioning on screen, not a relative positioning relative to component's
    # {#parent}.
    #
    # The component must not stick outside of {#parent}'s rect.
    #
    # The component is invalidated and will paint over the new rectangle. It is
    # parent's job to paint over the old component position.
    # @param new_rect [Rect] new position. Does nothing if the new rectangle is
    #   the same as the old one.
    def rect=(new_rect)
      raise TypeError, "expected Rect, got #{new_rect.inspect}" unless new_rect.is_a? Rect
      return if @rect == new_rect

      prev_width = @rect.width
      @rect = new_rect
      on_width_changed if prev_width != new_rect.width
      invalidate
    end

    # @return [Screen] the screen which owns this component.
    def screen = Screen.instance

    # Focuses this component. Equivalent to `screen.focused = self`.
    # @return [void]
    def focus
      screen.focused = self
    end

    # @return [Color, Theme::Ref, nil] this component's own background — the
    #   value as set, so a {Theme::Ref} comes back unresolved; `nil` when unset,
    #   in which case it inherits from the parent (see {#effective_bg_color}),
    #   ultimately the terminal default. {#effective_bg_color} is the resolved
    #   {Color} to paint.
    attr_reader :bg_color

    # Tints this component and every descendant that doesn't set its own
    # background (they re-resolve via {#effective_bg_color}) — set it once on a
    # container / {Component::Popup} to tint a whole subtree. Invalidates the
    # subtree so it repaints.
    #
    # A {Theme::Ref} is re-resolved against the theme each paint, so it tracks
    # light/dark flips with no {#on_theme_changed} hook; a {Color} is fixed:
    #
    #   panel.bg_color = Theme.ref(:panel_bg)   # theme-tracked
    #   panel.bg_color = Color::GREY27          # fixed
    #
    # @param color [Color, Theme::Ref, Symbol, Integer, Array<Integer>, nil] a
    #   {Theme::Ref}, else a color coerced via {Color.coerce}; `nil` unsets
    #   (inherit from the parent).
    # @raise [KeyError] when a {Theme::Ref} names an absent custom token —
    #   validated eagerly at assignment, not deferred to paint.
    # @return [void]
    def bg_color=(color)
      color = Color.coerce(color) unless color.is_a?(Theme::Ref)
      return if @bg_color == color

      color.resolve(screen.theme) if color.is_a?(Theme::Ref) # fail fast on a bad token
      @bg_color = color
      on_tree { |c| screen.invalidate(c) } if attached?
    end

    # @return [Color, nil] the background actually painted: this component's own
    #   {#bg_color} if set (a {Theme::Ref} resolved against the current theme),
    #   else the nearest ancestor's, else `nil` (terminal default). Resolved at
    #   paint time — never cached, so the subtree tracks both an ancestor's
    #   {#bg_color=} and a {Screen#theme=} on its next repaint.
    def effective_bg_color
      own = @bg_color
      own = own.resolve(screen.theme) if own.is_a?(Theme::Ref)
      own || parent&.effective_bg_color
    end

    # Repaints the component. The default does the bookkeeping most components
    # need: it clears the background, and for a container whose children leave
    # gaps in {#rect} it re-invalidates those children so they repaint over the
    # cleared area (what makes mixed-width form layouts safe). A container whose
    # children fully tile {#rect} is left alone — the children cover everything.
    #
    # Call `super` from your own `repaint` to inherit this. Skip it only if you
    # paint the whole {#rect} yourself ({Window}'s border, {Component::List}'s
    # row-by-row paint). Never draw outside {#rect}. Only called when attached.
    # @return [void]
    def repaint
      return if rect.empty?
      return if children.any? && children_tile_rect?

      clear_background
      children.each { |c| screen.invalidate(c) }
    end

    # Called when a key is pressed; override to act on keys you care about (the
    # default reports every key unhandled). A component only receives keys while
    # it's on the focus chain — or when app code hands it one directly — so act
    # on the key alone and never gate on your own {#active?} state. See book ch5
    # for how a keystroke is routed to reach here.
    # @param _key [String] a key.
    # @return [Boolean] true if the key was handled, false if not.
    def handle_key(_key)
      false
    end

    # Handles mouse event. Default implementation focuses this component when
    # clicked (if {#focusable?}).
    # @param event [MouseEvent]
    # @return [void]
    def handle_mouse(event)
      screen.focused = self unless event.button != :left || active? || !focusable?
    end

    # @return [Boolean] true if the component is on the active chain — i.e. it
    #   is the focused component or an ancestor of it. Set by {Screen#focused=}.
    def active? = @active

    # @param active [Boolean] true if active. Set by {Screen#focused=} as it
    #   marks the focus chain (root → focused); not meant to be called directly.
    # @return [void]
    def active=(active)
      active = active ? true : false
      return unless @active != active

      @active = active
      invalidate
    end

    # Whether this component is a valid focus target. `false` by default —
    # passive components like {Label} are decoration and don't accept focus.
    # The flag gates click-to-focus and the container focus-cascade. Independent
    # from {#active?}: every component carries the active flag, but only
    # focusable ones can become a focus target that puts themselves and their
    # ancestors on the active chain. Focusable is broader than {#tab_stop?} —
    # a {Window} is focusable (a click on chrome lands focus) but not a tab stop.
    # @return [Boolean] true if this component can be focused.
    def focusable? = false

    # Whether this component participates in Tab / Shift+Tab focus cycling.
    # `false` by default. Only true on components that accept direct user
    # input (e.g. {TextField}, {List}, {Component::Button}). Implies
    # {#focusable?} — Screen will skip non-focusable tab stops, but in
    # practice every override should keep the two consistent.
    # @return [Boolean] true if Tab / Shift+Tab should land on this component.
    def tab_stop? = false

    # @return [Component, nil] the parent component or nil if the component has
    #   no parent.
    attr_reader :parent

    # @return [Integer] the distance from the root component; 0 if {#parent}
    #   is nil.
    def depth = parent.nil? ? 0 : parent.depth + 1

    # @return [Component] the root component of this component hierarchy.
    def root = parent.nil? ? self : parent.root

    # Child components in paint order (siblings left to right, earlier ones
    # painted under later ones), maintained by {#add_child} / {#remove_child}.
    #
    # Not meant to be overridden: a container that computed this from its own
    # slots could disagree with the parent pointers, and {#attached?} walks the
    # chain while subtree walks use this list. Named slots are readers *over*
    # the array (`Window#footer`), never a second copy of it.
    # @return [Array<Component>] child components. Must not be mutated by
    #   callers! May be empty.
    attr_reader :children

    # Calls block for this component and for every descendant component.
    # @yield [component]
    # @yieldparam component [Component]
    # @yieldreturn [void]
    # @return [void]
    def on_tree(&block)
      block.call(self)
      children.each { _1.on_tree(&block) }
    end

    # Called when the component receives focus.
    # @return [void]
    def on_focus; end

    # Optional zero-arg listener fired by the base {#on_theme_changed} — the
    # composition-style alternative to overriding the method, for apps that
    # assemble stock components rather than subclass:
    #
    #   label.on_theme_changed = -> { label.text = render_status_line }
    #
    # @return [Proc, nil]
    attr_writer :on_theme_changed

    # Called on every attached component (pre-order, popups included) when
    # {Screen#theme} changes — at {Screen#theme=} / {Screen#theme_def=} and on
    # OS appearance flips. The hook exists for app *content* whose colors were
    # baked in from the old theme (a {Label#text} / {List#lines} {StyledString}
    # styled with `theme[:accent]`); rebuild it here by re-running the code that
    # rendered it. See book ch6 for why built-in accents need no such handling.
    #
    # Runs on the UI thread with {Screen#theme} already updated, so mutating
    # content (`text=`, `lines=`, …) is safe. Do not assign {Screen#theme=}
    # here. Subclasses overriding this must call `super` so an assigned
    # {#on_theme_changed=} listener keeps firing.
    # @return [void]
    def on_theme_changed
      @on_theme_changed&.call
    end

    # Whether this component's tree is mounted on a UI, {ScreenPane} being the
    # root of every displayed tree.
    #
    # A property of the parent chain alone — no {Screen} is consulted, so
    # assembling a tree needs no screen in the process at all:
    #
    #   layout = Component::Layout::Absolute.new
    #   layout.add(label)      # legal with no Screen; neither is attached yet
    #   screen.content = layout # now both are
    #
    # @return [Boolean] true if {#root} is a {ScreenPane}.
    def attached? = root.is_a?(ScreenPane)

    # Called by container components after `child` has been detached from
    # `self.children` (its `parent` is already nil and it is no longer in the
    # children list). Default behavior repairs dangling focus: if the focused
    # component lived inside the removed subtree, focus shifts to `self` so the
    # cursor doesn't dangle on a detached component. No-op if `self` is not
    # attached to the screen — focus state in a detached subtree is moot.
    # @param child [Component] the just-detached child.
    # @return [void]
    def on_child_removed(child)
      return unless attached?

      f = screen.focused
      return if f.nil?

      cursor = f
      until cursor.nil?
        if cursor == child
          screen.focused = self
          return
        end
        cursor = cursor.parent
      end
    end

    # Where the hardware terminal cursor should sit when this component is the
    # cursor owner. Returns `nil` to indicate the cursor should be hidden. The
    # {Screen} positions the hardware cursor after each repaint cycle by
    # consulting the {Screen#focused} component only.
    # @return [Point, nil] absolute screen coordinates, or nil to hide.
    def cursor_position = nil

    # @return [String] formatted keyboard hint surfaced in the status bar by
    #   {Screen} when this component is the active tiled window or the
    #   topmost popup. Empty by default; override to advertise shortcuts.
    def keyboard_hint = ""

    protected

    # Adopts `child`: places it in {#children} and wires its parent pointer.
    #
    #   add_child(@status_bar)                              # paints last
    #   add_child(popup, at: @children.index(@status_bar))  # …just before it
    #
    # @param child [Component] must not already have a parent.
    # @param at [Integer, nil] index to insert at; appends when nil.
    # @raise [TypeError] if `child` is not a {Component}.
    # @raise [ArgumentError] if `child` already has a parent.
    # @return [void]
    def add_child(child, at: nil)
      raise TypeError, "expected Component, got #{child.inspect}" unless child.is_a? Component
      raise ArgumentError, "#{child} already has a parent #{child.parent}" unless child.parent.nil?

      at.nil? ? @children.push(child) : @children.insert(at, child)
      child.parent = self
    end

    # Drops `child` and notifies {#on_child_removed}.
    # @param child [Component]
    # @raise [ArgumentError] if `child` is not a child of this component.
    # @return [void]
    def remove_child(child)
      detach_child(child)
      on_child_removed(child)
    end

    # Drops `child` *without* notifying — for a container swapping a named slot,
    # which owes the {#on_child_removed} call once the new occupant is wired:
    #
    #   detach_child(old)
    #   @content = new
    #   add_child(new, at: 0)
    #   on_child_removed(old)   # focus repair cascades into the *new* content
    #
    # The child leaves {#children} before its pointer is cleared, so nothing
    # observes a child whose parent has disowned it while still listing it.
    # @param child [Component]
    # @raise [ArgumentError] if `child` is not a child of this component.
    # @return [void]
    def detach_child(child)
      raise ArgumentError, "#{child} is not a child of #{self}" unless @children.include?(child)

      @children.delete(child)
      child.parent = nil
    end

    # @return [Component, nil]
    attr_writer :parent

    # Called whenever the component width changes. Does nothing by default.
    # @return [void]
    def on_width_changed; end

    # Invalidates the component: {Screen} records this component as
    # needs-repaint and once all events are processed, will call {#repaint}.
    #
    # No-op when the component is not {#attached?} — a detached component has
    # no place on the screen to paint to, so {Screen} must never end up
    # repainting it. Callers don't need to guard their own `invalidate` calls;
    # mutating a detached component (e.g. setting `lines=` on a {List} sitting
    # inside a closed {Component::Popup}) is silent.
    # @return [void]
    def invalidate
      return unless attached?

      screen.invalidate(self)
    end

    # Whether direct children fully tile {#rect}. Used by the default
    # {#repaint} to decide whether the framework needs to wipe gaps.
    #
    # Approximated by area: sum of (non-empty) child areas vs the parent's
    # area. Cheap, and correct as long as siblings don't overlap each other
    # — which Tuile already requires (no clipping in the tiled tree).
    # Children with empty rects contribute zero, since they paint nothing.
    # @return [Boolean]
    def children_tile_rect?
      total = children.sum { |c| c.rect.empty? ? 0 : c.rect.width * c.rect.height }
      total >= rect.width * rect.height
    end

    # Clears the background: fills every cell of {#rect} with a blank in the
    # {#effective_bg_color} (the terminal default when none is inherited).
    # @return [void]
    def clear_background
      bg = effective_bg_color
      screen.buffer.fill(rect, bg ? StyledString::Style.new(bg:) : StyledString::Style::DEFAULT)
    end

    # {Buffer#set_line} wrapper that fills {#effective_bg_color} behind any span
    # with no bg of its own (via {StyledString#under_bg}), so an inherited
    # {#bg_color} shows through the content a component paints. A no-op layer
    # when nothing is inherited. Self-painters (those skipping the {#repaint}
    # auto-clear) paint through this instead of {Screen#buffer} directly.
    # @param x [Integer] starting column.
    # @param y [Integer] row.
    # @param styled [StyledString]
    # @return [void]
    def draw_line(x, y, styled)
      screen.buffer.set_line(x, y, styled.under_bg(effective_bg_color))
    end

    # {#draw_line}'s single-grapheme counterpart: writes `grapheme` at `(x, y)`,
    # filling {#effective_bg_color} when `style` carries no bg of its own.
    # @param x [Integer] column.
    # @param y [Integer] row.
    # @param grapheme [String] one grapheme cluster.
    # @param style [StyledString::Style]
    # @return [void]
    def draw_char(x, y, grapheme, style = StyledString::Style::DEFAULT)
      bg = effective_bg_color
      style = style.merge(bg:) if bg && style.bg.nil?
      screen.buffer.set_char(x, y, grapheme, style)
    end
  end
end
