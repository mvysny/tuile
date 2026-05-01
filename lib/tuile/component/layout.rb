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

      # Adds a child component to this layout.
      # @param child [Component, Array<Component>]
      # @return [void]
      def add(child)
        if child.is_a? Enumerable
          child.each { add(it) }
        else
          raise "Not a component" unless child.is_a? Component
          raise if !child.nil? && !child.parent.nil?

          @children << child
          child.parent = self
        end
      end

      # @param child [Component]
      # @return [void]
      def remove(child)
        raise "Not a component" unless child.is_a? Component
        raise "Child's parent #{child.parent} is not this one #{self}" if child.parent != self

        child.parent = nil
        @children.delete(child)
        invalidate if @children.empty?
        on_child_removed(child)
      end

      # @return [Size]
      def content_size
        return Size.new(0, 0) if @children.empty?

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
          child.handle_mouse(event) if child.rect.contains?(event.x, event.y)
        end
      end

      # Called when a character is pressed on the keyboard.
      # @param key [String] a key.
      # @return [Boolean] true if the key was handled, false if not.
      def handle_key(key)
        return true if super(key)

        sc = @children.find(&:active?)
        return false if sc.nil?

        sc.handle_key(key)
      end

      def focusable? = true

      # @return [void]
      def on_focus
        super
        # Let the content component receive focus, so that it can immediately
        # start responding to key presses.
        first_focusable = @children.find(&:focusable?)
        screen.focused = first_focusable unless first_focusable.nil?
      end

      # Absolute layout. Extend this class, register any children, and
      # override {Component#rect=} to reposition the children.
      class Absolute < Layout
      end
    end
  end
end
