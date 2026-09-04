# frozen_string_literal: true

module Tuile
  class Component
    # A borderless, tinted, non-focusable floating selection list — the dropdown
    # a *driver* drops open, drives by forwarding movement keys, and commits a
    # pick from: an {Overlay} wrapping a {List} that never takes focus, so
    # focus stays on the driver while the caller refills the rows, moves the
    # highlight, and reads the pick.
    #
    #   drop = Component::ListDropdown.new
    #   drop.renderer = method(:label_for)                 # caller renders
    #   drop.on_item_chosen = ->(_index, item) { commit(item) }   # caller commits
    #   # …then, from the driver's key handler:
    #   drop.items = matches                         # caller filters
    #   drop.anchor_to(rect, rows: matches.size)     # below the driver, or flipped
    #   drop.open
    #   return true if drop.move(key)  # Up/Down/PgUp/PgDn/^U/^D → list scroll
    #   drop.choose if key == Keys::ENTER            # commit the highlight
    #
    # It owns only what every such dropdown shares — *placement* included, via
    # {#anchor_to} (below a field) and {#anchor_beside} (beside a parent row, for
    # a cascading submenu). What stays with the driver: the width **policy**
    # (neither placement method measures anything itself), filtering, row
    # rendering, the commit action, and ESC/Enter handling. ESC and Enter carry driver-specific tails (ESC may
    # revert a query; Enter may commit via {#choose} *or* via a separate submit
    # path), so {#move} claims neither — the driver calls {#choose} and {#close}
    # from its own branches.
    #
    # == Theming
    # Borderless, told apart from the content beneath by a background tint —
    # {Theme#input_bg_color} by default, assigned as a live {Theme::Ref} so it
    # tracks light/dark flips with no hook. Reassign {Component#bg_color=} for a
    # different tint (a `Theme.ref(:token)` keeps the flip-tracking).
    #
    # UI-thread-confined, like every component (see {Screen}).
    class ListDropdown < Overlay
      # The dropdown's {List}. Non-focusable on purpose: the driver forwards keys
      # while focus stays on it, and a mouse click selects an item without
      # stealing focus — so a driving text input never loses its caret
      # mid-interaction.
      class Menu < List
        def focusable? = false
        def tab_stop? = false
      end

      # Cursor-movement keys forwarded to the list by {#move}: the two vertical
      # arrows, page up/down, and Ctrl+U/D half-page jumps. Deliberately excludes
      # Home/End and `j`/`k` — a jump to the first/last row is the driver's call,
      # and both drivers decline it ({ComboBox}'s field needs Home/End for the
      # caret; {Select} would spend a branch on what a second arrow press already
      # does) — and Enter/ESC, which carry driver-specific tails (see the class
      # docs).
      #
      # A driver only ever sees the keys its own children decline, so a
      # {ComboBox} never gets Ctrl+U — its field claims it to clear the query —
      # while {Select}, wrapping no editor, gets every one of these.
      # @return [Array<String>]
      MOVE_KEYS = [Keys::UP_ARROW, Keys::DOWN_ARROW, Keys::PAGE_UP, Keys::PAGE_DOWN,
                   Keys::CTRL_U, Keys::CTRL_D].freeze

      # Most rows shown before the list scrolls; {#anchor_to}'s `max_rows`
      # default.
      # @return [Integer]
      MAX_VISIBLE_ROWS = 10

      def initialize
        @list = Menu.new
        @list.cursor = List::Cursor.new
        @list.show_cursor_when_inactive = true # highlight the selection though focus stays on the driver
        super(content: @list)
        self.bg_color = Theme.ref(:input_bg_color)
      end

      # @param items [Array] the items to show, one row each; see {List#items=}.
      # @return [void]
      def items=(items)
        @list.items = items
      end

      # @return [Array] the items currently shown.
      def items = @list.items

      # @param proc [Proc, Method] item -> row; see {List#renderer}.
      # @return [void]
      def renderer=(proc)
        @list.renderer = proc
      end

      # @param proc [Proc, Method, nil] commit callback; see {List#on_item_chosen}.
      # @return [void]
      def on_item_chosen=(proc)
        @list.on_item_chosen = proc
      end

      # @param proc [Proc, Method, nil] highlight-moved callback; see
      #   {List#on_cursor_changed}. A cascading driver needs it to drop the
      #   panels that belonged to the row the highlight just left.
      # @return [void]
      def on_cursor_changed=(proc)
        @list.on_cursor_changed = proc
      end

      # @param cursor [List::Cursor] the highlight; see {List#cursor=}.
      # @return [void]
      def cursor=(cursor)
        @list.cursor = cursor
      end

      # @return [List::Cursor] the list's cursor (the current highlight).
      def cursor = @list.cursor

      # Moves the highlight to the item at `index`, scrolling it into view; see
      # {List#select}. The positional counterpart of {#move}, for a driver that
      # picked a row by something other than a key — a mnemonic letter, say.
      # @param index [Integer]
      # @return [Boolean] whether the highlight moved there.
      def select(index) = @list.select(index)

      # Sizes and places the dropdown against `anchor`: directly beneath it,
      # flipped above when `rows` won't fit below, clamped — with the list
      # scrolling — when neither side has room. Horizontally the left edges line
      # up, sliding left only far enough to keep the panel on screen.
      #
      #   drop.anchor_to(field.rect, rows: matches.size)            # field width
      #   drop.anchor_to(rect, rows: items.size, width: measured)   # own width
      #
      # Vertical flips but horizontal slides because covering the driver would
      # hide what is being chosen, while sharing its columns is the point.
      #
      # **`anchor` is the region actually occupied, and may be taller than one
      # row** — "beneath" means the row *after* it, so a multi-row driver (a
      # {Component::TextArea} carrying an autocomplete menu) is cleared entirely
      # rather than overdrawn from its second row down. A widget that paints one
      # row but may be *assigned* more height passes its face, not its rect:
      # {ComboBox} and {Select} both do, since a {Window} content slot hands them
      # the full inner height.
      #
      # @param anchor [Rect] the region the driver occupies, of any height; the
      #   dropdown never covers it.
      # @param rows [Integer] how many rows there are to show — the content
      #   count, not the height: more than fits turns the scrollbar on. `0`
      #   collapses the dropdown to an empty rect (drivers close instead).
      # @param width [Integer] the panel's width in columns, clamped to the
      #   screen. Defaults to the anchor's, which lines both edges up with a
      #   field; a driver that measured its labels passes its own. A label wider
      #   than the screen clips — {List} has no horizontal scrolling.
      # @param max_rows [Integer] rows shown before the list scrolls.
      # @return [void]
      def anchor_to(anchor, rows:, width: anchor.width, max_rows: MAX_VISIBLE_ROWS)
        desired = [rows, max_rows].min
        beneath = anchor.top + anchor.height
        below = screen.size.height - beneath
        above = anchor.top
        if desired <= below
          top = beneath
          height = desired
        elsif above >= below
          height = [desired, above].min
          top = anchor.top - height
        else
          height = below
          top = beneath
        end
        width = [width, screen.size.width].min
        self.rect = Rect.new([anchor.left, screen.size.width - width].min.clamp(0, nil), top, width, height)
        # After the geometry: the setter rebuilds the list's padded rows against
        # the width it can see, and the gutter takes a column off it.
        @list.scrollbar_visibility = rows > height ? :visible : :gone
      end

      # Sizes and places the dropdown *beside* `anchor` — the placement a
      # cascading submenu wants, where {#anchor_to} is the placement a field's
      # dropdown wants.
      #
      #   sub.anchor_beside(parent.cursor_row_rect, rows: kids.size, width: measured)
      #
      # Horizontally it sits against `anchor`'s right edge, **flipping** to its
      # left when the right has no room (and clamping to the screen when neither
      # side does). Vertically it **slides**: the panel's first row lines up with
      # the anchored row, sliding up only far enough to keep the panel on screen.
      #
      # The two axes are the mirror image of {#anchor_to}'s, for the same reason:
      # never cover the thing being chosen from. A field's dropdown must not
      # cover the field, so it flips *vertically* and shares its columns; a
      # submenu must not cover its parent panel, so it flips *horizontally* and
      # shares its rows.
      #
      # @param anchor [Rect] the row the submenu belongs to — typically the
      #   parent dropdown's {#cursor_row_rect}. Its width is the parent panel's,
      #   which is what the submenu clears.
      # @param rows [Integer] how many rows there are to show — the content
      #   count, not the height; more than fits turns the scrollbar on. `0`
      #   collapses the dropdown to an empty rect (drivers close instead).
      # @param width [Integer] the panel's width in columns, clamped to the
      #   screen. **Required, with no default:** `anchor.width` is the *parent's*
      #   width and would be meaningless here, so the caller measures (see
      #   `DECISIONS.md` `D_select` on why the width policy stays with the
      #   driver).
      # @param max_rows [Integer] rows shown before the list scrolls.
      # @return [void]
      def anchor_beside(anchor, rows:, width:, max_rows: MAX_VISIBLE_ROWS)
        height = [rows, max_rows, screen.size.height].min
        width = [width, screen.size.width].min
        right = anchor.left + anchor.width
        left = if right + width <= screen.size.width || (anchor.left - width).negative?
                 right
               else
                 anchor.left - width
               end
        left = left.clamp(0, [screen.size.width - width, 0].max)
        top = [anchor.top, screen.size.height - height].min.clamp(0, nil)
        self.rect = Rect.new(left, top, width, height)
        # After the geometry, as in {#anchor_to}: the setter rebuilds the list's
        # padded rows against the width it can see.
        @list.scrollbar_visibility = rows > height ? :visible : :gone
      end

      # The highlighted row's rect on screen — what a cascading submenu anchors
      # against, via {#anchor_beside}.
      #
      # It lives here rather than in the driver because {ListDropdown} owns the
      # list's geometry: a driver computing `top + position - scroll_top_row`
      # itself would have to reach through to the private list.
      # @return [Rect, nil] one row spanning the panel's width, or `nil` when
      #   the cursor is off-content ({List::Cursor::None}, an empty list) or its
      #   row is scrolled out of the viewport.
      def cursor_row_rect
        return nil if @list.rect.empty?
        return nil unless @list.cursor.position.between?(0, @list.items.size - 1)

        row = @list.cursor.position - @list.scroll_top_row
        return nil unless row.between?(0, @list.rect.height - 1)

        Rect.new(@list.rect.left, @list.rect.top + row, @list.rect.width, 1)
      end

      # Forwards a cursor-movement key to the list. The driver calls this from
      # its own key handler; a truthy return means "consumed — stop here", falsy
      # means "not mine — proceed with normal editing/dispatch". Only {MOVE_KEYS}
      # are claimed, and only while open.
      # @param key [String]
      # @return [Boolean] true iff the key was consumed.
      def move(key)
        return false unless open? && MOVE_KEYS.include?(key)

        @list.handle_key(key)
        true
      end

      # Commits the highlighted row by firing {List#on_item_chosen}, exactly as
      # pressing Enter on the focused list would — the driver calls this from its
      # own Enter branch.
      # @return [Boolean] true iff a row was chosen (false when the cursor is
      #   off-content).
      def choose = @list.handle_key(Keys::ENTER)
    end
  end
end
