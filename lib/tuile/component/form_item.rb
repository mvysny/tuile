# frozen_string_literal: true

module Tuile
  class Component
    # One row of a form: a {#caption} above a field, and whatever the field has
    # to say against itself below it.
    #
    #   item = Component::FormItem.new(username, caption: "Username", required: true)
    #   username.error_message = "Must not be blank"
    #
    #   Username ∙            ← the caption, with the required marker
    #   [________________]    ← the content, whatever you wrapped
    #   Must not be blank     ← the message, here the verdict just written
    #
    # Wrap a field and drop the item wherever a component goes — a
    # {Layout::Vertical} stacking items is already a form:
    #
    #   column.add(Component::FormItem.new(notes, caption: "Notes"), Fixed[7])
    #
    # The chrome is the item's, the face is the field's: a {Checkbox} or a
    # {Button} paints its own text and takes no caption here, so the item is
    # built without one and simply reserves no caption row.
    #
    # **Hide the item, never the field** — `item.visible = false` takes the
    # caption and the message with it, while `field.visible = false` blanks the
    # field's rows and leaves its caption stranded above them.
    #
    # **`caption_position: :left` puts the caption beside the field**, and the
    # message under the field rather than under the caption — one row less:
    #
    #   Component::FormItem.new(username, caption: "Username", caption_position: :left)
    #
    #   Username [__________]
    #            Must not be blank
    #
    # The caption column fits the caption unless {#caption_width} fixes it;
    # inside a {FormLayout} both are the form's, written on every pass, so the
    # column lines up across its items.
    #
    # == Implementation details
    # **The message row is also the gap row**, which is why the item's pitch is
    # a flat three rows and nothing ever reflows: a form that grew a row when a
    # field went invalid would push the fields below it down *while the user is
    # typing into one of them*. See `D_form_item`.
    #
    # **It measures nothing of the field.** The rect it is handed is divided
    # top-down — caption, content, message — so there is no `rows` property
    # here and no question asked of the field. Rows are served content-first
    # when there are too few: the content never drops below one row, then the
    # caption takes the next row it can, then the message. Columns go the same
    # way: a left caption yields until the field keeps {MIN_FIELD_COLUMNS}, then
    # the gap goes, and the field is never hidden.
    #
    # **A caption too wide for its cells is ellipsized, and the required marker
    # survives the cut** (`Userna… ∙`).
    #
    # **The message comes from two channels and the item orders neither.** A
    # validator's verdict ({HasValidation#error_message}) and the field's own
    # report of input its value cannot represent ({HasBadInput#bad_input?}) both
    # land in this row; the item registers on both notices and paints
    # {HasValidation#shown_message}, which is where the precedence lives — bad
    # input wins, and a latched field says nothing until it settles
    # (`D_bad_input`). So the row can fill while `error_message` is still `nil`.
    #
    # **The message is claimed ink.** It is painted in {Theme#error_color}
    # whatever colors the {StyledString} carried, so the row always reads as an
    # error — the matching half of the red well the field paints for itself
    # (`D_has_validation`).
    #
    # Both that message and the required marker are {StyledString}s this item
    # authors, so they bake their colors and are rebuilt from
    # {Component#handle_theme_changed} — and from {Component#handle_attached},
    # for a tree assembled before there was a {Screen} to read a theme from.
    class FormItem < Component
      include Component::HasContent
      include Component::HasCaption

      class << self
        # The glyph marking a {#required?} item, `∙` (U+2219 BULLET OPERATOR)
        # by default:
        #
        #   Tuile::Component::FormItem.required_marker = "*"
        #
        # An app-global, like {VerticalScrollBar.handle_char} — the marker is a
        # house style, not a per-item decision.
        #
        # The default is deliberately not one of `•`, `●` or `·`: those are
        # East-Asian *Ambiguous* and would measure two columns under the other
        # policy, enlarging the inventory that keeps `D_ambiguous_width`'s bet
        # cheap to reverse. `∙` and `◦` measure one under both.
        # @return [String]
        attr_reader :required_marker

        # @param glyph [String] one grapheme cluster, one column wide.
        # @return [String] frozen.
        # @raise [TypeError] when `glyph` is not a String.
        # @raise [ArgumentError] when it is not exactly one cluster one column wide.
        def required_marker=(glyph)
          @required_marker = StyledString.validate_glyph(glyph, :required_marker)
        end
      end

      self.required_marker = "∙"

      # Columns a left caption leaves the field before it yields any of its own.
      # @return [Integer]
      MIN_FIELD_COLUMNS = 5

      # @return [Array<Symbol>] what {#caption_position=} accepts.
      CAPTION_POSITIONS = %i[above left].freeze

      # @param content [Component, nil] the field to wrap; assignable later
      #   through {#content=}.
      # @param caption [String, StyledString, nil] the text above it; omit it
      #   for a widget painting its own, such as a {Checkbox} or a {Button}.
      # @param required [Boolean] whether to paint {.required_marker} beside
      #   the caption. Paint only: the check is a {Binder::Binding#required},
      #   said to the binder separately.
      # @param caption_position [Symbol] `:above` or `:left`; see {#caption_position=}.
      # @param caption_width [Integer, nil] see {#caption_width=}.
      # @raise [ArgumentError] when `required` is true and there is no caption
      #   for the marker to sit beside, or on a bad `caption_position` / `caption_width`.
      def initialize(content = nil, caption: nil, required: false, caption_position: :above, caption_width: nil)
        super()
        @content = nil
        @required = false
        @caption_position = :above
        @caption_width = nil
        @caption_label = Label.new
        @message_label = Label.new
        add_child(@caption_label) # appended: HasContent forces the content to index 0
        add_child(@message_label)
        self.caption = caption
        self.required = required
        self.caption_position = caption_position
        self.caption_width = caption_width
        self.content = content unless content.nil?
      end

      # @return [Boolean] whether the caption carries {.required_marker}.
      def required? = @required

      # @return [Symbol] `:above` (the default) or `:left`.
      attr_reader :caption_position

      # Puts the caption above the field, or beside it with the message under
      # the field. Inside a {FormLayout} this is the form's to write.
      # @param position [Symbol] one of {CAPTION_POSITIONS}.
      # @raise [ArgumentError] on anything else.
      # @return [void]
      def caption_position=(position)
        unless CAPTION_POSITIONS.include?(position)
          raise ArgumentError, "caption_position expects one of #{CAPTION_POSITIONS.inspect}, got #{position.inspect}"
        end
        return if @caption_position == position

        @caption_position = position
        invalidate_geometry
      end

      # @return [Integer, nil] the left caption's column, in cells; nil fits
      #   the caption, marker included. Ignored while {#caption_position} is
      #   `:above`.
      attr_reader :caption_width

      # Fixes the left caption's column, so items stacked in a {Layout::Vertical}
      # can line up. Inside a {FormLayout} this is the form's to write.
      #
      #   FormItem.new(city, caption: "City", caption_position: :left, caption_width: 12)
      #
      # One gap column always follows the caption, outside this width.
      # @param columns [Integer, nil] `>= 0`, or nil to fit the caption.
      # @raise [ArgumentError] on a negative or non-Integer width.
      # @return [void]
      def caption_width=(columns)
        unless columns.nil? || (columns.is_a?(Integer) && !columns.negative?)
          raise ArgumentError, "caption_width expects nil or a non-negative Integer, got #{columns.inspect}"
        end
        return if @caption_width == columns

        @caption_width = columns
        invalidate_geometry
      end

      # The caption as painted, {.required_marker} included — what a left
      # caption column is measured against.
      # @return [StyledString]
      def marked_caption = required? ? caption + marker : caption

      # Paints {.required_marker} beside the caption. The field never learns it
      # is required — nothing here validates, and this is not a rule.
      # @param flag [Boolean]
      # @return [void]
      # @raise [ArgumentError] when true and {#caption} is empty — the marker
      #   rides the caption, so without one it has nowhere to go.
      def required=(flag)
        flag = flag ? true : false
        return if @required == flag
        raise ArgumentError, "a required FormItem needs a caption for the marker" if flag && caption.empty?

        @required = flag
        refresh_chrome
        invalidate_geometry
      end

      # Sets the caption, adding or dropping the caption row as it becomes
      # non-empty or empty, and re-running the parent's pass: a {FormLayout}
      # sizes the item, and its caption column, from it.
      # @param new_caption [String, StyledString, nil]
      # @return [void]
      # @raise [ArgumentError] when clearing the caption of a {#required?} item.
      def caption=(new_caption)
        new_caption = StyledString.parse(new_caption)
        if required? && new_caption.empty?
          raise ArgumentError, "a required FormItem keeps its caption: the marker has nowhere else to go"
        end
        return if caption == new_caption

        super
        refresh_chrome
        invalidate_geometry
      end

      # Mounts the field, moving the message subscriptions onto it: the outgoing
      # occupant is unsubscribed in the same call, which is the one choke point
      # {HasContent} gives for it.
      #
      # A content component without {HasValidation} is fine — the message row
      # then simply stays empty — and one that cannot hold bad input skips that
      # slot.
      # @param new_content [Component, nil]
      # @return [void]
      def content=(new_content)
        return if content == new_content

        old = content
        super
        # Both channels paint this row, and either can move without the other.
        old.on_error_message_change.remove(method(:refresh_chrome)) if old.respond_to?(:on_error_message_change)
        old.on_bad_input_change.remove(method(:refresh_chrome)) if old.respond_to?(:on_bad_input_change)
        content.on_error_message_change << method(:refresh_chrome) if content.respond_to?(:on_error_message_change)
        content.on_bad_input_change << method(:refresh_chrome) if content.respond_to?(:on_bad_input_change)
        refresh_chrome
      end

      # @return [Boolean] true, so clicking the caption forwards focus into the
      #   field through {HasContent#handle_focus}. Never a {Component#tab_stop?}:
      #   the field it wraps is the one stop.
      def focusable? = true

      # Asks for the whole item, so a field scrolled into view brings its
      # caption and message along — then for `rect` itself, which wins when the
      # item is taller than the viewport (a caret row over the caption).
      # @param rect [Rect] in this component's coordinates.
      # @return [void]
      def scroll_to_visible(rect = local_extent_rect)
        super(local_rect)
        super
      end

      protected

      # Divides the rect into caption, content and message — stacked, or with
      # the caption in a column beside the other two.
      # @return [void]
      def relayout
        caption_rect, content_rect, message_rect = caption_position == :left ? left_rects : row_rects
        content&.rect = content_rect
        @caption_label.rect = caption_rect
        @message_label.rect = message_rect
        # The cut depends on the cells the caption was just handed.
        @caption_columns = caption_rect.width
        refresh_chrome
      end

      # @return [void]
      def handle_theme_changed
        super
        refresh_chrome
      end

      # @return [void]
      def handle_attached
        super
        refresh_chrome
      end

      # @return [Array<String>]
      def inspect_details = required? ? super + ["required"] : super

      private

      # Rebuilds both chrome strings from the current caption, marker and
      # verdict — the single writer, idempotent, so every input that can change
      # one of them just calls this.
      # @return [void]
      def refresh_chrome
        @caption_label.text = fitted_caption
        # `shown_message` orders the two channels, and hands back a plain
        # String for a field's own report — hence the parse.
        message = StyledString.parse(content.respond_to?(:shown_message) ? content.shown_message : nil)
        @message_label.text = message.empty? ? StyledString::EMPTY : message.with_fg(error_ink)
      end

      # @return [StyledString] {#marked_caption}, ellipsized to the columns the
      #   last pass handed the caption, keeping the marker whole.
      def fitted_caption
        columns = @caption_columns
        full = marked_caption
        return full if columns.nil? || full.display_width <= columns
        return full.ellipsize(columns) unless required? && columns > marker.display_width

        caption.ellipsize(columns - marker.display_width) + marker
      end

      # @return [StyledString] the required marker with its leading space.
      def marker
        # The marker shares the message's red rather than earning a theme token
        # of its own — a required field is not yet invalid; see `D_form_item`.
        StyledString.styled(" #{self.class.required_marker}", fg: error_ink)
      end

      # @return [Color, nil]
      def error_ink = Screen.instance? ? screen.theme.error_color : nil

      # Marks both passes that depend on the caption's shape: this item's, and
      # the parent's — a {FormLayout} sizes the item and its caption column from
      # it, and re-imposes its own position and width. Inside the form's own
      # pass the second mark is dropped, as it is written before any placement.
      # @return [void]
      def invalidate_geometry
        invalidate_layout
        parent&.invalidate_layout
      end

      # Divides {Component#rect} top-down. A part with no row left gets a rect
      # of zero height — empty, so the {Label} in it paints nothing — rather
      # than a stale one (`D_empty_ancestor`).
      # @return [Array(Rect, Rect, Rect)] the caption, content and message rects.
      def row_rects
        height = rect.height
        caption_rows = caption.empty? || height < 2 ? 0 : 1
        message_rows = height - caption_rows < 2 ? 0 : 1
        content_rows = height - caption_rows - message_rows
        [row_rect(0, caption_rows),
         row_rect(caption_rows, content_rows),
         row_rect(caption_rows + content_rows, message_rows)]
      end

      # @param top [Integer]
      # @param rows [Integer]
      # @return [Rect] the full width, `rows` tall.
      def row_rect(top, rows) = Rect.new(0, top, rect.width, rows)

      # Divides {Component#rect} into a caption column on the first row, a gap
      # column, and the content over the message beside them. A captionless
      # item keeps the indent and paints nothing in it.
      # @return [Array(Rect, Rect, Rect)] the caption, content and message rects.
      def left_rects
        width = rect.width
        height = rect.height
        requested = caption_width || marked_caption.display_width
        columns = requested.clamp(0, [width - 1 - MIN_FIELD_COLUMNS, 0].max)
        field_left = columns.positive? ? columns + 1 : 0
        message_rows = height < 2 ? 0 : 1
        content_rows = height - message_rows
        [Rect.new(0, 0, columns, [height, 1].min),
         Rect.new(field_left, 0, width - field_left, content_rows),
         Rect.new(field_left, content_rows, width - field_left, message_rows)]
      end
    end
  end
end
