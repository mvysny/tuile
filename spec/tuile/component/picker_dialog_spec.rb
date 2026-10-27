# frozen_string_literal: true

module Tuile
  describe Component::PickerDialog do
    before { Screen.fake }
    after { Screen.close }

    it "is a Dialog" do
      picker = Component::PickerDialog.new("foo", [%w[a all]]) {}
      assert picker.is_a?(Component::Dialog)
    end

    it "renders option rows into its inner list" do
      picker = Component::PickerDialog.new("foo", [%w[a all]]) {}
      assert picker.content.is_a?(Component::List)
      assert_equal Component::PickerDialog::Option.new("a", StyledString.plain("all")),
                   picker.content.items.first
      picker.open(Component::Overlay::At[Rect.new(0, 0, 20, 3)])
      assert_equal "a all", Testing.paint(picker.content).text.first.strip
    end

    # The picker recommends no ink of its own: a plain caption inherits the
    # terminal's foreground, and the app colors one by handing in a
    # StyledString (or the ANSI String Theme#fg returns).
    describe "caption styling" do
      # A row is `" <key> <caption>"`: List's one-column gutter, the key, a
      # separator, then the caption.
      key_column = 1
      caption_column = 3

      # @return [Tuile::Buffer::Cell] the cell `column` cells into row `row`.
      def paint(options, column:, row: 0)
        picker = Component::PickerDialog.new("foo", options) {}
        picker.open(Component::Overlay::At[Rect.new(0, 0, 20, 4)])
        Testing.paint(picker.content).cell(column, row)
      end

      it "leaves a String caption in the terminal's own foreground" do
        assert_equal "a", paint([%w[a all]], column: caption_column).grapheme
        assert_nil paint([%w[a all]], column: caption_column).style.fg
      end

      it "keeps a StyledString caption's own color, per option" do
        options = [["a", StyledString.styled("all", fg: Color::GREEN)],
                   ["b", StyledString.plain("bare")]]
        assert_equal Color::GREEN, paint(options, column: caption_column).style.fg
        assert_nil paint(options, column: caption_column, row: 1).style.fg
        # The key stays unstyled either way — only the caption is the app's.
        assert_nil paint(options, column: key_column).style.fg
      end

      it "parses an ANSI-coded String caption, as Theme#fg hands back" do
        theme = Theme::DARK.with(custom: { hint: Color::GREEN })
        assert_equal Color::GREEN, paint([["a", theme.fg(:hint, "all")]], column: caption_column).style.fg
      end
    end

    describe "disabled options" do
      options = [["r", "Resize", { disabled: "VM running" }], %w[g Grow]]

      def paint(options)
        picker = Component::PickerDialog.new("foo", options) {}
        picker.open(Component::Overlay::At[Rect.new(0, 0, 30, 4)])
        Testing.paint(picker.content)
      end

      it "paints the whole row in disabled_color, its reason after the caption" do
        painted = paint(options)
        assert_equal "r Resize (VM running)", painted.text.first.strip
        assert_equal Theme::DARK.disabled_color, painted.cell(1, 0).style.fg
        assert_equal Theme::DARK.disabled_color, painted.cell(20, 0).style.fg
        assert_nil painted.cell(1, 1).style.fg
      end

      it "replaces an app-colored caption's ink" do
        painted = paint([["r", StyledString.styled("Resize", fg: Color::RED), { disabled: "VM running" }]])
        assert_equal Theme::DARK.disabled_color, painted.cell(3, 0).style.fg
      end

      it "follows a theme change" do
        picker = Component::PickerDialog.new("foo", options) {}
        picker.open(Component::Overlay::At[Rect.new(0, 0, 30, 4)])
        Testing.paint(picker.content) # fills the List's row cache under DARK
        Screen.instance.theme = Theme::LIGHT
        Testing.loop
        assert_equal Theme::LIGHT.disabled_color, Testing.paint(picker.content).cell(1, 0).style.fg
      end

      it "refuses a disabled option without a reason" do
        [true, "", :running].each do |reason|
          assert_raises(ArgumentError) { Component::PickerDialog.new("foo", [["r", "Resize", { disabled: reason }]]) {} }
        end
      end

      it "refuses an unknown option key" do
        assert_raises(ArgumentError) { Component::PickerDialog.new("foo", [["r", "Resize", { hidden: true }]]) {} }
      end

      def press(key) = Screen.instance.send(:handle_key?, key)

      it "moves the cursor onto it on its key, firing nothing and staying open" do
        picker = Component::PickerDialog.new("foo", [%w[g Grow], *options]) { raise "never" }.open
        list = picker.content
        assert_equal 0, list.cursor.position
        assert press("r")
        assert_equal 1, list.cursor.position
        assert picker.open?
      end

      it "fires nothing on Enter on its row" do
        picker = Component::PickerDialog.new("foo", options) { raise "should not be called" }.open
        press(Keys::ENTER)
        assert picker.open?
      end

      it "fires nothing on a click on its row" do
        picker = Component::PickerDialog.new("foo", options) { raise "should not be called" }.open
        row = picker.content.absolute_rect
        Screen.instance.click(row.left + 1, row.top)
        assert picker.open?
      end

      it "still picks an enabled option beside it" do
        selected = nil
        Component::PickerDialog.new("foo", options) { selected = _1 }.open
        press("g")
        assert_equal "g", selected
      end
    end

    describe "#open" do
      it "opens a subclass built from its own constructor arguments" do
        sort_picker = Class.new(Component::PickerDialog) do
          def initialize(columns, &) = super("Sort by", columns.map { [_1[0], _1] }, &)
        end
        selected = nil
        picker = sort_picker.new(%w[name size]) { selected = _1 }.open
        press("s")
        assert_equal "s", selected
        assert !picker.open?
      end

      it "reopens after closing" do
        picker = Component::PickerDialog.new("foo", [%w[a all]]) {}
        picker.open.close
        assert picker.open.open?
      end

      # Drive through the real dispatcher (Screen#handle_key?): opening the
      # dialog focuses the inner List, and keys reach the picker by capture +
      # bubble, exactly as in a running app.
      def press(key) = Screen.instance.send(:handle_key?, key)

      it "doesn't call block when closed via q" do
        picker = Component::PickerDialog.new("foo", [%w[a all]]) { raise "should not be called" }.open
        press("q")
        assert !picker.open?
      end

      it "selects first option on enter" do
        selected = nil
        picker = Component::PickerDialog.new("foo", [%w[a all]]) { selected = _1 }.open
        press(Keys::ENTER)
        assert_equal "a", selected
        assert !picker.open?
      end

      it "selects correct option when its key is pressed" do
        selected = nil
        picker = Component::PickerDialog.new("foo", [%w[a all]]) { selected = _1 }.open
        press("a")
        assert_equal "a", selected
        assert !picker.open?
      end

      it "does nothing if an unlisted key is pressed" do
        selected = nil
        picker = Component::PickerDialog.new("foo", [%w[a all]]) { selected = _1 }.open
        press("b")
        assert_nil selected
        assert picker.open?
      end
    end
  end
end
