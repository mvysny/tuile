# frozen_string_literal: true

module Tuile
  class Component
    # Single-select from a set of typed items, one row each. Arrows move a
    # cursor; Space, Enter or a left click selects the row under it:
    #
    #    (*) Ascending
    #    ( ) Descending    <- cursor row, highlighted across the full width
    #    ( ) Unsorted
    #   ^ the composed {List}'s one-column gutter
    #
    #   rg = Component::RadioGroup.new(items: %w[Ascending Descending Unsorted])
    #   rg.value = "Descending"                      # or seed it via the ctor
    #   rg.on_value_change = ->(order) { resort(order) }
    #   rg.value                                     # => "Descending"
    #   rg.item_label = ->(o) { o.title }            # default :to_s
    #
    # {#value} is **the selected item itself** — of whatever type {#items}
    # holds, never its label. `nil` means nothing is selected: that is the
    # initial state, and assigning it is the only way back, since Space on the
    # already-selected row is a no-op rather than a deselect.
    #
    # Composes rather than subclasses, like {ComboBox}: a {List} is its single
    # {HasContent} child, which is where the cursor, scrolling, the scrollbar
    # and per-row mouse hit-testing come from. `content` is that list, so an app
    # can tune it (`scrollbar_visibility`, `show_cursor_when_inactive`, …). Rows
    # beyond {#rect}'s height scroll; the inner list is the tab stop, not the
    # group.
    #
    # == The cursor is chrome
    # The cursor and the selection are two independent things, as in
    # {CheckboxGroup} — arrows roam without changing {#value}, so a listener
    # that resorts a pane fires once on intent instead of once per row crossed.
    # {#value=} therefore does *not* move the cursor. An app that wants it
    # parked on the selection parks it:
    #
    #   rg.content.cursor = List::Cursor.new(position: rg.items.index(rg.value))
    #
    # {#items=} is the one thing that moves it, clamping it back into range.
    #
    # == +items+ is chrome; +value+ is authoritative
    # {#items=} changes only what is *presented*. It never touches {#value} and
    # never fires {HasValue#on_value_change}, and a selected item absent from
    # {#items} renders no marked row while surviving intact — so a form saved
    # without the user editing anything changes nothing silently. Keeping the
    # two in sync is the app's job. Same contract as {ComboBox#value} and
    # {CheckboxGroup#value}.
    #
    # == Implementation details
    # Two `==`-equal items share one selection, so selecting either marks both
    # rows; two *distinct* items that merely render the same label stay
    # independent, because a row resolves to an item by index.
    #
    # Rows are `(*) `/`( ) ` literals, mirroring {Checkbox}'s convention rather
    # than importing constants from it. ASCII deliberately: `(•)` would measure
    # two columns in a terminal configured for East-Asian-Ambiguous glyphs and
    # shift every row's text, which no test would catch.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class RadioGroup < Component
      include HasContent
      include HasValue

      # @param items [Array] the items to present, one row each; also settable
      #   via {#items=}.
      # @param value [Object, nil] the initially selected item. Seeds the
      #   backing ivar directly, so no listener fires and assignment order
      #   doesn't matter to a form helper.
      def initialize(items: [], value: nil)
        super()
        @items = items.to_a
        @item_label = :to_s.to_proc
        @value = value
        @on_value_change = nil

        list = List.new
        # A List has no cursor at all by default (Cursor::None, position -1).
        list.cursor = List::Cursor.new
        list.on_item_chosen = ->(index, _line) { select_at(index) }
        self.content = list
        rebuild_rows
      end

      # @return [Array] the presented items.
      attr_reader :items

      # @return [Proc, Method] item -> row label (a `String`, {StyledString}, or
      #   anything with `#to_s`); `:to_s` by default.
      attr_reader :item_label

      # Replaces the presented rows, leaving {#value} untouched and clamping the
      # cursor back into range.
      # @param new_items [Array]
      # @raise [TypeError] unless `new_items` is an `Array`.
      # @return [void]
      def items=(new_items)
        raise TypeError, "expected Array, got #{new_items.inspect}" unless new_items.is_a?(Array)

        @items = new_items
        # Before the rebuild, so the single {List#on_cursor_changed} that
        # {List#lines=} fires reports the final row rather than a stale one.
        clamp_cursor
        rebuild_rows
      end

      # @param proc [Proc, Method] item -> row label.
      # @return [void]
      def item_label=(proc)
        @item_label = proc
        rebuild_rows
      end

      # Selects `new_value`, firing {HasValue#on_value_change} when it really
      # changed. The cursor stays where it is.
      # @param new_value [Object, nil] `nil` selects nothing; an item outside
      #   {#items} is kept but renders no marked row.
      # @return [void]
      def value=(new_value)
        # HasValue#value= no-ops on an unchanged value; this guard is what also
        # skips the row rebuild.
        return if value == new_value

        super
        rebuild_rows
      end

      # Selects the cursor row on Space. Nothing else is claimed: the composed
      # {List} — being the focused component — has already had its chance at the
      # key (its arrows, Home/End, PgUp/PgDn, ^U/^D and Enter), and whatever
      # neither of us wants bubbles on to an ancestor.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return false unless key == " "

        select_at(content.cursor.position)
        true
      end

      protected

      # Places the composed list across the whole rect ({HasContent} hook).
      # @param list [Component]
      # @return [void]
      def layout(list) = (list.rect = rect)

      private

      # Selects the item on row `index`; an index outside {#items} is ignored.
      # @param index [Integer]
      # @return [void]
      def select_at(index)
        return unless index.between?(0, @items.size - 1)

        self.value = @items[index]
      end

      # Re-renders every row from the current items, labels and selection.
      # @return [void]
      def rebuild_rows
        content.lines = @items.map do |item|
          StyledString.plain(item == value ? "(*) " : "( ) ") + label_for(item)
        end
      end

      # Pulls an over-range cursor back onto the last row (row 0 when there are
      # none). {List#lines=} leaves a stale cursor alone, which would strand it
      # off-content: no highlight, a dead Enter, and a Space that resolves to
      # `nil` and silently clears the selection.
      # @return [void]
      def clamp_cursor
        cursor = content.cursor
        # go_to_last funnels through Cursor#go's clamp(0, nil), so an empty
        # items list floors at 0 instead of going negative.
        cursor.go_to_last(@items.size) if cursor.position >= @items.size
      end

      # @param item [Object]
      # @return [StyledString, String] whichever {StyledString#+} accepts on the
      #   right — so a styled label keeps its spans and a plain one is parsed.
      def label_for(item)
        label = @item_label.call(item)
        label.is_a?(StyledString) ? label : label.to_s
      end
    end
  end
end
