# frozen_string_literal: true

module Tuile
  # A UI component which is positioned on the screen and draws characters into
  # its bounding rectangle (in {#repaint}).
  #
  # Component is considered invisible if {#rect} is empty or one of left/top is
  # negative. The component won't draw when invisible.
  class Component
    def initialize
      @rect = Rect.new(0, 0, 0, 0)
      @active = false
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
      raise "invalid rect #{new_rect}" unless new_rect.is_a? Rect
      return if @rect == new_rect

      prev_width = @rect.width
      @rect = new_rect
      on_width_changed if prev_width != new_rect.width
      invalidate
    end

    # @return [Screen] the screen which owns this component.
    def screen = Screen.instance

    # Focuses this component. Equivalent to `screen.focused = self`.
    def focus
      screen.focused = self
    end

    # Repaints the component. Default implementation does nothing.
    #
    # The component must fully draw over {#rect}, and must not draw outside of
    # {#rect}.
    #
    # Tip: use {#clear_background} to clear component background before painting.
    def repaint; end

    # Called when a character is pressed on the keyboard.
    #
    # Also called for inactive components. Inactive component should just return
    # false.
    #
    # Default implementation searches for a component with {#key_shortcut} and
    # focuses it. The shortcut search is suppressed while the focused component
    # owns the hardware cursor (e.g. a {Component::TextField} the user is
    # typing into) so that hotkeys don't steal printable keys from the editor.
    # @param key [String] a key.
    # @return [Boolean] true if the key was handled, false if not.
    def handle_key(key)
      return false unless screen.cursor_position.nil?

      c = find_shortcut_component(key)
      if !c.nil?
        screen.focused = c
        true
      else
        false
      end
    end

    # A global keyboard shortcut. When pressed, will focus this component.
    # @return [String, nil] shortcut, `nil` by default.
    attr_accessor :key_shortcut

    # @param key [String] keyboard key to look up.
    # @return [Component, nil] the component whose {#key_shortcut} matches `key`,
    #   or nil.
    def find_shortcut_component(key)
      return self if key_shortcut == key

      children.each do |child|
        sc = child.find_shortcut_component(key)
        return sc unless sc.nil?
      end
      nil
    end

    # Handles mouse event. Default implementation focuses this component when
    # clicked (if {#focusable?}).
    # @param event [MouseEvent]
    def handle_mouse(event)
      screen.focused = self unless event.button != :left || active? || !focusable?
    end

    # @return [Boolean] true if the component is on the active chain — i.e. it
    #   is the focused component or an ancestor of it. Set by {Screen#focused=}.
    def active? = @active

    # @param active [Boolean] true if active. Set by {Screen#focused=} as it
    #   marks the focus chain (root → focused); not meant to be called directly.
    def active=(active)
      active = !!active
      return unless @active != active

      @active = active
      invalidate
    end

    # Whether this component is a valid focus target. `false` by default —
    # passive components like {Label} are decoration and don't accept focus.
    # The flag gates click-to-focus ({#handle_mouse}) and the focus-cascade
    # in container components ({HasContent#on_focus}, {Layout#on_focus}).
    # Independent from {#active?}: every component carries the active flag, but
    # only focusable ones can become a focus target that puts themselves and
    # their ancestors on the active chain.
    # @return [Boolean] true if this component can be focused.
    def focusable? = false

    # @return [Component, nil] the parent component or nil if the component has
    #   no parent.
    attr_reader :parent

    # @return [Integer] the distance from the root component; 0 if {#parent}
    #   is nil.
    def depth = parent.nil? ? 0 : parent.depth + 1

    # @return [Component] the root component of this component hierarchy.
    def root = parent.nil? ? self : parent.root

    # List of child components, defaults to an empty array.
    # @return [Array<Component>] child components. Must not be mutated! May be
    #   empty.
    def children = []

    # Calls block for this component and for every descendant component.
    # @yield [component]
    # @yieldparam component [Component]
    def on_tree(&block)
      block.call(self)
      children.each { it.on_tree(&block) }
    end

    # Called when the component receives focus.
    def on_focus; end

    # @return [Boolean] true if this component's tree is currently mounted on
    #   the {Screen}, i.e. its root is the {ScreenPane}.
    def attached? = root == screen.pane

    # Called by container components after `child` has been detached from
    # `self.children` (its `parent` is already nil and it is no longer in the
    # children list). Default behavior repairs dangling focus: if the focused
    # component lived inside the removed subtree, focus shifts to `self` so the
    # cursor doesn't dangle on a detached component. No-op if `self` is not
    # attached to the screen — focus state in a detached subtree is moot.
    # @param child [Component] the just-detached child.
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

    # When a component wraps contents, this function returns a {Size} big enough
    # to show the entire component contents, without scrolling.
    # @return [Size, nil]
    def content_size = nil

    # Where the hardware terminal cursor should sit when this component is the
    # cursor owner. Returns `nil` to indicate the cursor should be hidden. The
    # {Screen} positions the hardware cursor after each repaint cycle by
    # consulting the {Screen#focused} component only.
    # @return [Point, nil] absolute screen coordinates, or nil to hide.
    def cursor_position = nil

    protected

    attr_writer :parent

    # Called whenever the component width changes. Does nothing by default.
    def on_width_changed; end

    # Invalidates the component: {Screen} records this component as
    # needs-repaint and once all events are processed, will call {#repaint}.
    def invalidate
      screen.invalidate(self)
    end

    # Clears the background: prints spaces into all characters occupied by the
    # component's rect.
    def clear_background
      return if rect.empty?

      spaces = " " * rect.width
      (rect.top..(rect.top + rect.height - 1)).each do |row|
        screen.print TTY::Cursor.move_to(rect.left, row), spaces
      end
    end

    # A label which shows static text. No word-wrapping; clips long lines.
    class Label < Component
      def initialize
        super
        @lines = []
        @clipped_lines = []
      end

      # @param text [String, nil] draws this text. May contain ANSI formatting.
      #   Clipped automatically.
      def text=(text)
        @lines = text.to_s.split("\n")
        @content_size = nil
        update_clipped_text
      end

      def content_size
        @content_size ||= begin
          width = @lines.map { |line| Unicode::DisplayWidth.of(Rainbow.uncolor(line)) }.max || 0
          Size.new(width, @lines.size)
        end
      end

      def repaint
        clear_background
        height = rect.height.clamp(0, nil)
        lines_to_print = @clipped_lines.length.clamp(nil, height)
        (0..lines_to_print - 1).each do |index|
          screen.print TTY::Cursor.move_to(rect.left, rect.top + index), @clipped_lines[index]
        end
      end

      protected

      def on_width_changed
        super
        update_clipped_text
      end

      private

      def update_clipped_text
        len = rect.width.clamp(0, nil)
        clipped = @lines.map do |line|
          Strings::Truncation.truncate(line, length: len)
        end
        return if @clipped_lines == clipped

        @clipped_lines = clipped
        invalidate
      end
    end
  end
end
