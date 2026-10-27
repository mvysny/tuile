# frozen_string_literal: true

module Tuile
  describe BorderDrawerInt do
    before { Screen.fake }
    after { Screen.close }

    let(:drawer) { BorderDrawerInt.new }

    # @return [Buffer] the box painted at `size`.
    def paint(size, caption: StyledString.plain("Log"), fg: nil)
      buffer = Buffer.new(size)
      drawer.paint(Canvas.new(buffer), size, caption:, fg:)
      buffer
    end

    describe "#content_rect" do
      it "insets the box by one on every side" do
        assert_equal Rect.new(1, 1, 8, 2), drawer.content_rect(Size.new(10, 4))
      end

      it "gives the right border column to the content once it is dropped" do
        drawer.right_border = false
        assert_equal Rect.new(1, 1, 9, 2), drawer.content_rect(Size.new(10, 4))
      end

      it "is empty for a box too small to have an inside" do
        assert drawer.content_rect(Size.new(2, 2)).empty?
      end
    end

    describe "#paint" do
      it "draws the caption into the top border and the footer into the bottom" do
        drawer.footer_text = StyledString.plain("q")
        assert_equal ["┌Log─────┐", "│        │", "└q───────┘"],
                     paint(Size.new(10, 3)).region_text(Rect.new(0, 0, 10, 3))
      end

      it "clips the caption to the inner width" do
        assert_equal "┌Lo┐", paint(Size.new(4, 2)).region_text(Rect.new(0, 0, 4, 1)).first
      end

      it "leaves the right column unpainted while the right border is dropped" do
        drawer.right_border = false
        assert_equal " ", paint(Size.new(10, 3)).cell(9, 1).grapheme
      end

      it "paints the whole border, caption included, in fg" do
        buffer = paint(Size.new(10, 3), caption: StyledString.styled("Log", fg: :red), fg: Color::GREEN)
        assert_equal Color::GREEN, buffer.cell(1, 0).style.fg
        assert_equal Color::GREEN, buffer.cell(0, 1).style.fg
      end

      it "paints nothing into an empty size" do
        paint(Size.new(0, 0))
      end
    end
  end
end
