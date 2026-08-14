# frozen_string_literal: true

module Tuile
  describe Component::ListDropdown do
    before { Screen.fake }
    after { Screen.close }

    # A dropdown mounted as the tiled root's overlay, sized to a 20×10 box so
    # half-page / page jumps are observable, and filled with `count` rows.
    def dropdown(count: 30)
      d = Component::ListDropdown.new
      Screen.instance.content = Component::Label.new # something for focus to rest on
      d.lines = (1..count).map { |n| "item#{n}" }
      d.size = Size.new(20, 10)
      d.open
      d
    end

    def list(drop) = drop.instance_variable_get(:@list)

    describe "construction" do
      it "wraps a non-focusable, non-tab-stop list" do
        d = Component::ListDropdown.new
        refute list(d).focusable?
        refute list(d).tab_stop?
      end

      it "is a non-modal popup" do
        refute Component::ListDropdown.new.modal?
      end

      it "tints itself with a live Theme::Ref to input_bg_color" do
        assert_equal Theme.ref(:input_bg_color), Component::ListDropdown.new.bg_color
      end

      it "the list inherits that tint via effective_bg_color" do
        d = Component::ListDropdown.new
        assert_equal Theme::DARK.input_bg_color, list(d).effective_bg_color
      end
    end

    describe "content delegation" do
      it "the deprecated lines= / lines still round-trip through the list" do
        d = Component::ListDropdown.new
        d.lines = %w[a b c]
        assert_equal %w[a b c], d.lines.map(&:to_s)
      end

      it "cursor= / cursor round-trips through the list" do
        d = Component::ListDropdown.new
        d.cursor = Component::List::Cursor.new(position: 2)
        assert_equal 2, d.cursor.position
      end
    end

    describe "#move" do
      it "Ctrl+D moves the highlight down by half a page" do
        d = dropdown
        assert_equal 0, d.cursor.position
        assert d.move(Keys::CTRL_D)
        assert_equal 5, d.cursor.position # viewport 10 → half-page 5
      end

      it "Ctrl+U moves the highlight up by half a page" do
        d = dropdown
        d.cursor = Component::List::Cursor.new(position: 10)
        assert d.move(Keys::CTRL_U)
        assert_equal 5, d.cursor.position
      end

      it "Page Down scrolls the viewport a full page" do
        d = dropdown
        assert_equal 0, list(d).top_line
        assert d.move(Keys::PAGE_DOWN)
        assert_equal 10, list(d).top_line
      end

      it "Page Up scrolls the viewport back" do
        d = dropdown
        d.move(Keys::PAGE_DOWN)
        assert d.move(Keys::PAGE_UP)
        assert_equal 0, list(d).top_line
      end

      it "arrows move the highlight one row" do
        d = dropdown
        assert d.move(Keys::DOWN_ARROW)
        assert_equal 1, d.cursor.position
        assert d.move(Keys::UP_ARROW)
        assert_equal 0, d.cursor.position
      end

      it "does not claim Enter, ESC, Home/End, or printables" do
        d = dropdown
        [Keys::ENTER, Keys::ESC, Keys::HOME, Keys::END_, "j", "k"].each do |key|
          refute d.move(key), "expected #move to decline #{key.inspect}"
        end
      end

      it "declines every key while closed" do
        d = dropdown
        d.close
        refute d.move(Keys::DOWN_ARROW)
      end
    end

    describe "#anchor_to" do
      # A dropdown filled with `rows` rows and anchored to a one-row driver rect;
      # `kwargs` (an explicit `width:` / `max_rows:`) reach {#anchor_to}.
      def anchored(rows:, top: 0, left: 0, anchor_width: 20, **kwargs)
        d = Component::ListDropdown.new
        Screen.instance.content = Component::Label.new
        d.lines = (1..rows).map { |n| "item#{n}" }
        d.anchor_to(Rect.new(left, top, anchor_width, 1), rows: rows, **kwargs)
        d
      end

      it "sits directly below the anchor, at the anchor's width" do
        assert_equal Rect.new(3, 1, 20, 4), anchored(rows: 4, top: 0, left: 3).rect
      end

      it "caps the height at MAX_VISIBLE_ROWS" do
        assert_equal 10, anchored(rows: 30).rect.height
      end

      it "honors an explicit max_rows" do
        assert_equal 3, anchored(rows: 30, max_rows: 3).rect.height
      end

      it "flips above the anchor when the rows won't fit below" do
        # The fake screen is 50 tall, so a driver on row 48 has one row beneath.
        assert_equal Rect.new(0, 44, 20, 4), anchored(rows: 4, top: 48).rect
      end

      it "clamps the height when neither side has room" do
        Screen.instance.instance_variable_set(:@size, Size.new(60, 8))
        # 5 rows below, 2 above: below wins, and the list scrolls within them.
        assert_equal Rect.new(0, 3, 20, 5), anchored(rows: 30, top: 2).rect
      end

      it "honors a caller-supplied width instead of the anchor's" do
        assert_equal 9, anchored(rows: 4, anchor_width: 20, width: 9).rect.width
      end

      it "clamps a width wider than the screen" do
        assert_equal 160, anchored(rows: 4, width: 400).rect.width
      end

      it "slides left to keep an over-wide panel on screen" do
        # 155 + 9 would end at 164; the panel slides so its right edge is 160.
        assert_equal 151, anchored(rows: 4, left: 155, width: 9).rect.left
      end

      it "never slides past the left edge" do
        Screen.instance.instance_variable_set(:@size, Size.new(6, 20))
        assert_equal 0, anchored(rows: 4, left: 3, width: 6).rect.left
      end

      it "collapses to an empty rect when there are no rows" do
        assert anchored(rows: 0).rect.empty?
      end
    end

    describe "the scrollbar tracks whether the rows fit" do
      # The painted rows of a dropdown anchored to a 20-wide driver on row 0.
      def painted(count, **kwargs)
        d = Component::ListDropdown.new
        Screen.instance.content = Component::Label.new
        d.open
        refill(d, count, **kwargs)
        Screen.instance.repaint
        Screen.instance.buffer.region_text(d.rect)
      end

      def refill(drop, count, top: 0, **kwargs)
        drop.lines = (1..count).map { |n| "item#{n}" }
        drop.anchor_to(Rect.new(0, top, 20, 1), rows: count, **kwargs)
      end

      it "paints a scrollbar column when the rows overflow the height" do
        rows = painted(30)
        assert_equal "█", rows.first[-1]
        assert_equal "░", rows.last[-1]
      end

      it "paints none when every row fits" do
        refute_match(/[█░]/, painted(4).join)
      end

      it "appears when the screen clamps the height below max_rows too" do
        Screen.instance.instance_variable_set(:@size, Size.new(60, 8))
        # 6 rows, 5 rows of room: it scrolls well short of max_rows, so it says so.
        assert_equal "█", painted(6, top: 2).first[-1]
      end

      # The one path this can break: `scrollbar_visibility=` rebuilds List's
      # padded-row cache because the gutter changes the content width. A refill
      # that crosses the threshold must re-pad, or every row sits a column off.
      it "re-pads the rows when a refill drops below the threshold" do
        d = Component::ListDropdown.new
        Screen.instance.content = Component::Label.new
        d.open
        refill(d, 11)
        Screen.instance.repaint
        assert_equal " item1#{" " * 13}█", Screen.instance.buffer.region_text(d.rect).first

        refill(d, 3)
        Screen.instance.repaint
        assert_equal " item1#{" " * 14}", Screen.instance.buffer.region_text(d.rect).first
      end

      it "re-pads them when a refill crosses back up" do
        d = Component::ListDropdown.new
        Screen.instance.content = Component::Label.new
        d.open
        refill(d, 3)
        Screen.instance.repaint
        refill(d, 11)
        Screen.instance.repaint
        assert_equal " item1#{" " * 13}█", Screen.instance.buffer.region_text(d.rect).first
      end
    end

    describe "#choose" do
      it "fires on_item_chosen with the highlighted index and returns true" do
        d = dropdown
        seen = []
        d.on_item_chosen = ->(index, line) { seen << [index, line.to_s] }
        d.cursor = Component::List::Cursor.new(position: 3)
        assert d.choose
        assert_equal [[3, "item4"]], seen
      end

      it "returns false and fires nothing when the cursor is off-content" do
        d = dropdown(count: 0)
        fired = false
        d.on_item_chosen = ->(_i, _l) { fired = true }
        refute d.choose
        refute fired
      end
    end
  end
end
