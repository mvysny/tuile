# frozen_string_literal: true

module Tuile
  class Component
    # A single-line text input field with hardware-cursor caret.
    #
    # The field does not scroll. Any keystroke that would make {#text} longer
    # than `rect.width - 1` (the last column is reserved for the caret past the
    # last char) is rejected.
    #
    # The caret is a logical index in `0..text.length`. The hardware cursor is
    # positioned by {Screen} after each repaint cycle when this component is
    # focused; see {Component#cursor_position}.
    class TextField < Component
      def initialize
        super
        @text = +""
        @caret = 0
        @on_escape = nil
        @on_change = nil
        @on_key_up = nil
        @on_key_down = nil
        @on_enter = nil
      end

      # @return [String] current text contents.
      attr_reader :text

      # @return [Integer] caret index in `0..text.length`.
      attr_reader :caret

      # Optional callback fired when ESC is pressed. When set, ESC is consumed
      # by the field; when nil, ESC falls through to the parent (default
      # behavior).
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_escape

      # Optional callback fired whenever {#text} changes. Receives the new text
      # as a single argument. Not fired by {#caret=} (text unchanged) and not
      # fired when a setter is a no-op.
      # @return [Proc, Method, nil] one-arg callable, or nil.
      attr_accessor :on_change

      # Optional callback fired when the UP arrow key is pressed. When set, UP
      # is consumed by the field; when nil, UP falls through to the parent
      # (default behavior). Only triggered by {Keys::UP_ARROW}, not by `k`,
      # since `k` is a printable character inserted into {#text}.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_key_up

      # Optional callback fired when the DOWN arrow key is pressed. When set,
      # DOWN is consumed by the field; when nil, DOWN falls through to the
      # parent (default behavior). Only triggered by {Keys::DOWN_ARROW}, not by
      # `j`, since `j` is a printable character inserted into {#text}.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_key_down

      # Optional callback fired when ENTER is pressed. When set, ENTER is
      # consumed by the field; when nil, ENTER falls through to the parent
      # (default behavior).
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_enter

      # Sets the text. Truncates to fit if longer than `rect.width - 1`. Caret
      # is clamped to the new text length.
      # @param new_text [String]
      def text=(new_text)
        new_text = new_text.to_s
        new_text = new_text[0, max_text_length] if new_text.length > max_text_length
        return if @text == new_text

        @text = +new_text
        @caret = @caret.clamp(0, @text.length)
        invalidate
        @on_change&.call(@text)
      end

      # Sets the caret position. Clamped to `0..text.length`.
      # @param new_caret [Integer]
      def caret=(new_caret)
        new_caret = new_caret.clamp(0, @text.length)
        return if @caret == new_caret

        @caret = new_caret
        invalidate
      end

      def can_activate? = true

      def cursor_position
        return nil unless rect.width.positive?

        Point.new(rect.left + @caret, rect.top)
      end

      def handle_key(key)
        return false unless active?
        return true if super

        case key
        when Keys::LEFT_ARROW then self.caret = @caret - 1
        when Keys::RIGHT_ARROW then self.caret = @caret + 1
        when Keys::HOME then self.caret = 0
        when Keys::END_ then self.caret = @text.length
        when *Keys::BACKSPACES then delete_before_caret
        when Keys::DELETE then delete_at_caret
        when Keys::ESC
          return false if @on_escape.nil?

          @on_escape.call
        when Keys::UP_ARROW
          return false if @on_key_up.nil?

          @on_key_up.call
        when Keys::DOWN_ARROW
          return false if @on_key_down.nil?

          @on_key_down.call
        when Keys::ENTER
          return false if @on_enter.nil?

          @on_enter.call
        else
          return insert(key) if printable?(key)

          return false
        end
        true
      end

      def handle_mouse(event)
        super
        return unless event.button == :left && rect.contains?(event.x, event.y)

        self.caret = (event.x - rect.left).clamp(0, @text.length)
      end

      def repaint
        clear_background
        return if rect.empty?

        screen.print TTY::Cursor.move_to(rect.left, rect.top), @text
      end

      protected

      def on_width_changed
        super
        return if @text.length <= max_text_length

        @text = @text[0, [max_text_length, 0].max]
        @caret = @caret.clamp(0, @text.length)
        @on_change&.call(@text)
      end

      private

      # Maximum number of characters {#text} can hold given current width.
      def max_text_length = (rect.width - 1).clamp(0, nil)

      def insert(char)
        return false if @text.length >= max_text_length

        @text = @text.dup.insert(@caret, char)
        @caret += 1
        invalidate
        @on_change&.call(@text)
        true
      end

      def delete_before_caret
        return if @caret.zero?

        @text = @text.dup
        @text.slice!(@caret - 1)
        @caret -= 1
        invalidate
        @on_change&.call(@text)
      end

      def delete_at_caret
        return if @caret >= @text.length

        @text = @text.dup
        @text.slice!(@caret)
        invalidate
        @on_change&.call(@text)
      end

      def printable?(key)
        key.length == 1 && key.ord >= 0x20 && key.ord < 0x7f
      end
    end
  end
end
