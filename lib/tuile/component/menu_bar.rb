# frozen_string_literal: true

module Tuile
  class Component
    # A one-row strip of menu captions, each dropping open a cascade of submenus
    # that nests as deep as you build it.
    #
    #   ␣File␣␣Edit␣␣View␣          <- the strip; highlighted while focused
    #    ␣New␣␣␣␣␣␣␣␣␣              <- the open menu, measured to its widest label
    #    ␣Recent␣␣␣␣▸␣              <- a row that opens a submenu
    #    ␣Quit␣␣␣␣␣␣␣␣              (the outer gutters are {List}'s)
    #
    #   bar = Component::MenuBar.new
    #   file = bar.add_item("File")
    #   file.add_item("New") { new_document }
    #   recent = file.add_item("Recent")            # no block ⇒ a submenu holder
    #   recent.add_item("notes.txt") { open("notes.txt") }
    #   bar.add_item("Quit") { screen.close }       # a top-level leaf: a button
    #
    # LEFT / RIGHT move along the strip; Enter, Space or Down opens the
    # highlighted menu. Inside a menu: Up / Down (and PgUp/PgDn, Ctrl+U/D) move
    # the highlight, Enter or Space activates a row or opens its submenu, RIGHT
    # opens a submenu, LEFT returns to the previous menu, ESC closes one level.
    # LEFT at the first level and RIGHT on a row with no submenu step to the
    # sibling menu, as they do in every menu bar. Book ch7 has the table.
    #
    # {Item} handles are minted by {#add_item} and nest via the *same* method, so
    # depth is unlimited. There is no removal, no reordering and no dynamic
    # rebuilding: a menu is built once, at construction. See `DECISIONS.md`
    # `D-menu-bar`.
    #
    # == Sizing
    # Assign a {#rect} (typically one {Layout::Fixed}`[1]` row at the top of a
    # {Layout::Vertical}) at least {#extent}`.width` wide. A wider one leaves a
    # dead tail; a narrower one **clips**, like {Tabs}. Reassigning the rect
    # **closes** an open cascade: every panel position is derived from a segment
    # or a parent row, so after a resize they would all sit at stale columns, and
    # a resize with a menu open is rare enough that closing beats re-anchoring
    # every level.
    #
    # == Implementation details
    # Deliberately painted *unlike* {Tabs}, whose picture it would otherwise
    # share: no separator between segments, no bold, and no highlight at all
    # while unfocused — a menu bar has no persistent selection to show, and a
    # reader should not have to work out which of the two controls they are
    # looking at. Hit testing *is* {Tabs}': one private `segments` method feeds
    # both the paint and the click, so a click cannot land on a caption other
    # than the one drawn under it, and it is derived from the captions on each
    # call so a hit test is correct before the first paint.
    #
    # The open panels are overlays owned by a private {Cascade}, not children:
    # focus stays here for the whole interaction, so the strip receives every key
    # and forwards it. An open cascade swallows keys the cascade doesn't
    # recognize; a *closed* strip lets every printable bubble, so an app's
    # `s`-to-save keeps working while the bar has focus.
    #
    # A click outside an open cascade is not blocked — non-modal overlays block
    # nothing — but any click on a focusable component moves focus, and losing
    # focus closes the cascade.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class MenuBar < Component
      # One menu item: a caption, an optional click listener, and its children.
      #
      #   file = bar.add_item("File")       # minted by the bar
      #   file.add_item("New") { create }   # …and nested by the same method
      #   file.items.size                   # => 1
      #
      # An item with children is a submenu and its own listener is dead
      # ({#submenu?} decides). An item with **neither** children nor a listener is
      # legal and inert: it highlights, Enter closes the menu, nothing happens —
      # an item that looks live but does nothing is the app's error to fix, not
      # the framework's to raise on.
      #
      # Apps don't construct items; {MenuBar#add_item} and {#add_item} do.
      class Item
        # @param caption [StyledString] already coerced by the caller.
        # @param on_click [Proc, Method, nil]
        def initialize(caption, on_click)
          @caption = caption
          @on_click = on_click
          @items = []
        end

        private_class_method :new

        # @return [StyledString] the label painted on the strip or the row.
        attr_reader :caption

        # @return [Array<Item>] this item's children, in menu order. Read-only by
        #   convention, like {Component#children} — grow it through {#add_item}.
        attr_reader :items

        # @return [Proc, Method, nil] no-arg callable fired when the item is
        #   activated (Enter, Space or a left click), exactly as
        #   {Button#on_click}. Never fired on an item with children.
        attr_accessor :on_click

        # @return [Boolean] whether this item opens a submenu, i.e. has children.
        def submenu? = !@items.empty?

        # Appends a child and returns its handle.
        # @param caption [String, StyledString, nil] parsed as
        #   {StyledString.parse} parses it.
        # @yield optional `on_click` callback; same as assigning {#on_click=}.
        # @return [Item]
        def add_item(caption = nil, &on_click)
          Item.send(:new, StyledString.parse(caption), on_click).tap { @items << _1 }
        end

        # @return [String]
        def inspect = "#<#{self.class.name} #{caption.to_s.inspect}#{submenu? ? " (#{@items.size} items)" : ""}>"
      end

      def initialize
        super()
        @root = Item.send(:new, StyledString::EMPTY, nil)
        @highlighted_index = 0
        @cascade = Cascade.new
      end

      # @return [Boolean] `true` — the strip takes focus, so its keys work.
      def focusable? = true

      # @return [Boolean] `true` — one stop for the whole strip, as on {Tabs}.
      def tab_stop? = true

      # @return [Array<Item>] the top-level items, in strip order. Read-only by
      #   convention; grow it through {#add_item}.
      def items = @root.items

      # @return [Integer] which top-level item the strip highlights while
      #   focused, and which menu Enter opens. `0` until the user moves.
      attr_reader :highlighted_index

      # Appends a top-level item and returns its handle; nest submenus into it
      # with {Item#add_item}.
      # @param caption [String, StyledString, nil] parsed as
      #   {StyledString.parse} parses it.
      # @yield optional `on_click` callback, for a top-level item that acts as a
      #   button rather than opening a menu.
      # @return [Item]
      def add_item(caption = nil, &on_click)
        @root.add_item(caption, &on_click).tap { invalidate }
      end

      # The cells the strip actually paints: one row, as wide as its segments
      # need, clipped to {#rect}.
      #
      # Both the highlight and the click hit test use it, so a click on the blank
      # tail — or on a lower row, when the rect is taller than one — opens
      # nothing. It still *focuses*: {Component#handle_mouse}'s click-to-focus is
      # ungated by geometry.
      # @return [Rect]
      def extent
        return Rect.new(rect.left, rect.top, 0, 1) if rect.empty?

        Rect.new(rect.left, rect.top, [painted_width, rect.width].min, 1)
      end

      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        # Only a *changed* rect closes the menu: a layout re-assigning the same
        # rect (which {Layout::Box} does on any child mutation) must not.
        changed = rect != new_rect
        super
        @cascade.close if changed
      end

      # Closes the cascade when the strip leaves the focus chain, so tabbing (or
      # clicking) away doesn't strand an open menu.
      # @param flag [Boolean]
      # @return [void]
      def active=(flag)
        was = active?
        super
        @cascade.close if was && !active?
      end

      # Closes the cascade, so a bar removed from the tree can't strand its
      # panels on the pane — they are the {ScreenPane}'s children, not the bar's,
      # so nothing else would take them down.
      # @return [void]
      def on_detached
        super
        @cascade.close
      end

      # @return [String]
      def keyboard_hint
        return "" if items.empty?
        return "↑↓ #{screen.theme.hint("move")}  ⏎ #{screen.theme.hint("select")}" if @cascade.open?

        "←→ #{screen.theme.hint("menu")}  ⏎ #{screen.theme.hint("open")}"
      end

      # Offers the key to the open cascade first, then to the strip's own
      # LEFT/RIGHT/Enter/Space/Down.
      #
      # With a cascade open, the only keys reaching the strip are the two the
      # cascade declines — LEFT at the first level, RIGHT on a row with no
      # submenu — and both step to the sibling menu.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return true if @cascade.handle_key(key)

        if @cascade.open?
          case key
          when Keys::LEFT_ARROW then step_menu(-1)
          when Keys::RIGHT_ARROW then step_menu(1)
          else false
          end
        else
          case key
          when Keys::LEFT_ARROW then move_highlight(-1)
          when Keys::RIGHT_ARROW then move_highlight(1)
          when Keys::ENTER, " ", Keys::DOWN_ARROW then open_highlighted
          else false
          end
        end
      end

      # Opens the menu under a left click, or closes it when it is already the
      # open one; `super` runs first, so a click anywhere in {#rect} still
      # focuses.
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left

        index = index_at(event.point)
        return if index.nil?

        if @cascade.open? && index == @highlighted_index
          @cascade.close
        else
          @highlighted_index = index
          invalidate
          open_highlighted
        end
      end

      # @return [void]
      def repaint
        super
        return if rect.empty?

        draw_text(rect.left, rect.top, strip_row)
      end

      private

      # One `[item, start_column, width]` triple per top-level item, in strip
      # order, in columns relative to {#rect}`.left`. A segment is its caption
      # between two padding columns, and neighbours abut — the two blank columns
      # between captions are the segments' own padding, so a click on either
      # opens the menu it belongs to.
      # @return [Array<Array(Item, Integer, Integer)>]
      def segments
        column = 0
        items.map do |item|
          width = item.caption.display_width + 2
          [item, column, width].tap { column += width }
        end
      end

      # @return [Integer] columns the strip would paint given an unlimited rect.
      def painted_width
        _item, start, width = segments.last
        start.nil? ? 0 : start + width
      end

      # @param point [Point]
      # @return [Integer, nil] the index of the item painted at `point`; `nil`
      #   for the blank tail or a row the strip doesn't paint.
      def index_at(point)
        return nil unless extent.contains?(point)

        column = point.x - rect.left
        segments.index { |_item, start, width| column >= start && column < start + width }
      end

      # @param index [Integer]
      # @return [Rect] the segment's cells on screen — the cascade's anchor.
      def segment_rect(index)
        _item, start, width = segments[index]
        Rect.new(rect.left + start, rect.top, width, 1)
      end

      # @return [StyledString] the whole strip as one row, clipped to the rect.
      def strip_row
        row = StyledString::EMPTY
        items.each_with_index { |item, index| row += segment_text(item, index) }
        row.slice(0, rect.width)
      end

      # @param item [Item]
      # @param index [Integer]
      # @return [StyledString] the caption between its padding columns,
      #   highlighted when it is the one Enter would open *and* the strip has
      #   focus. An unfocused strip shows no highlight at all: there is no
      #   persistent selection to report.
      def segment_text(item, index)
        pad = StyledString.plain(" ")
        segment = pad + item.caption + pad
        return segment unless index == @highlighted_index && active?

        segment.with_bg(screen.theme.active_bg_color)
      end

      # Moves the highlight along the strip, clamping at both ends. Consumes the
      # key even at an end, as {Tabs} does.
      # @param delta [Integer] `+1` / `-1`.
      # @return [Boolean] `false` only when there are no items.
      def move_highlight(delta)
        return false if items.empty?

        target = (@highlighted_index + delta).clamp(0, items.size - 1)
        unless target == @highlighted_index
          @highlighted_index = target
          invalidate
        end
        true
      end

      # Steps to the sibling menu and opens it, leaving the cascade alone when
      # the highlight is already at an end — reopening the same menu would throw
      # away the submenu the user is standing in.
      # @param delta [Integer] `+1` / `-1`.
      # @return [Boolean] always `true`: an open menu swallows the key either way.
      def step_menu(delta)
        was = @highlighted_index
        move_highlight(delta)
        open_highlighted unless @highlighted_index == was
        true
      end

      # Opens the highlighted item's menu — or fires it, when a top-level item
      # has no children and is therefore a button.
      # @return [Boolean] `false` only when there are no items.
      def open_highlighted
        return false if items.empty?

        item = items[@highlighted_index]
        if item.submenu?
          @cascade.open_below(segment_rect(@highlighted_index), item)
        else
          item.on_click&.call
        end
        true
      end
    end
  end
end
