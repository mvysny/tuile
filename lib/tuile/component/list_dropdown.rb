# frozen_string_literal: true

module Tuile
  class Component
    # A borderless, tinted, non-focusable floating selection list — the dropdown
    # a text input drops open, drives by forwarding movement keys, and commits a
    # pick from: a non-modal {Popup} wrapping a {List} that never takes focus, so
    # the caret stays in the driving input while the caller refills the rows,
    # moves the highlight, and reads the pick.
    #
    #   drop = Component::ListDropdown.new
    #   drop.on_item_chosen = ->(index, _line) { commit(index) } # caller commits
    #   # …then, per keystroke in the driving input's key handler:
    #   drop.lines = matches.map { |m| render(m) }  # caller filters + renders
    #   drop.rect  = Rect.new(...)                   # caller anchors + sizes it
    #   drop.open
    #   return true if drop.move(key)  # Up/Down/PgUp/PgDn/^U/^D → list scroll
    #   drop.choose if key == Keys::ENTER            # commit the highlight
    #
    # It owns only what every such dropdown shares; everything that varies stays
    # with the driver: geometry/anchoring, filtering, row rendering, the commit
    # action, and ESC/Enter handling. ESC and Enter carry driver-specific tails
    # (ESC may revert a query; Enter may commit via {#choose} *or* via a separate
    # submit path), so {#move} claims neither — the driver calls {#choose} and
    # {#close} from its own branches.
    #
    # == Theming
    # Borderless, told apart from the content beneath by a background tint —
    # {Theme#input_bg_color} by default, assigned as a live {Theme::Ref} so it
    # tracks light/dark flips with no hook. Reassign {Component#bg_color=} for a
    # different tint (a `Theme.ref(:token)` keeps the flip-tracking).
    #
    # UI-thread-confined, like every component (see {Screen}).
    class ListDropdown < Popup
      # The dropdown's {List}. Non-focusable on purpose: the driver forwards keys
      # while focus (and the caret) stay in its input, and a mouse click selects
      # an item without stealing focus — so the input never loses the cursor
      # mid-interaction.
      class Menu < List
        def focusable? = false
        def tab_stop? = false
      end

      # Cursor-movement keys forwarded to the list by {#move}: the two vertical
      # arrows, page up/down, and Ctrl+U/D half-page jumps. Deliberately excludes
      # Home/End and `j`/`k` (they belong to the driving field — caret movement
      # and typing) and Enter/ESC (they carry driver-specific tails — see the
      # class docs).
      # @return [Array<String>]
      MOVE_KEYS = [Keys::UP_ARROW, Keys::DOWN_ARROW, Keys::PAGE_UP, Keys::PAGE_DOWN,
                   Keys::CTRL_U, Keys::CTRL_D].freeze

      def initialize
        @list = Menu.new
        @list.cursor = List::Cursor.new
        @list.show_cursor_when_inactive = true # highlight the selection though focus stays in the input
        super(content: @list, modal: false)
        self.bg_color = Theme.ref(:input_bg_color)
      end

      # @param lines [Array] the rows to show; see {List#lines=}.
      # @return [void]
      def lines=(lines)
        @list.lines = lines
      end

      # @return [Array<StyledString>] the current rows.
      def lines = @list.lines

      # @param proc [Proc, Method, nil] commit callback; see {List#on_item_chosen}.
      # @return [void]
      def on_item_chosen=(proc)
        @list.on_item_chosen = proc
      end

      # @param cursor [List::Cursor] the highlight; see {List#cursor=}.
      # @return [void]
      def cursor=(cursor)
        @list.cursor = cursor
      end

      # @return [List::Cursor] the list's cursor (the current highlight).
      def cursor = @list.cursor

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
