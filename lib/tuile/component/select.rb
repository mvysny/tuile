# frozen_string_literal: true

module Tuile
  class Component
    # A closed-choice field on one row: the selected item's label plus a `▾`
    # affordance, dropping open a {ListDropdown} of the options. Enter, Space or
    # Down opens it; the arrows (and PgUp/PgDn) move the highlight; Enter or
    # Space commits; ESC dismisses without committing.
    #
    #   warn                ▾     <- the face: one row, on a field well
    #    debug                    <- the dropdown, measured to the widest label
    #    info                        (the one-column gutters are {List}'s)
    #    warn                     <- highlighted: the value's row, on open
    #    error
    #
    #   sel = Component::Select.new(items: LogLevel.all)
    #   sel.item_label = ->(l) { l.name }          # item -> shown label; default :to_s
    #   sel.on_value_change { |e| relog(e.value) }   # fires on commit, with the item
    #   sel.value = LogLevel::WARN                 # selects it; the face shows its label
    #
    # Use it for an **enum** — labels the developer authored, a closed set known
    # when the code is written: log level, sort order, line endings, Yes/No/Ask.
    # For items the app supplies at runtime with labels you don't control
    # (countries, users, branches) reach for {ComboBox} instead, where filtering
    # is the navigation. Item count is a symptom, not the criterion; book ch7 has
    # the widget-choice table.
    #
    # {#value} is the selected *item*, of whatever type {#items} holds, never its
    # label; `nil` — a blank face — is the initial state and stays legal, so an
    # optional enum field needs no placeholder. As on {ComboBox}, {#items=} is
    # chrome: it never touches {#value}, never fires {HasValue#on_value_change},
    # and a value absent from {#items} survives intact while rendering nothing
    # selected. Keeping the two in sync is the app's job.
    #
    # == It claims no printable key but Space
    # Enter, Space, ESC, {ListDropdown::MOVE_KEYS} and the mouse. *Every other*
    # printable key bubbles past it (key-dispatch rung 3), so a form's `s`-to-save
    # and a layout's `1`/`2`/`3` pane jumps keep working while a Select has focus
    # — the one capability no {ComboBox} configuration can offer, since a text
    # field eats printables unconditionally. Space is the single exception, and it
    # forecloses nothing: every activatable widget in the gem already claims it.
    # Home/End are declined too, so they stay available app-wide.
    #
    # There is no type-ahead: a hidden prefix buffer *is* the ComboBox query with
    # the feedback removed (`design/decisions.md` `D_select`). Which is also why labels
    # need no prefix-disambiguation.
    #
    # == Implementation details
    # A leaf widget: it paints its own row (the face is *derived* from {#value}
    # each paint, never a synced copy) and owns the dropdown as an overlay, which
    # is not a child — like {ComboBox}'s. The well is read from
    # {Screen#theme} at paint time, so it tracks a theme flip with no hook.
    #
    # The dropdown is at least as wide as the face and grows to fit the widest
    # label, so the labels are never the thing that ellipsizes. It is not opened
    # at all when {#items} is empty: an item-less Select is a programming bug, and
    # an empty tinted panel reads as a broken list rather than as "nothing to
    # pick". Enter/Space/Down are claimed either way.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class Select < Component
      include HasValue

      # @param items [Array] the options (any type); also settable via {#items=}.
      # @param value [Object, nil] the initially selected item. Seeds the backing
      #   ivar directly, so no listener fires and assignment order doesn't matter
      #   to a form helper.
      def initialize(items: [], value: nil)
        super()
        @items = items.to_a
        @item_label = :to_s.to_proc
        @value = value
        @overlay = ListDropdown.new
        # Outside-click dismissal spans the owner chain, so a click on this
        # select's dropdown must not dismiss a dialog the select sits in.
        @overlay.owner = self
        @overlay.renderer = ->(item, _text_width) { label_for(item) }
        @overlay.list.on_item_chosen { |e| commit(e.item) }
        # A Select has no caret, so the focus shade is its only indicator: an app
        # flattening it with a plain bg_color is choosing that, and can keep the
        # pair with `bg_color = { normal: …, active: … }`.
        bg.default_color = ComponentBackground::INPUT_WELL
      end

      # @return [Array] the options.
      attr_reader :items

      # @return [Proc, Method] item -> shown label (a `String` or
      #   {StyledString}); `:to_s` by default. Never called with `nil` — an
      #   unselected Select renders a blank face.
      attr_reader :item_label

      def tab_stop? = true

      # Replaces the options, leaving {#value} untouched. An open dropdown is
      # rebuilt (and re-measured) around them, or closed when none are left.
      # @param new_items [Array]
      # @raise [TypeError] unless `new_items` is an `Array`.
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
        refill if @overlay.open?
        invalidate
      end

      # Closes the dropdown when the Select leaves the focus chain, so tabbing
      # away doesn't strand an open menu. Safe against re-entrancy: focus never
      # sits inside the (non-focusable) {ListDropdown}, so closing it repairs no
      # focus.
      # @param flag [Boolean]
      # @return [void]
      def active=(flag)
        was = active?
        super
        close_menu if was && !active?
      end

      # Opens the dropdown on Enter, Space or Down; while it is open, forwards
      # {ListDropdown::MOVE_KEYS} to it, commits the highlight on Enter or Space,
      # and dismisses on ESC. Everything else — every other printable included —
      # is left unhandled so it bubbles to an ancestor.
      # @param key [String]
      # @return [Boolean]
      def handle_key?(key)
        if @overlay.open?
          return true if @overlay.move(key)

          case key
          when Keys::ENTER, " " then @overlay.choose
          when Keys::ESC then close_menu
          else return false
          end
          true
        elsif [Keys::ENTER, " ", Keys::DOWN_ARROW].include?(key)
          open_menu
          true
        else
          false
        end
      end

      # The one row this Select paints — the full width, at the top of {#rect}.
      # A single-slot container ({Component::Window}, {Component::Popup}) hands
      # its content the whole inner rect, so a Select is routinely assigned more
      # height than it uses; {#repaint} clears that tail, a press in it never reaches
      # {#handle_mouse_down?}, and the dropdown hangs under this rather than under the
      # unused space.
      # @return [Size]
      def extent = Size.new(rect.width, 1)

      # Toggles the dropdown on a left press anywhere in {#extent} — a field's
      # affordance is its whole row, as the well advertises.
      # @param event [Mouse::DownEvent]
      # @return [Boolean]
      def handle_mouse_down?(event)
        return false unless event.button == :left

        @overlay.open? ? close_menu : open_menu
        true
      end

      # @param canvas [Canvas] see {Component#repaint}.
      # @return [void]
      def repaint(canvas)
        super
        return if rect.empty?

        canvas.set_text(0, 0, face_row)
      end

      private

      # The painted row: the value's label padded across all but the last column,
      # then the `▾`. The well underneath is {ComponentBackground::INPUT_WELL}, applied by
      # {Canvas#set_text} — so a label span carrying its own background keeps
      # it, where the old override-all fill flattened it.
      # @return [StyledString]
      def face_row
        width = [rect.width - 1, 0].max
        label = label_for(value).ellipsize(width)
        label + StyledString.plain("#{" " * (width - label.display_width)}▾")
      end

      # Rebuilds the dropdown's rows, highlight and geometry, opening it if
      # needed; closes it instead when there is nothing to show.
      # @return [void]
      def refill
        if @items.empty?
          close_menu
          return
        end

        @overlay.items = @items
        @overlay.cursor = List::Cursor.new(position: @items.index(value) || 0)
        anchor
      end

      # @return [void]
      def open_menu = refill

      # @return [void]
      def close_menu = (@overlay.close if @overlay.open?)

      # Adopts the chosen item as {#value} and closes the dropdown.
      # @param item [Object]
      # @return [void]
      def commit(item)
        close_menu
        self.value = item
      end

      # @return [void]
      def anchor = @overlay.anchor_to(self, width: method(:menu_width))

      # The dropdown's width: the widest label plus {List}'s two row gutters, plus
      # the scrollbar column when the rows can't all be shown at once — but never
      # narrower than the Select itself, so both edges line up with the face and
      # the panel reads as belonging to it. Only a label that needs more pushes it
      # wider.
      #
      # A dropdown the screen clamps shorter than
      # {ListDropdown::MAX_VISIBLE_ROWS} scrolls without having bought that
      # column, ellipsizing its labels one early — the {ComboBox} trade, in the
      # one case measuring can't predict the height.
      # @return [Integer]
      def menu_width
        widest = @items.map { |item| label_for(item).display_width }.max || 0
        measured = widest + 2 + (@items.size > ListDropdown::MAX_VISIBLE_ROWS ? 1 : 0)
        [measured, rect.width].max
      end

      # @param item [Object]
      # @return [StyledString] `item`'s label, or empty for `nil` — so {#value}
      #   being unset never reaches an {#item_label} that assumes an item.
      def label_for(item)
        return StyledString::EMPTY if item.nil?

        label = @item_label.call(item)
        label.is_a?(StyledString) ? label : StyledString.parse(label.to_s)
      end
    end
  end
end
