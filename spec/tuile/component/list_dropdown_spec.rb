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
      it "lines= / lines round-trips through the list" do
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
