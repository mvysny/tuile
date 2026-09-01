# frozen_string_literal: true

module Tuile
  # Which glyph to draw at each row of a scrollbar. Built fresh per repaint from
  # the viewport height and the content's scroll state, then asked row by row —
  # the caller styles what comes back:
  #
  #   bar = VerticalScrollBar.new(10, row_count: 20, scroll_top_row: 0)
  #   bar.scrollbar_char(0)   # => "█"  the handle: 20 rows of content, 10 shown
  #   bar.scrollbar_char(9)   # => "░"  the track below it
  #   StyledString.styled(bar.scrollbar_char(row), fg: screen.theme.scrollbar_color)
  #
  # No arrows — the full height is the track — and no color of its own, so this
  # class reaches no {Screen}. {handle_char=} / {track_char=} swap the two
  # glyphs app-wide.
  #
  # **No handle is drawn when the content fits.** A handle covering the whole
  # track is a solid column carrying no information, so `row_count <= height`
  # paints track at every row — while {#handle_height} / {#handle_start} /
  # {#handle_end} still report the covering handle. Ink only: the caller's bar
  # keeps its column and its content width (`DECISIONS.md` `D_scrollbar_ink`).
  class VerticalScrollBar
    class << self
      # The glyph drawn where the handle covers a row, `█` by default. Set the
      # pair at startup for a lazygit-style bar:
      #
      #   Tuile::VerticalScrollBar.handle_char = "▐"
      #   Tuile::VerticalScrollBar.track_char  = "│"
      #
      # Process-global, and assigning invalidates nothing — a change after the
      # first paint shows up only where something repaints anyway.
      # @return [String]
      attr_reader :handle_char

      # The glyph drawn on the rows the handle doesn't cover, `░` by default —
      # and on every row when the content fits, see the class docs.
      # @return [String]
      attr_reader :track_char

      # @param char [String]
      # @return [String]
      # @raise [TypeError] when `char` is not a String.
      # @raise [ArgumentError] when `char` is not exactly one grapheme cluster
      #   one column wide.
      def handle_char=(char)
        @handle_char = validate_glyph(char, :handle_char)
      end

      # @param char [String] see {handle_char=}.
      # @return [String]
      def track_char=(char)
        @track_char = validate_glyph(char, :track_char)
      end

      private

      # One cell, exactly: a painter concatenates the glyph onto a row already
      # padded to fill the rest of its rect, so a two-column one pushes every
      # painted row past `rect.width` — silently, with nothing in the frame to
      # point at.
      # @param char [String]
      # @param name [Symbol] the accessor, for the message.
      # @return [String] frozen.
      def validate_glyph(char, name)
        raise TypeError, "#{name} must be a String, got #{char.inspect}" unless char.is_a?(String)

        unless char.grapheme_clusters.size == 1
          raise ArgumentError, "#{name} must be exactly one grapheme cluster, got #{char.inspect}"
        end

        width = StyledString.plain(char).display_width
        raise ArgumentError, "#{name} must be one column wide, got #{char.inspect} (#{width})" unless width == 1

        -char
      end
    end

    self.handle_char = "█"
    self.track_char = "░"

    # @return [Integer] number of track rows the handle occupies (height >= 1
    #   only).
    attr_reader :handle_height
    # @return [Integer] 0-based row where the handle starts (height >= 1 only).
    attr_reader :handle_start
    # @return [Integer] 0-based row where the handle ends (height >= 1 only).
    attr_reader :handle_end

    # @param height [Integer] number of rows in the scrollbar (== viewport
    #   height).
    # @param row_count [Integer] total number of content rows.
    # @param scroll_top_row [Integer] index of the first visible content row.
    def initialize(height, row_count:, scroll_top_row:)
      @height = height
      @scrollable = row_count > height

      return unless height >= 1

      if @scrollable
        @handle_height = [(height * height / row_count.to_f).ceil, 1].max
        @handle_start  = (height * scroll_top_row / row_count.to_f).floor
        @handle_end    = @handle_start + @handle_height - 1
      else
        @handle_height = height
        @handle_start  = 0
        @handle_end    = height - 1
      end
    end

    # The glyph for one viewport row: {VerticalScrollBar.handle_char} where the
    # handle covers it, {VerticalScrollBar.track_char} elsewhere — and at every
    # row when the content fits (see the class docs).
    # @param row_in_viewport [Integer] 0-based row index within the viewport.
    # @return [String] single scrollbar character.
    def scrollbar_char(row_in_viewport)
      return self.class.track_char unless @scrollable

      on_handle = row_in_viewport >= @handle_start && row_in_viewport <= @handle_end
      on_handle ? self.class.handle_char : self.class.track_char
    end
  end
end
