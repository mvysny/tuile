# frozen_string_literal: true

module Tuile
  class Component
    # A scrollable list of String items with cursor support.
    #
    # Items are lines painted directly into the component's {#rect}. Lines are
    # automatically clipped horizontally. Vertical scrolling is supported via
    # {#top_line}; the list can also automatically scroll to the bottom if
    # {#auto_scroll} is enabled.
    #
    # Cursor is supported; call {#cursor=} to change cursor behavior. The
    # cursor responds to arrows, `jk`, Home/End, Ctrl+U/D and scrolls the list
    # automatically.
    class List < Component
      def initialize
        super
        @lines = []
        @auto_scroll = false
        @top_line = 0
        @cursor = Cursor::None.new
        @scrollbar_visibility = :gone
        @show_cursor_when_inactive = false
        @on_item_chosen = nil
      end

      # @return [Proc, nil] callback fired when an item is chosen — by pressing
      #   Enter on the cursor's item, or by left-clicking an item. Called as
      #   `proc.call(index, line)` with the chosen 0-based index and its line.
      #   Never fires when the cursor's position is outside the content (e.g.
      #   {Cursor::None}, or empty content).
      attr_accessor :on_item_chosen

      # @return [Boolean] if true and a line is added or new content is set,
      #   auto-scrolls to the bottom.
      attr_reader :auto_scroll

      # @return [Integer] top line of the viewport. 0 or positive.
      attr_reader :top_line

      # @return [Cursor] the list's cursor.
      attr_reader :cursor

      # @return [Symbol] scrollbar visibility: `:gone` or `:visible`.
      attr_reader :scrollbar_visibility

      # @return [Boolean] when true, the cursor highlight is painted even while
      #   the list is inactive (e.g. when focus is on a sibling search field).
      #   Defaults to false.
      attr_reader :show_cursor_when_inactive

      # @param value [Boolean]
      def show_cursor_when_inactive=(value)
        value = value ? true : false
        return if @show_cursor_when_inactive == value

        @show_cursor_when_inactive = value
        invalidate
      end

      # Sets the scrollbar visibility.
      # @param value [Symbol] `:gone` or `:visible`.
      def scrollbar_visibility=(value)
        raise ArgumentError, "expected :gone or :visible, got #{value.inspect}" unless %i[gone visible].include?(value)
        return if @scrollbar_visibility == value

        @scrollbar_visibility = value
        invalidate
      end

      # Sets the new auto_scroll. If true, immediately scrolls to the bottom.
      # @param new_auto_scroll [Boolean]
      def auto_scroll=(new_auto_scroll)
        @auto_scroll = new_auto_scroll
        update_top_line_if_auto_scroll
      end

      # Sets a new cursor.
      # @param cursor [Cursor] new cursor.
      def cursor=(cursor)
        raise TypeError, "expected Cursor, got #{cursor.inspect}" unless cursor.is_a? Cursor

        old_position = @cursor.position
        @cursor = cursor
        invalidate if old_position != cursor.position
      end

      # Sets the top line.
      # @param new_top_line [Integer] 0 or greater.
      def top_line=(new_top_line)
        raise TypeError, "expected Integer, got #{new_top_line.inspect}" unless new_top_line.is_a? Integer
        raise ArgumentError, "top_line must not be negative, got #{new_top_line}" if new_top_line.negative?
        return unless @top_line != new_top_line

        @top_line = new_top_line
        invalidate
      end

      # Sets new lines. Each entry is coerced via `#to_s`, split on `\n` into
      # separate lines, and trailing whitespace stripped — symmetric with
      # {#add_lines}, so the stored `@lines` is always `Array<String>`.
      # @param lines [Array] new lines. Entries need only respond to `#to_s`.
      # @return [void]
      def lines=(lines)
        raise TypeError, "expected Array, got #{lines.inspect}" unless lines.is_a? Array

        @lines = lines.flat_map { it.to_s.split("\n") }.map(&:rstrip)
        @content_size = nil
        update_top_line_if_auto_scroll
        invalidate
      end

      # Without a block, returns the current lines. With a block, fully
      # re-populates the list:
      # ```ruby
      # list.lines do |buffer|
      #   buffer << "Hello!"
      # end
      # ```
      # @yield [buffer]
      # @yieldparam buffer [Array<String>] mutable buffer to push lines into.
      # @yieldreturn [void]
      # @return [Array<String>] current lines (when called without a block).
      def lines
        return @lines unless block_given?

        buffer = []
        yield buffer
        self.lines = buffer
      end

      # Adds a line.
      # @param line [String]
      # @return [void]
      def add_line(line)
        add_lines [line]
      end

      # Appends given lines. Each entry is coerced via `#to_s`, split on `\n`
      # into separate lines, and trailing whitespace stripped — symmetric with
      # {#lines=}.
      # @param lines [Array] entries need only respond to `#to_s`.
      # @return [void]
      def add_lines(lines)
        screen.check_locked
        @lines += lines.flat_map { it.to_s.split("\n") }.map(&:rstrip)
        @content_size = nil
        update_top_line_if_auto_scroll
        invalidate
      end

      # @return [Size]
      def content_size
        @content_size ||= begin
          content_width = @lines.map { |line| Unicode::DisplayWidth.of(Rainbow.uncolor(line)) }.max || 0
          width = @lines.empty? ? 0 : content_width + 2
          Size.new(width, @lines.size)
        end
      end

      def focusable? = true

      def tab_stop? = true

      # @param key [String] a key.
      # @return [Boolean] true if the key was handled.
      def handle_key(key)
        if !active?
          false
        elsif super
          true
        elsif key == Keys::PAGE_UP
          move_top_line_by(-viewport_lines)
          true
        elsif key == Keys::PAGE_DOWN
          move_top_line_by(viewport_lines)
          true
        elsif key == Keys::ENTER && cursor_on_item?
          fire_item_chosen
          true
        elsif @cursor.handle_key(key, @lines.size, viewport_lines)
          move_viewport_to_cursor
          invalidate
          true
        else
          false
        end
      end

      # Moves the cursor to the next line whose text contains `query`
      # (case-insensitive substring match). Search wraps around the end of the
      # list. Only lines reachable by the current {#cursor} are considered.
      #
      # @param query [String] substring to match. Empty query never matches.
      # @param include_current [Boolean] when true, the current cursor position
      #   is eligible (useful when the query has just changed and the current
      #   line may still match); when false, the search starts after the
      #   current position (useful for "find next" key bindings that should
      #   advance past the current).
      # @return [Boolean] true if a match was found.
      def select_next(query, include_current: false)
        search_and_go(query, include_current: include_current, reverse: false)
      end

      # Mirror of {#select_next} that walks the list backwards.
      # @param query [String]
      # @param include_current [Boolean]
      # @return [Boolean] true if a match was found.
      def select_prev(query, include_current: false)
        search_and_go(query, include_current: include_current, reverse: true)
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        if event.button == :scroll_down
          move_top_line_by(4)
        elsif event.button == :scroll_up
          move_top_line_by(-4)
        else
          return unless rect.contains?(event.point)

          line = event.y - rect.top + top_line
          if @cursor.handle_mouse(line, event, @lines.size)
            move_viewport_to_cursor
            invalidate
          end
          fire_item_chosen if event.button == :left && line >= 0 && line < @lines.size && cursor_on_item?
        end
      end

      # Paints the list items into {#rect}.
      # @return [void]
      def repaint
        super
        return if rect.empty?

        width = rect.width
        scrollbar = if scrollbar_visible?
                      VerticalScrollBar.new(rect.height, line_count: @lines.size, top_line: @top_line)
                    end
        (0..(rect.height - 1)).each do |line_no|
          line_index = line_no + @top_line
          line = paintable_line(line_index, line_no, width, scrollbar)
          screen.print TTY::Cursor.move_to(rect.left, line_no + rect.top), line
        end
      end

      # Tracks cursor position within the list.
      class Cursor
        # @param position [Integer] the initial cursor position.
        def initialize(position: 0)
          @position = position
        end

        # No cursor — cursor is disabled.
        class None < Cursor
          def initialize
            super(position: -1)
            freeze
          end

          # @param _key [String]
          # @param _line_count [Integer]
          # @param _viewport_lines [Integer]
          # @return [Boolean]
          def handle_key(_key, _line_count, _viewport_lines)
            false
          end

          # @param _line [Integer]
          # @param _event [MouseEvent]
          # @param _line_count [Integer]
          # @return [Boolean]
          def handle_mouse(_line, _event, _line_count)
            false
          end

          # @param _line_count [Integer]
          # @return [Array<Integer>]
          def candidate_positions(_line_count)
            []
          end
        end

        # @return [Integer] 0-based line index of the current cursor position.
        attr_reader :position

        # @param line_count [Integer] number of lines in the list.
        # @return [Array<Integer>] positions the cursor can land on, in
        #   ascending order.
        def candidate_positions(line_count)
          (0...line_count).to_a
        end

        # @param key [String] pressed keyboard key.
        # @param line_count [Integer] number of lines in the list.
        # @param viewport_lines [Integer] number of visible lines.
        # @return [Boolean] true if the cursor moved.
        def handle_key(key, line_count, viewport_lines)
          case key
          when *Keys::DOWN_ARROWS
            go_down_by(1, line_count)
          when *Keys::UP_ARROWS
            go_up_by(1)
          when Keys::HOME
            go_to_first
          when Keys::END_
            go_to_last(line_count)
          when Keys::CTRL_U
            go_up_by(viewport_lines / 2)
          when Keys::CTRL_D
            go_down_by(viewport_lines / 2, line_count)
          else
            false
          end
        end

        # @param line [Integer] cursor is hovering over this line.
        # @param event [MouseEvent] the event.
        # @param line_count [Integer] number of lines in the list.
        # @return [Boolean] true if the event was handled.
        def handle_mouse(line, event, line_count)
          if event.button == :left
            go(line.clamp(nil, line_count - 1))
          else
            false
          end
        end

        # Moves the cursor to the new position. Public only because of testing.
        # @param new_position [Integer] new 0-based cursor position.
        # @return [Boolean] true if the position changed.
        def go(new_position)
          new_position = new_position.clamp(0, nil)
          return false if @position == new_position

          @position = new_position
          true
        end

        protected

        # @param lines [Integer]
        # @param line_count [Integer]
        # @return [Boolean]
        def go_down_by(lines, line_count)
          go((@position + lines).clamp(nil, line_count - 1))
        end

        # @param lines [Integer]
        # @return [Boolean]
        def go_up_by(lines)
          go(@position - lines)
        end

        # @return [Boolean]
        def go_to_first
          go(0)
        end

        # @param line_count [Integer]
        # @return [Boolean]
        def go_to_last(line_count)
          go(line_count - 1)
        end

        # Cursor which can only land on specific allowed lines.
        class Limited < Cursor
          # @param positions [Array<Integer>] allowed positions. Must not be
          #   empty.
          # @param position [Integer] initial position.
          def initialize(positions, position: positions[0])
            @positions = positions.sort
            position = @positions[@positions.rindex { it < position } || 0] unless @positions.include?(position)
            super(position: position)
          end

          # @param line [Integer]
          # @param event [MouseEvent]
          # @param _line_count [Integer]
          # @return [Boolean]
          def handle_mouse(line, event, _line_count)
            if event.button == :left
              prev_pos = @positions.reverse_each.find { it <= line }
              return go_to_first if prev_pos.nil?

              go(prev_pos)
            else
              false
            end
          end

          # @param line_count [Integer]
          # @return [Array<Integer>]
          def candidate_positions(line_count)
            @positions.select { it < line_count }
          end

          protected

          # @param lines [Integer]
          # @param line_count [Integer]
          # @return [Boolean]
          def go_down_by(lines, line_count)
            next_pos = @positions.find { it >= @position + lines }
            return go_to_last(line_count) if next_pos.nil?

            go(next_pos)
          end

          # @param lines [Integer]
          # @return [Boolean]
          def go_up_by(lines)
            prev_pos = @positions.reverse_each.find { it <= @position - lines }
            return go_to_first if prev_pos.nil?

            go(prev_pos)
          end

          # @return [Boolean]
          def go_to_first
            go(@positions.first)
          end

          # @param _line_count [Integer]
          # @return [Boolean]
          def go_to_last(_line_count)
            go(@positions.last)
          end
        end
      end

      private

      # @return [Boolean] true if the cursor sits on a real content line.
      def cursor_on_item?
        pos = @cursor.position
        pos >= 0 && pos < @lines.size
      end

      # Calls {#on_item_chosen} with the cursor's current `(index, line)`.
      # Caller must ensure {#cursor_on_item?}.
      # @return [void]
      def fire_item_chosen
        pos = @cursor.position
        @on_item_chosen&.call(pos, @lines[pos])
      end

      # @param query [String]
      # @param include_current [Boolean]
      # @param reverse [Boolean]
      # @return [Boolean]
      def search_and_go(query, include_current:, reverse:)
        return false if query.empty?

        candidates = @cursor.candidate_positions(@lines.size)
        return false if candidates.empty?

        ordered = order_for_search(candidates, @cursor.position, include_current: include_current, reverse: reverse)
        query_lc = query.downcase
        match = ordered.find { |idx| Rainbow.uncolor(@lines[idx]).downcase.include?(query_lc) }
        return false unless match

        @cursor.go(match)
        move_viewport_to_cursor
        invalidate
        true
      end

      # Rotates `candidates` (sorted ascending) so iteration starts from the
      # position appropriate for "find next" / "find prev" with optional
      # inclusion of the current.
      # @param candidates [Array<Integer>]
      # @param current [Integer]
      # @param include_current [Boolean]
      # @param reverse [Boolean]
      # @return [Array<Integer>]
      def order_for_search(candidates, current, include_current:, reverse:)
        if reverse
          before, after = if include_current
                            [candidates.select { it <= current }, candidates.select { it > current }]
                          else
                            [candidates.select { it < current }, candidates.select { it >= current }]
                          end
          before.reverse + after.reverse
        else
          after, before = if include_current
                            [candidates.select { it >= current }, candidates.select { it < current }]
                          else
                            [candidates.select { it > current }, candidates.select { it <= current }]
                          end
          after + before
        end
      end

      # Scrolls the viewport so the cursor is visible.
      # @return [void]
      def move_viewport_to_cursor
        pos = @cursor.position
        return unless pos >= 0

        if @top_line > pos
          self.top_line = pos
        elsif pos > @top_line + rect.height - 1
          self.top_line = pos - rect.height + 1
        end
      end

      # @return [Integer] the max value of {#top_line}.
      def top_line_max = (@lines.size - rect.height).clamp(0, nil)

      # @return [Integer] the number of visible lines.
      def viewport_lines = rect.height

      # Scrolls the list.
      # @param delta [Integer] negative scrolls up, positive scrolls down.
      # @return [void]
      def move_top_line_by(delta)
        new_top_line = (@top_line + delta).clamp(0, top_line_max)
        return if @top_line == new_top_line

        @top_line = new_top_line
        invalidate
      end

      # If auto-scrolling, recalculate the top line.
      # @return [void]
      def update_top_line_if_auto_scroll
        return unless @auto_scroll

        new_top_line = (@lines.size - viewport_lines).clamp(0, nil)
        return unless @top_line != new_top_line

        self.top_line = new_top_line
      end

      # @return [Boolean] whether the scrollbar should be drawn right now.
      def scrollbar_visible?
        return false if rect.empty?

        @scrollbar_visibility == :visible
      end

      # Trims string exactly to `width` columns.
      # @param str [String]
      # @param width [Integer]
      # @return [String]
      def trim_to(str, width)
        return " " * width if str.empty?

        truncated_line = Truncate.truncate(str, length: width)
        return truncated_line unless truncated_line == str

        length = Unicode::DisplayWidth.of(Rainbow.uncolor(str))
        str += " " * (width - length) if length < width
        str
      end

      # @param index [Integer] 0-based index into {#lines}.
      # @param row_in_viewport [Integer] 0-based row within the viewport.
      # @param width [Integer] number of columns the line should occupy.
      # @param scrollbar [VerticalScrollBar, nil] scrollbar instance, or nil if
      #   not shown.
      # @return [String] paintable line exactly `width` columns wide;
      #   highlighted if cursor is here.
      def paintable_line(index, row_in_viewport, width, scrollbar)
        content_width = scrollbar ? width - 1 : width
        line = @lines[index] || ""
        line = trim_to(line, content_width - 2)
        line = " #{line} "
        is_cursor = (active? || @show_cursor_when_inactive) && index < @lines.size && @cursor.position == index
        line = if is_cursor
                 Rainbow(Rainbow.uncolor(line)).bg(:darkslategray)
               else
                 line
               end
        return line unless scrollbar

        line + scrollbar.scrollbar_char(row_in_viewport)
      end
    end
  end
end
