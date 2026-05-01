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
      end

      # @return [Boolean] if true and a line is added or new content is set,
      #   auto-scrolls to the bottom.
      attr_reader :auto_scroll

      # @return [Integer] top line of the viewport. 0 or positive.
      attr_reader :top_line

      # @return [Cursor] the list's cursor.
      attr_reader :cursor

      # @return [Symbol] scrollbar visibility: `:gone`, `:visible`, or
      #   `:optional`.
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
      # @param value [Symbol] `:gone`, `:visible`, or `:optional`.
      def scrollbar_visibility=(value)
        raise "Invalid scrollbar_visibility: #{value.inspect}" unless %i[gone visible optional].include?(value)
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
        raise "Not a Cursor" unless cursor.is_a? Cursor

        old_position = @cursor.position
        @cursor = cursor
        invalidate if old_position != cursor.position
      end

      # Sets the top line.
      # @param new_top_line [Integer] 0 or greater.
      def top_line=(new_top_line)
        raise "Not an Integer" unless new_top_line.is_a? Integer
        raise "#{new_top_line} must not be negative" if new_top_line.negative?
        return unless @top_line != new_top_line

        @top_line = new_top_line
        invalidate
      end

      # Sets new content, as an array of strings.
      # @param lines [Array<String>] new content.
      def content=(lines)
        raise "lines must be Array" unless lines.is_a? Array

        @lines = lines
        @content_size = nil
        update_top_line_if_auto_scroll
        invalidate
      end

      # Fully re-populates the contents in a block:
      # ```ruby
      # list.content do |lines|
      #   lines << "Hello!"
      # end
      # ```
      # @yield [lines]
      # @yieldparam lines [Array<String>] mutable buffer to push lines into.
      # @return [Array<String>] current contents (when called without a block).
      def content
        return @lines unless block_given?

        lines = []
        yield lines
        self.content = lines
      end

      # Adds a line.
      # @param line [String]
      def add_line(line)
        add_lines [line]
      end

      # Appends given lines.
      # @param lines [Array<String>]
      def add_lines(lines)
        screen.check_locked
        lines = lines.flat_map { it.to_s.split("\n") }
        @lines += lines.map(&:rstrip)
        @content_size = nil
        update_top_line_if_auto_scroll
        invalidate
      end

      def content_size
        @content_size ||= begin
          content_width = @lines.map { |line| Unicode::DisplayWidth.of(Rainbow.uncolor(line)) }.max || 0
          width = @lines.empty? ? 0 : content_width + 2
          Size.new(width, @lines.size)
        end
      end

      def focusable? = true

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
      def handle_mouse(event)
        super
        if event.button == :scroll_down
          move_top_line_by(4)
        elsif event.button == :scroll_up
          move_top_line_by(-4)
        else
          return unless rect.contains?(event.x, event.y)

          line = event.y - rect.top + top_line
          return unless @cursor.handle_mouse(line, event, @lines.size)

          move_viewport_to_cursor
          invalidate
        end
      end

      # Paints the list items into {#rect}.
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

          def handle_key(_key, _line_count, _viewport_lines)
            false
          end

          def handle_mouse(_line, _event, _line_count)
            false
          end

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

        def go_down_by(lines, line_count)
          go((@position + lines).clamp(nil, line_count - 1))
        end

        def go_up_by(lines)
          go(@position - lines)
        end

        def go_to_first
          go(0)
        end

        def go_to_last(line_count)
          go(line_count - 1)
        end

        # Cursor which can only land on specific allowed lines.
        # @param positions [Array<Integer>] allowed positions. Must not be
        #   empty.
        # @param position [Integer] initial position.
        class Limited < Cursor
          def initialize(positions, position: positions[0])
            @positions = positions.sort
            position = @positions[@positions.rindex { it < position } || 0] unless @positions.include?(position)
            super(position: position)
          end

          def handle_mouse(line, event, _line_count)
            if event.button == :left
              prev_pos = @positions.reverse_each.find { it <= line }
              return go_to_first if prev_pos.nil?

              go(prev_pos)
            else
              false
            end
          end

          def candidate_positions(line_count)
            @positions.select { it < line_count }
          end

          protected

          def go_down_by(lines, line_count)
            next_pos = @positions.find { it >= @position + lines }
            return go_to_last(line_count) if next_pos.nil?

            go(next_pos)
          end

          def go_up_by(lines)
            prev_pos = @positions.reverse_each.find { it <= @position - lines }
            return go_to_first if prev_pos.nil?

            go(prev_pos)
          end

          def go_to_first
            go(@positions.first)
          end

          def go_to_last(_line_count)
            go(@positions.last)
          end
        end
      end

      private

      def search_and_go(query, include_current:, reverse:)
        return false if query.empty?

        candidates = @cursor.candidate_positions(@lines.size)
        return false if candidates.empty?

        ordered = order_for_search(candidates, @cursor.position, include_current: include_current, reverse: reverse)
        query_lc = query.downcase
        match = ordered.find { |idx| Rainbow.uncolor(@lines[idx].to_s).downcase.include?(query_lc) }
        return false unless match

        @cursor.go(match)
        move_viewport_to_cursor
        invalidate
        true
      end

      # Rotates `candidates` (sorted ascending) so iteration starts from the
      # position appropriate for "find next" / "find prev" with optional
      # inclusion of the current.
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
      def move_top_line_by(delta)
        new_top_line = (@top_line + delta).clamp(0, top_line_max)
        return if @top_line == new_top_line

        @top_line = new_top_line
        invalidate
      end

      # If auto-scrolling, recalculate the top line.
      def update_top_line_if_auto_scroll
        return unless @auto_scroll

        new_top_line = (@lines.size - viewport_lines).clamp(0, nil)
        return unless @top_line != new_top_line

        self.top_line = new_top_line
      end

      # @return [Boolean] whether the scrollbar should be drawn right now.
      def scrollbar_visible?
        return false if rect.empty?

        case @scrollbar_visibility
        when :gone then false
        when :visible then true
        when :optional then @lines.size > rect.height
        end
      end

      # Trims string exactly to `width` columns.
      def trim_to(str, width)
        return " " * width if str.empty?

        truncated_line = Strings::Truncation.truncate(str, length: width)
        return truncated_line unless truncated_line == str

        length = Unicode::DisplayWidth.of(Rainbow.uncolor(str))
        str += " " * (width - length) if length < width
        str
      end

      # @param index [Integer] 0-based index into {#content}.
      # @param row_in_viewport [Integer] 0-based row within the viewport.
      # @param width [Integer] number of columns the line should occupy.
      # @param scrollbar [VerticalScrollBar, nil] scrollbar instance, or nil if
      #   not shown.
      # @return [String] paintable line exactly `width` columns wide;
      #   highlighted if cursor is here.
      def paintable_line(index, row_in_viewport, width, scrollbar)
        content_width = scrollbar ? width - 1 : width
        line = (@lines[index] || "").to_s
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
