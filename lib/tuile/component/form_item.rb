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
    # == Implementation details
    # **The message row is also the gap row**, which is why the item's pitch is
    # a flat three rows and nothing ever reflows: a form that grew a row when a
    # field went invalid would push the fields below it down *while the user is
    # typing into one of them*. See `D_form_item`.
    #
    # **It measures nothing.** The rect it is handed is divided top-down —
    # caption, content, message — so there is no `rows` property here and no
    # question asked of the field. Rows are served content-first when there are
    # too few: the content never drops below one row, then the caption takes the
    # next row it can, then the message.
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
        # An app-global, like {VerticalScrollBarInk.handle_char} — the marker is a
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
          raise TypeError, "required_marker must be a String, got #{glyph.inspect}" unless glyph.is_a?(String)

          unless glyph.grapheme_clusters.size == 1
            raise ArgumentError, "required_marker must be exactly one grapheme cluster, got #{glyph.inspect}"
          end

          width = StyledString.plain(glyph).display_width
          unless width == 1
            raise ArgumentError, "required_marker must be one column wide, got #{glyph.inspect} (#{width})"
          end

          @required_marker = -glyph
        end
      end

      self.required_marker = "∙"

      # @param content [Component, nil] the field to wrap; assignable later
      #   through {#content=}.
      # @param caption [String, StyledString, nil] the text above it; omit it
      #   for a widget painting its own, such as a {Checkbox} or a {Button}.
      # @param required [Boolean] whether to paint {.required_marker} beside
      #   the caption.
      # @raise [ArgumentError] when `required` is true and there is no caption
      #   for the marker to sit beside.
      def initialize(content = nil, caption: nil, required: false)
        super()
        @content = nil
        @required = false
        @caption_label = Label.new
        @message_label = Label.new
        add_child(@caption_label) # appended: HasContent forces the content to index 0
        add_child(@message_label)
        self.caption = caption
        self.required = required
        self.content = content unless content.nil?
      end

      # @return [Boolean] whether the caption carries {.required_marker}.
      def required? = @required

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
      end

      # Sets the caption, adding or dropping the caption row as it becomes
      # non-empty or empty.
      # @param new_caption [String, StyledString, nil]
      # @return [void]
      # @raise [ArgumentError] when clearing the caption of a {#required?} item.
      def caption=(new_caption)
        new_caption = StyledString.parse(new_caption)
        if required? && new_caption.empty?
          raise ArgumentError, "a required FormItem keeps its caption: the marker has nowhere else to go"
        end

        had_row = !caption.empty?
        super
        refresh_chrome
        relayout unless had_row == !caption.empty?
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

      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        super # Component#rect=, then HasContent's layout(content)
        layout_chrome
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

      # @param content [Component]
      # @return [void]
      def layout(content) = content.rect = row_rects[1]

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

      # The rows are fixed, so a hidden child abandons its cells instead of
      # collapsing them — repaint to blank what it left behind.
      # @param child [Component]
      # @return [void]
      def handle_child_visibility_changed(child)
        super
        invalidate
      end

      # @return [Array<String>]
      def inspect_details = required? ? super + ["required"] : super

      private

      # Rebuilds both chrome strings from the current caption, marker and
      # verdict — the single writer, idempotent, so every input that can change
      # one of them just calls this.
      # @return [void]
      def refresh_chrome
        # The marker shares the message's red rather than earning a theme token
        # of its own — a required field is not yet invalid; see `D_form_item`.
        ink = Screen.instance? ? screen.theme.error_color : nil
        marker = StyledString.styled(" #{self.class.required_marker}", fg: ink)
        @caption_label.text = required? ? caption + marker : caption
        # `shown_message` orders the two channels, and hands back a plain
        # String for a field's own report — hence the parse.
        message = StyledString.parse(content.respond_to?(:shown_message) ? content.shown_message : nil)
        @message_label.text = message.empty? ? StyledString::EMPTY : message.with_fg(ink)
      end

      # @return [void]
      def relayout
        layout(content) unless content.nil?
        layout_chrome
      end

      # @return [void]
      def layout_chrome
        caption_rect, _content_rect, message_rect = row_rects
        @caption_label.rect = caption_rect
        @message_label.rect = message_rect
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
    end
  end
end
