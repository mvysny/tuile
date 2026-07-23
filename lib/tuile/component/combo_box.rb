# frozen_string_literal: true

module Tuile
  class Component
    # A text field with a filtering dropdown: type to narrow the candidates,
    # arrow to move the highlight, Enter (or click) to accept. Its {#value} is
    # the *selected item* — of whatever type the items are — not the display
    # string, so a combo over domain objects hands back the object:
    #
    #   combo = Component::ComboBox.new
    #   combo.items = User.all                       # Array of any type
    #   combo.item_label = ->(u) { u.full_name }     # item -> shown text; default :to_s
    #   combo.on_value_change = ->(u) { open(u) }    # fires on commit, with the item
    #   combo.value = some_user                       # selects it; field shows its label
    #
    # It's the assembly you'd otherwise wire by hand — a {TextField} plus a
    # non-modal {Popup} over a {List} — promoted to one component. Give it a
    # single-row {#rect}; it paints the field across that row with a `▾` in the
    # last column and floats the dropdown above or below.
    #
    # == The two values
    # {#value} (the committed selection) and the field's typed text (a transient
    # *query*) are deliberately distinct. Keystrokes move the query and refilter
    # the list; only Enter/click commits, and only a commit changes {#value} and
    # fires {#on_value_change}. An uncommitted query reverts to the current
    # value's label when the dropdown is dismissed (ESC) or the combo loses
    # focus. Selecting by list index (not by matching the label back) is what
    # lets two items share a label and still resolve to the right object.
    #
    # == Theming
    # The dropdown is borderless, told apart from the content beneath it by a
    # background tint — {Theme#input_bg_color} by default, assigned as a live
    # {Theme::Ref} so it tracks light/dark flips with no hook. Set {#bg_color=}
    # for a different tint (a `Theme.ref(:token)` keeps the flip-tracking).
    #
    # UI-thread-confined, like every component (see {Screen}).
    class ComboBox < Component
      include HasValue

      # The dropdown's list. Non-focusable on purpose: the combo drives it by
      # forwarding keys while focus (and the caret) stay in the field, and a
      # mouse click selects an item without stealing focus — so the field never
      # loses the cursor mid-interaction.
      class Menu < List
        def focusable? = false
        def tab_stop? = false
      end

      # @param items [Array] the candidate items (any type); also settable via
      #   {#items=}.
      def initialize(items: [])
        super()
        @value = nil
        @on_value_change = nil
        @items = items.to_a
        @item_label = :to_s.to_proc
        @filtered = []
        @suppressing_filter = false

        @field = TextField.new
        @field.parent = self
        @field.on_change = ->(_text) { refill unless @suppressing_filter }
        @field.on_key = method(:field_key)

        @menu = Menu.new
        @menu.cursor = List::Cursor.new
        @menu.show_cursor_when_inactive = true
        @menu.on_item_chosen = ->(index, _line) { commit(index) }

        @overlay = Popup.new(content: @menu, modal: false)
        @overlay.bg_color = Theme.ref(:input_bg_color)
      end

      # @return [Array] the candidate items.
      attr_reader :items

      # @return [Proc, Method] item -> shown label (a `String` or
      #   {StyledString}); the field shows its `#to_s`, the list its styled form.
      attr_reader :item_label

      # @param new_items [Array]
      # @return [void]
      def items=(new_items)
        raise TypeError, "expected Array, got #{new_items.inspect}" unless new_items.is_a?(Array)

        @items = new_items
        refill if @overlay.open?
        invalidate
      end

      # @param proc [Proc, Method] item -> shown label.
      # @return [void]
      def item_label=(proc)
        @item_label = proc
        sync_field(display_for(value)) # re-render the current selection
        invalidate
      end

      # Selects `new_value` programmatically: updates the field to its label
      # *without* opening the dropdown, then fires {#on_value_change}. `nil`
      # clears the selection (blank field). The value need not be in {#items}.
      # @param new_value [Object]
      # @return [void]
      def value=(new_value)
        return if value == new_value

        sync_field(display_for(new_value))
        super
      end

      def focusable? = true

      # @return [Point, nil] the field's caret position (the combo delegates the
      #   hardware cursor to its field).
      def cursor_position = @field.cursor_position

      # @return [String]
      def keyboard_hint = "↑↓ #{screen.theme.hint("select")}  ⏎ #{screen.theme.hint("accept")}"

      # @return [Array<Component>]
      def children = [@field]

      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        super
        # Field spans the row bar the last column, which the `▾` occupies.
        @field.rect = Rect.new(new_rect.left, new_rect.top, [new_rect.width - 1, 0].max, 1)
        anchor if @overlay.open?
      end

      # @return [void]
      def on_focus
        super
        screen.focused = @field
      end

      # Closes the dropdown and reverts an uncommitted query when the combo
      # leaves the focus chain — so tabbing away doesn't strand an open menu or
      # a half-typed filter. Safe against re-entrancy: focus never sits inside
      # the (non-focusable) {Menu}, so closing the overlay repairs no focus.
      # @param flag [Boolean]
      # @return [void]
      def active=(flag)
        was = active?
        super
        return unless was && !active?

        close_menu
        revert_query
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        if @field.rect.contains?(event.point)
          @field.handle_mouse(event)
        elsif event.button == :left && rect.contains?(event.point) # the ▾ cell
          @field.focus
          @overlay.open? ? close_menu : open_menu
        end
      end

      # @return [void]
      def repaint
        super
        return if rect.empty?

        well = active? ? screen.theme.active_bg_color : screen.theme.input_bg_color
        draw_char(rect.left + rect.width - 1, rect.top, "▾", StyledString::Style::DEFAULT.with(bg: well))
      end

      private

      # The field's key interceptor: forwards navigation to the open menu (Up/
      # Down move, Enter commits, ESC dismisses), and opens it on Down or Enter
      # when closed. Everything else (printable keys, editing) falls through to
      # the field, whose {TextField#on_change} refilters.
      # @param key [String]
      # @return [Boolean] true if consumed.
      def field_key(key)
        if @overlay.open?
          case key
          when Keys::UP_ARROW, Keys::DOWN_ARROW, Keys::ENTER
            @menu.handle_key(key)
            true
          when Keys::ESC
            close_menu
            revert_query
            true
          else
            false
          end
        elsif [Keys::DOWN_ARROW, Keys::ENTER].include?(key)
          open_menu
          true
        else
          false
        end
      end

      # Recomputes the matches for the current query, opening the dropdown when
      # there are any (and preselecting the current value's row) or closing it
      # when there are none.
      # @return [void]
      def refill
        @filtered = matching(@field.text)
        if @filtered.empty?
          close_menu
        else
          @menu.lines = @filtered.map { |item| @item_label.call(item) }
          @menu.cursor = List::Cursor.new(position: @filtered.index(value) || 0)
          @overlay.open unless @overlay.open?
          anchor
        end
      end

      # Items whose label contains `query` (case-insensitive). A query still
      # equal to the current value's label — the resting state, or a fresh
      # open — is treated as "show everything", so Down opens the full list.
      # @param query [String]
      # @return [Array]
      def matching(query)
        return @items if query.empty? || query == display_for(value)

        needle = query.downcase
        @items.select { |item| @item_label.call(item).to_s.downcase.include?(needle) }
      end

      # Commits the item at the menu's `index`: closes the dropdown and adopts
      # it as {#value} (which repaints the field with its label).
      # @param index [Integer]
      # @return [void]
      def commit(index)
        item = @filtered[index]
        close_menu
        self.value = item
      end

      # @return [void]
      def open_menu = refill

      # @return [void]
      def close_menu = (@overlay.close if @overlay.open?)

      # @return [void]
      def revert_query = sync_field(display_for(value))

      # Sets the field's text without triggering a refilter — for programmatic
      # value changes and query reverts, which must not spring the dropdown.
      # @param text [String]
      # @return [void]
      def sync_field(text)
        @suppressing_filter = true
        @field.text = text
      ensure
        @suppressing_filter = false
      end

      # @param item [Object]
      # @return [String] the plain-text label for `item`, or "" for nil.
      def display_for(item) = item.nil? ? "" : @item_label.call(item).to_s

      # Sizes and positions the dropdown against the field: full combo width,
      # `min(matches, 10)` rows, below the field — flipped above when it won't
      # fit beneath, clamped (with the list scrolling) when it fits neither.
      # @return [void]
      def anchor
        desired = [@filtered.size, MAX_VISIBLE_ROWS].min
        below = screen.size.height - (rect.top + 1)
        above = rect.top
        if desired <= below
          top = rect.top + 1
          height = desired
        elsif above >= below
          height = [desired, above].min
          top = rect.top - height
        else
          height = below
          top = rect.top + 1
        end
        @overlay.size = Size.new(rect.width, height)
        @overlay.rect = Rect.new(rect.left, top, rect.width, height)
      end

      # Most matches shown before the dropdown scrolls.
      MAX_VISIBLE_ROWS = 10
    end
  end
end
