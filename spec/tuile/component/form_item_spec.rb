# frozen_string_literal: true

module Tuile
  describe Component::FormItem do
    before { Screen.fake }
    after { Screen.close }

    let(:field) { Component::TextField.new }
    let(:item) { Component::FormItem.new(field, caption: "Username") }
    let(:required_item) { Component::FormItem.new(field, caption: "Username", required: true) }

    # Mounts an item and gives it `height` rows, 20 columns wide.
    # @param target [Component::FormItem]
    # @param height [Integer]
    # @return [Component::FormItem] `target`.
    def mount(target = item, height: 3)
      Screen.instance.content = target
      target.rect = Rect.new(0, 0, 20, height)
      target
    end

    # The mounted region, painted. Independent of which item is mounted, so an
    # example holding a local one still reads the right cells.
    # @param height [Integer]
    # @return [Array<String>] one string per row.
    def painted(height = 3)
      Screen.instance.repaint
      Screen.instance.buffer.region_text(Rect.new(0, 0, 20, height))
    end

    context "the tree" do
      it "puts the content at index 0 and its own chrome after it" do
        assert_equal [field, Component::Label, Component::Label],
                     [item.children[0], item.children[1].class, item.children[2].class]
      end

      it "keeps the chrome even with no content" do
        assert_equal 2, Component::FormItem.new.children.size
      end

      it "is focusable but never a tab stop — the field it wraps is the one stop" do
        assert item.focusable?
        refute item.tab_stop?
      end

      it "forwards focus into the field, so clicking the caption lands there" do
        mount
        Screen.instance.focused = item
        assert_equal field, Screen.instance.focused
      end
    end

    context "geometry" do
      it "gives row 0 to the caption, the last row to the message, the rest to the content" do
        mount(height: 5)
        assert_equal Rect.new(0, 0, 20, 1), item.children[1].rect
        assert_equal Rect.new(0, 1, 20, 3), field.rect
        assert_equal Rect.new(0, 4, 20, 1), item.children[2].rect
      end

      it "reserves no caption row when there is no caption" do
        bare = mount(Component::FormItem.new(field))
        assert bare.children[1].rect.empty?
        assert_equal Rect.new(0, 0, 20, 2), field.rect
        assert_equal Rect.new(0, 2, 20, 1), bare.children[2].rect
      end

      it "adds the caption row when a caption arrives, with no resize" do
        bare = mount(Component::FormItem.new(field))
        bare.caption = "Username"
        assert_equal Rect.new(0, 0, 20, 1), bare.children[1].rect
        assert_equal Rect.new(0, 1, 20, 1), field.rect
      end

      it "serves the content first when the rows run out, and the message last" do
        mount(height: 2)
        refute field.rect.empty?, "the field is the half worth keeping"
        assert item.children[2].rect.empty?
      end

      it "assigns every child a rect even when its own is empty" do
        mount
        item.rect = Rect.new(0, 0, 0, 0)
        assert(item.children.all? { _1.rect.empty? })
      end
    end

    context "the message" do
      it "mirrors the field's verdict into the last row" do
        mount
        field.error_message = "Must not be blank"
        assert_equal "Must not be blank   ", painted[2]
      end

      it "clears the row when the field goes valid again" do
        mount
        field.error_message = "Must not be blank"
        field.error_message = nil
        assert_equal " " * 20, painted[2]
      end

      it "claims the foreground, so the row always reads as an error" do
        mount
        field.error_message = StyledString.styled("nope", fg: Color::GREEN)
        assert_equal Screen.instance.theme.error_color, item.children[2].text.spans.first.style.fg
      end

      it "picks up a verdict the field was already carrying" do
        field.error_message = "stale"
        mount
        assert_equal "stale               ", painted[2]
      end

      it "unsubscribes from the outgoing occupant on a swap" do
        mount
        item.content = Component::TextField.new
        assert_empty field.on_error_message_change
        field.error_message = "ignored now"
        assert_equal " " * 20, painted[2]
      end

      it "unsubscribes when the content is cleared outright" do
        mount
        field.error_message = "Must not be blank"
        item.content = nil
        assert_empty field.on_error_message_change
        assert_equal " " * 20, painted[2]
      end

      it "leaves an app's own listener registered — the slot is a list" do
        mount
        seen = []
        field.on_error_message_change { |e| seen << e.error_message&.to_s }
        field.error_message = "Must not be blank"
        assert_equal ["Must not be blank"], seen
        assert_equal "Must not be blank   ", painted[2]
      end

      it "shows the field's own report, with no verdict written" do
        number = Component::IntegerField.new
        mount(Component::FormItem.new(number, caption: "Count"))
        Testing.get(Component::TextField, in: number).text = "-"
        assert_nil number.error_message
        assert_equal "not a whole number  ", painted[2]
      end

      it "prefers that report over a verdict, and falls back when it converts" do
        number = Component::IntegerField.new
        mount(Component::FormItem.new(number, caption: "Count"))
        number.error_message = "must be over 18"
        Testing.get(Component::TextField, in: number).text = "-"
        assert_equal "not a whole number  ", painted[2]
        Testing.get(Component::TextField, in: number).text = "-5"
        assert_equal "must be over 18     ", painted[2]
      end

      it "waits for a latched field to settle before saying anything" do
        date = Component::DateField.new
        mount(Component::FormItem.new(date, caption: "Starts"))
        Screen.instance.focused = date
        "2020-13-45".each_char { Screen.instance.send(:handle_key?, _1) }
        assert_equal " " * 20, painted[2], "every prefix is bad input; the row must not flicker through them"
        Screen.instance.focused = nil
        assert_equal "not a valid date    ", painted[2]
      end

      it "unsubscribes from both slots on a swap" do
        number = Component::IntegerField.new
        wrapper = mount(Component::FormItem.new(number, caption: "Count"))
        wrapper.content = Component::TextField.new
        assert_empty number.on_bad_input_change
        assert_empty number.on_error_message_change
      end

      it "tolerates content with no validation at all" do
        mount(Component::FormItem.new(Component::Label.new("plain"), caption: "Label"))
        assert_equal " " * 20, painted[2]
      end
    end

    context "the required marker" do
      it "rides the caption" do
        mount(required_item)
        assert_equal "Username ∙          ", painted[0]
      end

      it "is painted in the error color" do
        assert_equal Screen.instance.theme.error_color,
                     required_item.children[1].text.spans.last.style.fg
      end

      it "refuses to be set without a caption to sit beside" do
        assert_raises(ArgumentError) { Component::FormItem.new(field, required: true) }
        assert_raises(ArgumentError) { Component::FormItem.new(field).required = true }
      end

      it "refuses to let a required item lose its caption" do
        assert_raises(ArgumentError) { required_item.caption = nil }
        assert_equal "Username", required_item.caption.to_s
      end

      it "goes away with required = false" do
        required_item.required = false
        assert_equal "Username", required_item.children[1].text.to_s
      end
    end

    context ".required_marker" do
      after { Component::FormItem.required_marker = "∙" }

      it "swaps the glyph app-wide" do
        Component::FormItem.required_marker = "*"
        assert_equal "Username *", required_item.children[1].text.to_s
      end

      it "refuses a glyph that is not exactly one cluster one column wide" do
        assert_raises(TypeError) { Component::FormItem.required_marker = :star }
        assert_raises(ArgumentError) { Component::FormItem.required_marker = "**" }
        assert_raises(ArgumentError) { Component::FormItem.required_marker = "漢" }
      end
    end

    context "theme and lifecycle" do
      it "rebakes the chrome it authored when the theme changes" do
        mount(required_item)
        field.error_message = "nope"
        Screen.instance.theme = ThemeDef.default.light
        light = Screen.instance.theme.error_color
        assert_equal light, required_item.children[1].text.spans.last.style.fg
        assert_equal light, required_item.children[2].text.spans.first.style.fg
      end

      it "bakes the color on attach, for a tree assembled before there was a screen" do
        Screen.close
        item = required_item # built here, with no Screen in the process
        field.error_message = "nope"
        assert_nil item.children[1].text.spans.last.style.fg

        Screen.fake
        Screen.instance.content = item
        ink = Screen.instance.theme.error_color
        assert_equal ink, item.children[1].text.spans.last.style.fg
        assert_equal ink, item.children[2].text.spans.first.style.fg
      end
    end

    context "visibility" do
      it "takes the caption and the message with it" do
        mount
        field.error_message = "Must not be blank"
        item.visible = false
        # Blanking the cells is the parent's job, so what the item owes is to
        # paint none of them back — chrome included.
        buffer = Screen.instance.buffer
        3.times { |y| 20.times { |x| buffer.set_char(x, y, "·") } }
        assert_equal ["·" * 20] * 3, painted
      end

      it "blanks the rows a hidden field abandons, keeping the chrome" do
        mount
        field.error_message = "Must not be blank"
        field.visible = false
        rows = painted
        assert_equal "Username            ", rows[0]
        assert_equal " " * 20, rows[1]
        assert_equal "Must not be blank   ", rows[2]
      end
    end
  end
end
