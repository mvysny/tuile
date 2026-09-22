# frozen_string_literal: true

module Tuile
  class Component
    # Fills every cell of its {#rect} with one glyph. Give it a one-column rect
    # and `│` for a vertical rule between two borderless panes, a one-row rect
    # and `─` for a horizontal one — the glyph decides the direction, the parent
    # decides the length:
    #
    #   rule = Component::Fill.new("│", color: Theme.ref(:pane_frame))
    #   bottom = Component::Layout::Horizontal.new
    #   bottom.add(system_pane, Layout::Percent[40])
    #   bottom.add(rule, Layout::Fixed[1])
    #   bottom.add(log_pane, Layout::Expand[1])
    #
    # Display-only — not focusable, no keys, no mouse. The background behind
    # the glyph is its own {Component#bg_color}, else inherited, as for any
    # component.
    class Fill < Component
      # @param char [String] initial {#char=}.
      # @param color [Color, Theme::Ref, Symbol, Integer, Array<Integer>, nil]
      #   initial {#color=}.
      # @raise [ArgumentError, TypeError] see {#char=} and {#color=}.
      def initialize(char, color: nil)
        super()
        @char = StyledString.validate_glyph(char, :char)
        @color = nil
        self.color = color
      end

      # @return [String] the glyph painted into every cell; one grapheme
      #   cluster, one column wide.
      attr_reader :char

      # @return [Color, Theme::Ref, nil] the value as set, so a {Theme::Ref}
      #   comes back unresolved; `nil` (the default) is the terminal's default
      #   foreground.
      attr_reader :color

      # @param char [String]
      # @return [void]
      # @raise [TypeError] when `char` is not a String.
      # @raise [ArgumentError] when `char` is not exactly one grapheme cluster
      #   one column wide.
      def char=(char)
        char = StyledString.validate_glyph(char, :char)
        return if @char == char

        @char = char
        invalidate
      end

      # Sets the glyph's color, live-resolved at paint time when given a
      # {Theme::Ref} (so it follows a {Screen#theme=} with no
      # {Component#handle_theme_changed} hook).
      #
      #   rule.color = :bright_black
      #   rule.color = Theme.ref(:pane_frame)   # an app #custom token
      #
      # @param color [Color, Theme::Ref, Symbol, Integer, Array<Integer>, nil]
      #   coerced via {Color.coerce} unless it is a {Theme::Ref}; `nil` is the
      #   terminal default.
      # @return [void]
      # @raise [KeyError] when a {Theme::Ref} names a token the current theme
      #   lacks.
      def color=(color)
        color = Color.coerce(color) unless color.is_a?(Theme::Ref)
        return if @color == color

        color.resolve(screen.theme) if color.is_a?(Theme::Ref) # fail fast on a bad token

        @color = color
        invalidate
      end

      # Paints {#char} into every cell. Not `super`: the default's clear would
      # dirty every cell just before it is painted over.
      # @param canvas [Canvas] see {Component#repaint}.
      # @return [void]
      def repaint(canvas)
        return if rect.empty?

        row = StyledString.styled(@char * rect.width, fg: resolved_color)
        rect.height.times { canvas.set_text(0, _1, row) }
      end

      private

      # @return [Color, nil]
      def resolved_color = @color.is_a?(Theme::Ref) ? @color.resolve(screen.theme) : @color
    end
  end
end
