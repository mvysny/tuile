# frozen_string_literal: true

module Tuile
  class Component
    # A layout doesn't paint anything by itself: its job is to position child
    # components.
    #
    # All children must completely cover the contents of a layout: that way,
    # the layout itself doesn't have to draw and no clipping algorithm is
    # necessary.
    class Layout < Component
      def initialize
        super
        @children = []
      end

      # @return [Array<Component>]
      def children = @children.to_a

      # Layouts are focusable containers — like {Window} and {Popup}, they
      # don't accept input themselves but they need to participate in the
      # {HasContent} focus cascade so a Popup wrapping a Layout wrapping a
      # {TextField} ends up focusing the field rather than parking focus on
      # the popup. Per the cover-the-whole-rect invariant, Layouts have no
      # exposed click target of their own, so this has no mouse-routing
      # consequences.
      def focusable? = true

      # Adds a child component to this layout.
      # @param child [Component, Array<Component>]
      # @return [void]
      def add(child)
        if child.is_a? Enumerable
          child.each { add(it) }
        else
          raise TypeError, "expected Component, got #{child.inspect}" unless child.is_a? Component
          raise ArgumentError, "#{child} already has a parent #{child.parent}" unless child.parent.nil?

          @children << child
          child.parent = self
        end
      end

      # @param child [Component]
      # @return [void]
      def remove(child)
        raise TypeError, "expected Component, got #{child.inspect}" unless child.is_a? Component
        raise ArgumentError, "#{child}'s parent is #{child.parent}, not this layout #{self}" if child.parent != self

        child.parent = nil
        @children.delete(child)
        invalidate if @children.empty?
        on_child_removed(child)
      end

      # @return [Size]
      def content_size
        return Size::ZERO if @children.empty?

        right  = @children.map { |c| c.rect.left + c.rect.width  }.max
        bottom = @children.map { |c| c.rect.top  + c.rect.height }.max
        Size.new(right - rect.left, bottom - rect.top)
      end

      # @return [void]
      def repaint
        clear_background if @children.empty?
      end

      # Dispatches the event to the child under the mouse cursor.
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        @children.each do |child|
          child.handle_mouse(event) if child.rect.contains?(event.point)
        end
      end

      # Called when a character is pressed on the keyboard.
      # @param key [String] a key.
      # @return [Boolean] true if the key was handled, false if not.
      def handle_key(key)
        return true if super

        sc = @children.find(&:active?)
        return false if sc.nil?

        sc.handle_key(key)
      end

      # @return [void]
      def on_focus
        super
        # Forward focus to the first interactive widget in the subtree so the
        # user can start typing / cursoring immediately. Prefer a {#tab_stop?}
        # descendant (TextField, List, Button…) so we skip past intermediate
        # containers like a {Window} or another {Layout}. Fall back to the
        # first focusable direct child for the rare case where the layout has
        # focusable but non-tab-stop children (e.g. an empty {Window}).
        first_tab_stop = nil
        on_tree { |c| first_tab_stop ||= c if !c.equal?(self) && c.tab_stop? }
        if first_tab_stop
          screen.focused = first_tab_stop
        else
          first_focusable = @children.find(&:focusable?)
          screen.focused = first_focusable unless first_focusable.nil?
        end
      end

      # Absolute layout. Extend this class, register any children, and
      # override {Component#rect=} to reposition the children.
      class Absolute < Layout
      end
    end
  end
end
