# frozen_string_literal: true

module Tuile
  class Component
    # Abstract base for editable text components ({TextField}, {TextArea}).
    #
    # Holds the shared state — a mutable {#text} buffer, a {#caret} index,
    # {#on_change} and {#on_escape} callbacks — and the keyboard machinery
    # that single-line and multi-line inputs both need: ESC handling,
    # LEFT/RIGHT caret movement, CTRL+LEFT/CTRL+RIGHT word jumps, and the
    # `focusable?`/`tab_stop?` flags.
    #
    # Subclasses implement the layout-specific pieces ({#cursor_position},
    # {#repaint}) and add their own keys (HOME/END, ENTER, UP/DOWN,
    # printable insertion) by overriding the protected
    # {#handle_text_input_key} hook — `super` falls through to the common
    # navigation handling.
    #
    # The mutation pipeline is a template method: {#text=} and {#caret=}
    # detect no-ops, mutate state, fire {#on_change}, and invalidate.
    # Subclasses inject their own behavior via two protected hooks:
    #
    # - {#preprocess_text} — input filter (e.g. {TextField} truncates to
    #   fit `rect.width - 1`).
    # - {#on_text_mutated} / {#on_caret_mutated} — post-mutation side
    #   effects (e.g. {TextArea} invalidates its wrap cache and scrolls to
    #   keep the caret visible).
    class TextInput < Component
      def initialize
        super
        @text = +""
        @caret = 0
        @on_change = nil
        @on_escape = method(:default_on_escape)
      end

      # @return [String] current text contents.
      attr_reader :text

      # @return [Integer] caret index in `0..text.length`.
      attr_reader :caret

      # Optional callback fired whenever {#text} changes. Receives the new text
      # as a single argument. Not fired by {#caret=} (text unchanged) and not
      # fired when a setter is a no-op.
      # @return [Proc, Method, nil] one-arg callable, or nil.
      attr_accessor :on_change

      # Callback fired when ESC is pressed. Defaults to a closure that clears
      # focus (`screen.focused = nil`) so ESC visibly cancels text entry instead
      # of bubbling to the parent — and, in particular, instead of reaching the
      # screen's default ESC-to-quit handler. Set to nil to let ESC fall through
      # to the parent again; set to any other callable to replace the default.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_escape

      def focusable? = true

      def tab_stop? = true

      # Sets the text. Runs {#preprocess_text} first (subclasses may filter or
      # truncate). Caret is clamped to the new text length. Fires {#on_change}
      # only on a real change.
      # @param new_text [String]
      def text=(new_text)
        new_text = preprocess_text(new_text)
        return if @text == new_text

        @text = +new_text
        @caret = @caret.clamp(0, @text.length)
        on_text_mutated
        invalidate
        @on_change&.call(@text)
      end

      # Sets the caret position. Clamped to `0..text.length`. Fires
      # {#on_caret_mutated} hook for subclasses (e.g. {TextArea} scrolls).
      # @param new_caret [Integer]
      def caret=(new_caret)
        new_caret = new_caret.clamp(0, @text.length)
        return if @caret == new_caret

        @caret = new_caret
        on_caret_mutated
        invalidate
      end

      # 256-color SGR for the focused-button highlight (matches what
      # `Rainbow(...).bg(:darkslategray)` emits, which is what
      # {Component::Button#repaint} uses for its focused state).
      # @return [String]
      ACTIVE_BG_SGR = "\e[48;5;59m"
      # 256-color SGR for the unfocused field's "well": index 238 sits in
      # the grayscale ramp (~#444444), bright enough to stand out against
      # non-pure-black terminal themes (Gruvbox/Solarized/OneDark base
      # backgrounds sit in the #1d–#2d range), and still distinctly darker
      # than the active highlight at index 59 (~#5f5f5f). Rainbow's
      # RGB-to-256 mapping snaps everything dark to palette index 16
      # (terminal black), so we emit the escape directly to reach the ramp.
      # @return [String]
      INACTIVE_BG_SGR = "\e[48;5;238m"

      # Handles a key. Returns false when the component is inactive. Otherwise
      # first runs the {Component#handle_key} shortcut search via `super`, then
      # delegates to {#handle_text_input_key}.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return false unless active?
        return true if super

        handle_text_input_key(key)
      end

      protected

      # Input filter for {#text=}. Subclasses override to truncate or reject
      # invalid input. Default coerces to String.
      # @param new_text [String]
      # @return [String] possibly transformed text.
      def preprocess_text(new_text) = new_text.to_s

      # Hook called after {#text} has been mutated, before invalidation /
      # {#on_change}. Default no-op. Subclasses use this to invalidate caches
      # ({TextArea}'s wrap cache) and update derived state.
      # @return [void]
      def on_text_mutated; end

      # Hook called after {#caret} has been mutated, before invalidation.
      # Default no-op. Subclasses use this to keep the caret visible
      # ({TextArea}'s vertical scroll).
      # @return [void]
      def on_caret_mutated; end

      # Dispatch hook for {#handle_key}. Handles ESC and the navigation keys
      # that have identical semantics in single-line and multi-line inputs:
      # LEFT/RIGHT arrows, CTRL+LEFT/CTRL+RIGHT for word jumps. Subclasses
      # override to add their own keys (HOME/END, UP/DOWN, ENTER, BACKSPACE/
      # DELETE, printable insertion) and call `super` to fall back to the
      # common navigation handling.
      # @param key [String]
      # @return [Boolean] true if the key was handled.
      def handle_text_input_key(key)
        case key
        when Keys::LEFT_ARROW then self.caret = @caret - 1
        when Keys::RIGHT_ARROW then self.caret = @caret + 1
        when Keys::CTRL_LEFT_ARROW then self.caret = word_left
        when Keys::CTRL_RIGHT_ARROW then self.caret = word_right
        when Keys::ESC
          return false if @on_escape.nil?

          @on_escape.call
        else
          return false
        end
        true
      end

      # @return [void]
      def delete_before_caret
        return if @caret.zero?

        new_text = @text.dup
        new_text.slice!(@caret - 1)
        @caret -= 1
        self.text = new_text
      end

      # @return [void]
      def delete_at_caret
        return if @caret >= @text.length

        new_text = @text.dup
        new_text.slice!(@caret)
        self.text = new_text
      end

      private

      # Default {#on_escape} action: clear focus. Component deactivates; user
      # can re-focus by clicking or tabbing back in.
      # @return [void]
      def default_on_escape
        screen.focused = nil
      end

      # Caret target for ctrl+left: skip whitespace going left, then a run of
      # non-whitespace. Lands at the beginning of the current word, or the
      # beginning of the previous word if already there.
      # @return [Integer]
      def word_left
        c = @caret
        c -= 1 while c.positive? && @text[c - 1].match?(/\s/)
        c -= 1 while c.positive? && !@text[c - 1].match?(/\s/)
        c
      end

      # Caret target for ctrl+right: skip non-whitespace going right, then a
      # run of whitespace. Lands at the beginning of the next word, or at the
      # end of the text if no further word exists.
      # @return [Integer]
      def word_right
        c = @caret
        c += 1 while c < @text.length && !@text[c].match?(/\s/)
        c += 1 while c < @text.length && @text[c].match?(/\s/)
        c
      end
    end
  end
end
