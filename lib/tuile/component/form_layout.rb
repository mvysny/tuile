# frozen_string_literal: true

module Tuile
  class Component
    # A column of {FormItem}s. Hand it a field and a caption; it builds the item
    # and stacks it below the last one.
    #
    #   form = Component::FormLayout.new
    #   form.add(username, caption: "Username", required: true)
    #   form.add(notes,    caption: "Notes", rows: 5)
    #   form.add(logging)   # a Checkbox paints its own "[x] Enable logging"
    #   form.add(save)      # a Button, so no caption row at all
    #
    #   Username ∙            ← the caption row, with the required marker
    #   [______________]      ← `rows:` content rows, 1 by default
    #   Must not be blank     ← the message row, which is also the gap
    #   Notes
    #   [              ]
    #
    # **`caption_position: :left` puts every caption in one column beside its
    # field**, the message under the field, so an item costs a row less:
    #
    #   form = Component::FormLayout.new(caption_position: :left)
    #
    #   Username ∙ [__________]
    #              Must not be blank
    #   Password   [__________]
    #              [x] Remember me   ← captionless, but indented to the column
    #
    # The column fits the widest caption, clamped to half the form's width and
    # ellipsized past it; `caption_width: 12` fixes it instead.
    #
    # **You hand it fields, it holds items.** {#add} wraps whatever you give it
    # and returns the {FormItem} it built, so the chrome is the item's from the
    # start — `add(field, caption:)` reads as though it set the *field*'s
    # caption, and does not (`D_caption_ownership`). Name that field again
    # wherever this class takes one — {#remove}, {#constrain}, {#field_for}'s
    # answer — and the item around it responds. Hide that item, never the field:
    # its caption and message go with it and the rows come back here.
    #
    # == Implementation details
    # **Every row count is the caller's.** Nothing is asked of a field: a
    # captioned item is handed `1 + rows + 1` rows, a captionless or
    # left-captioned one `rows + 1`, and {#spacing} adds rows between adjacent
    # items. The message row already doubles as the gap, so `spacing` counts
    # *extra* rows on top of it and defaults to none. `rows:` is a placement
    # constraint in this layout's {Layout#constraints}, exactly as `Fixed[n]` is
    # in a {Layout::Box}, rather than a property of the item. See `D_form_layout`.
    #
    # **The caption settings are the form's, and it writes them into every item
    # on every pass** — a ready-made item's own included — so the field column
    # lines up. The widest caption counts hidden items too, so showing one never
    # shifts the rest sideways; the only thing measured is the form's own
    # caption strings, never a field.
    #
    # **Overflow clips, and there is no scrolling.** Items are laid from the top
    # edge; the one straddling the bottom takes the rows that are left — a
    # {FormItem} serves its content first — and everything past it gets an empty
    # rect rather than a stale one (`D_empty_ancestor`).
    #
    class FormLayout < Layout
      # Placement for an item wired in through `add_child` instead of {#add}.
      # @return [Hash{Symbol => Object}]
      DEFAULT_PLACEMENT = { rows: 1 }.freeze

      # @param spacing [Integer] extra blank rows between adjacent items, on top
      #   of the message row each item already ends with; `>= 0`.
      # @param caption_position [Symbol] `:above` or `:left`, for every item.
      # @param caption_width [Integer, nil] the left caption column in cells;
      #   nil fits the widest caption, up to half the form's width.
      # @raise [ArgumentError] on a negative `spacing`, or a bad
      #   `caption_position` / `caption_width`.
      def initialize(spacing: 0, caption_position: :above, caption_width: nil)
        super()
        @spacing = validate_spacing(spacing)
        @caption_position = validate_caption_position(caption_position)
        @caption_width = validate_caption_width(caption_width)
      end

      # @return [Integer] extra blank rows between adjacent items.
      attr_reader :spacing

      # @return [Symbol] `:above` (the default) or `:left`, for every item.
      attr_reader :caption_position

      # @return [Integer, nil] the left caption column in cells, or nil for
      #   the widest caption up to half the form's width.
      attr_reader :caption_width

      # Moves every caption above its field or into a column beside it.
      # @param position [Symbol] one of {FormItem::CAPTION_POSITIONS}.
      # @raise [ArgumentError] on anything else.
      # @return [void]
      def caption_position=(position)
        position = validate_caption_position(position)
        return if @caption_position == position

        @caption_position = position
        invalidate_layout
      end

      # Fixes the left caption column, or with nil fits it to the widest caption.
      # The field still keeps {FormItem::MIN_FIELD_COLUMNS}: the caption yields.
      # @param columns [Integer, nil] `>= 0`.
      # @raise [ArgumentError] on a negative or non-Integer width.
      # @return [void]
      def caption_width=(columns)
        columns = validate_caption_width(columns)
        return if @caption_width == columns

        @caption_width = columns
        invalidate_layout
      end

      # @param rows [Integer] extra blank rows between adjacent items; `>= 0`.
      # @raise [ArgumentError] on a negative value.
      # @return [void]
      def spacing=(rows)
        rows = validate_spacing(rows)
        return if @spacing == rows

        @spacing = rows
        invalidate_layout
      end

      # Wraps `field` in a {FormItem}, adds it, and re-runs the layout.
      #
      #   item = form.add(notes, caption: "Notes", rows: 5)
      #   item.required = true   # the chrome is the item's, so tune it there
      #
      # @param field [Component] the field to wrap — or a ready-made {FormItem},
      #   which is adopted as it stands.
      # @param caption [String, StyledString, nil] the caption row's text. Omit
      #   it for a widget that paints its own face, such as a {Checkbox} or a
      #   {Button}, and the item reserves no caption row.
      # @param required [Boolean] paints {FormItem.required_marker} beside the
      #   caption.
      # @param rows [Integer] content rows for the field; `>= 1`.
      # @param at [Integer, nil] position among the existing items; appends when
      #   nil. The index is part of the contract — it is paint and Tab order.
      # @raise [TypeError] unless `field` is a {Component}.
      # @raise [ArgumentError] on a `rows` below 1, on `caption:` or `required:`
      #   passed alongside a ready-made item, or from {FormItem} when `required:`
      #   has no caption to sit beside.
      # @return [FormItem] the item, whether built here or handed in.
      def add(field, caption: nil, required: false, rows: 1, at: nil)
        validate_rows(rows)
        item = wrap(field, caption, required)
        add_child(item, at:)
        constraints[item] = { rows: }
        item
      end

      # Re-sizes an item's content rows and re-runs the layout.
      #
      #   form.constrain(notes, 8)
      #
      # @param field [Component] the field, or the item around it.
      # @param rows [Integer] content rows; `>= 1`.
      # @raise [ArgumentError] when `field` is in no item of this form, or on a
      #   `rows` below 1.
      # @return [void]
      def constrain(field, rows)
        item = item_for(field)
        validate_rows(rows)
        constraints[item] = { rows: }
      end

      # Removes the item, forgets its placement, and closes the rows it left.
      #
      # The item keeps the field, so hand the *item* back to {#add} to put the
      # row back where it was — the {Layout::Box} idiom, with `rows:` on your
      # side because the placement is gone:
      #
      #   form.remove(notes)               # out, siblings move up
      #   form.add(item, rows: 5, at: 1)   # back where it was
      #
      # @param field [Component] the field, or the item around it.
      # @raise [ArgumentError] when `field` is in no item of this form.
      # @return [void]
      def remove(field)
        super(item_for(field))
      end

      # The field under a caption — sugar, since the association is a {FormItem}
      # in the tree and an ordinary walk answers the same question.
      #
      #   form.field_for(caption: "Username").value = "admin"
      #
      # @param caption [String, StyledString] matched against {FormItem#caption}
      #   as plain text; with duplicates, the first item wins.
      # @return [Component, nil] the wrapped field, or nil when no item matches
      #   or the matching one holds nothing.
      def field_for(caption:)
        wanted = caption.to_s
        children.find { _1.caption.to_s == wanted }&.content
      end

      private

      # Stacks the items from the top edge, each {#item_height} tall and
      # {#spacing} apart, and clips at the bottom. A hidden item gives up its
      # content rows, the fused gap row below them *and* its spacing, and
      # everything under it moves up.
      #
      # Deliberately *no* `return if rect.empty?` guard: that strands the items
      # at the coordinates they last had, and the next full repaint paints them
      # there (`D_empty_ancestor`).
      # @return [void]
      def relayout
        # Before any placement, so the marks these writes put back on this
        # layout are dropped as redundant rather than re-running the pass.
        columns = item_caption_width
        children.each do |item|
          item.caption_position = caption_position
          item.caption_width = columns
        end
        collapsed = Rect.new(0, 0, 0, 0)
        top = 0
        bottom = rect.empty? ? 0 : rect.height
        children.each do |item|
          # Spacing goes between shown items: the first one has none above it.
          top += spacing if item.visible? && top.positive?
          rows = item.visible? ? [item_height(item), bottom - top].min : 0
          item.rect = rows.positive? ? Rect.new(0, top, rect.width, rows) : collapsed
          top += rows
        end
      end

      # @param item [FormItem]
      # @return [Integer] the rows it is handed: a caption row when it carries a
      #   caption above, its content rows, and the message row that doubles as the gap.
      def item_height(item)
        caption_rows = caption_position == :left || item.caption.empty? ? 0 : 1
        caption_rows + placement(item)[:rows] + 1
      end

      # @return [Integer, nil] the column every item's left caption gets — the
      #   fixed {#caption_width}, else the widest caption, hidden items
      #   included, clamped to half the width. Nil above, where no column exists.
      def item_caption_width
        return nil if caption_position == :above
        return caption_width unless caption_width.nil?

        widest = children.map { _1.marked_caption.display_width }.max || 0
        [widest, rect.width / 2].min
      end

      # @param item [FormItem]
      # @return [Hash{Symbol => Object}] the item's `rows`.
      def placement(item) = constraints[item] || DEFAULT_PLACEMENT

      # @param field [Component]
      # @param caption [String, StyledString, nil]
      # @param required [Boolean]
      # @raise [TypeError] unless `field` is a {Component}.
      # @raise [ArgumentError] when a ready-made item is handed chrome arguments.
      # @return [FormItem]
      def wrap(field, caption, required)
        raise TypeError, "expected Component, got #{field.inspect}" unless field.is_a?(Component)
        return FormItem.new(field, caption:, required:) unless field.is_a?(FormItem)

        unless caption.nil? && !required
          raise ArgumentError, "#{field} is already a FormItem: it carries its own caption and marker"
        end

        field
      end

      # @param field [Component] a field, or an item of this form.
      # @raise [ArgumentError] when neither.
      # @return [FormItem]
      def item_for(field)
        return field if children.any? { _1.equal?(field) }

        item = children.find { _1.content.equal?(field) }
        raise ArgumentError, "#{field} is in no item of #{self}" if item.nil?

        item
      end

      # @param rows [Integer]
      # @raise [ArgumentError] unless `rows` is a non-negative Integer.
      # @return [Integer] `rows`.
      def validate_spacing(rows)
        return rows if rows.is_a?(Integer) && !rows.negative?

        raise ArgumentError, "spacing expects a non-negative Integer, got #{rows.inspect}"
      end

      # @param position [Symbol]
      # @raise [ArgumentError] unless one of {FormItem::CAPTION_POSITIONS}.
      # @return [Symbol] `position`.
      def validate_caption_position(position)
        return position if FormItem::CAPTION_POSITIONS.include?(position)

        raise ArgumentError, "caption_position expects one of #{FormItem::CAPTION_POSITIONS.inspect}, " \
                             "got #{position.inspect}"
      end

      # @param columns [Integer, nil]
      # @raise [ArgumentError] unless nil or a non-negative Integer.
      # @return [Integer, nil] `columns`.
      def validate_caption_width(columns)
        return columns if columns.nil? || (columns.is_a?(Integer) && !columns.negative?)

        raise ArgumentError, "caption_width expects nil or a non-negative Integer, got #{columns.inspect}"
      end

      # @param rows [Integer]
      # @raise [ArgumentError] unless `rows` is a positive Integer.
      # @return [void]
      def validate_rows(rows)
        return if rows.is_a?(Integer) && rows.positive?

        raise ArgumentError, "rows expects a positive Integer, got #{rows.inspect} — " \
                             "hide an item with visible = false rather than starving it"
      end
    end
  end
end
