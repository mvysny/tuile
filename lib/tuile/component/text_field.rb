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
    class TextField < TextInput
      def initialize
        super
        @on_key_up = nil
        @on_key_down = nil
        @on_enter = nil
      end

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

      # @return [Point, nil]
      def cursor_position
        return nil unless rect.width.positive?

        Point.new(rect.left + @caret, rect.top)
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left && rect.contains?(event.point)

        self.caret = (event.x - rect.left).clamp(0, @text.length)
      end

      # @return [void]
      def repaint
        return if rect.empty?

        bg = active? ? ACTIVE_BG_SGR : INACTIVE_BG_SGR
        padded = @text + (" " * (rect.width - @text.length))
        screen.print TTY::Cursor.move_to(rect.left, rect.top), bg, padded, Ansi::RESET
      end

      protected

      # Truncate to fit `rect.width - 1` — single-line fields can't grow past
      # their width.
      # @param new_text [String]
      # @return [String]
      def preprocess_text(new_text)
        new_text = new_text.to_s
        new_text.length > max_text_length ? new_text[0, max_text_length] : new_text
      end

      # @param key [String]
      # @return [Boolean]
      def handle_text_input_key(key)
        case key
        when *Keys::HOMES then self.caret = 0
        when *Keys::ENDS_ then self.caret = @text.length
        when *Keys::BACKSPACES then delete_before_caret
        when Keys::DELETE then delete_at_caret
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
          return insert(key) if Keys.printable?(key)

          return super
        end
        true
      end

      # @return [void]
      def on_width_changed
        super
        return if @text.length <= max_text_length

        @text = @text[0, [max_text_length, 0].max]
        @caret = @caret.clamp(0, @text.length)
        @on_change&.call(@text)
      end

      private

      # Maximum number of characters {#text} can hold given current width.
      # @return [Integer]
      def max_text_length = (rect.width - 1).clamp(0, nil)

      # @param char [String]
      # @return [Boolean]
      def insert(char)
        return false if @text.length >= max_text_length

        new_text = @text.dup.insert(@caret, char)
        @caret += 1
        self.text = new_text
        true
      end
    end
  end
end
