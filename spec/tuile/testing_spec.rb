# frozen_string_literal: true

module Tuile
  describe Testing do
    before { Screen.fake }
    after { Screen.close }

    # A small form: a window whose column holds two buttons and a field, so a
    # class match is ambiguous and needs a caption, an id or a scope to resolve.
    let(:column) { Component::Layout::Vertical.new }
    let(:save) { Component::Button.new("Save").tap { _1.id = :save } }
    let(:cancel) { Component::Button.new("Cancel") }
    let(:field) { Component::TextField.new.tap { _1.text = "Zaphod" } }

    let(:window) do
      Component::Window.new("Settings").tap do |w|
        w.content = column
        column.add(save)
        column.add(cancel)
        column.add(field)
        Screen.instance.content = w
        w.rect = Rect.new(0, 0, 40, 10)
      end
    end

    describe "matching" do
      it "finds by class" do
        window
        assert_equal [save, cancel], Testing.find(Component::Button)
      end

      it "finds by id" do
        window
        assert_same save, Testing.get(id: :save)
      end

      it "finds by exact caption" do
        window
        assert_same cancel, Testing.get(Component::Button, caption: "Cancel")
      end

      it "takes a Regexp caption as a partial match" do
        window
        assert_same save, Testing.get(Component::Button, caption: /^Sav/)
      end

      it "never matches a caption against a component that has none" do
        window
        assert_empty Testing.find(Component::TextField, caption: "Zaphod")
      end

      it "matches a mixin, so a seam finds every field that includes it" do
        window
        assert_equal [field], Testing.find(Component::HasValue)
      end

      it "narrows with a block predicate" do
        window
        assert_same cancel, Testing.get(Component::Button) { _1.caption.to_s.start_with?("C") }
      end

      it "searches the whole screen by default, popups included" do
        window
        popup = Component::Popup.new(content: Component::Button.new("OK"))
        Screen.instance.add_popup(popup)
        captions = Testing.find(Component::Button).map { _1.caption.to_s }
        assert_equal %w[Save Cancel OK], captions
      end

      # The sampler's own walks are scoped like this: its jump box is a ComboBox
      # too, so an unscoped class match reaches the navigator, not the demo.
      it "searches only the given subtree, root included" do
        window
        assert_equal [save, cancel], Testing.find(Component::Button, in: column)
        assert_equal [column], Testing.find(Component::Layout::Vertical, in: column)
      end
    end

    describe "count" do
      it "accepts any number when not given" do
        window
        assert_equal 2, Testing.find(Component::Button).size
        assert_empty Testing.find(Component::Checkbox)
      end

      it "passes an exact Integer" do
        window
        assert_equal 2, Testing.find(Component::Button, count: 2).size
      end

      it "passes a Range" do
        window
        assert_equal 2, Testing.find(Component::Button, count: 1..).size
      end

      it "raises when the count differs" do
        window
        assert_raises(Testing::LookupError) { Testing.find(Component::Button, count: 3) }
        assert_raises(Testing::LookupError) { Testing.find(Component::Button, count: 3..) }
      end

      # `count: 0` falls out of the same check, but a spec asserting nothing is
      # open says `assert_empty Screen.instance.popups` instead.
      it "accepts a zero count" do
        window
        assert_empty Testing.find(Component::Checkbox, count: 0)
      end
    end

    describe ".get" do
      it "raises when nothing matches" do
        window
        e = assert_raises(Testing::LookupError) { Testing.get(Component::Checkbox) }
        assert_includes e.message, "expected 1 Component::Checkbox, found 0"
      end

      it "raises rather than picking the first of an ambiguous match" do
        window
        e = assert_raises(Testing::LookupError) { Testing.get(Component::Button) }
        assert_includes e.message, "found 2"
      end

      it "names every part of the spec it was given" do
        window
        e = assert_raises(Testing::LookupError) do
          Testing.get(Component::Button, id: :nope, caption: "Save") { true }
        end
        assert_includes e.message, "expected 1 Component::Button id=:nope caption=\"Save\" matching the block"
      end

      it "is a Tuile::Error, so an app rescuing that catches it" do
        window
        assert_raises(Tuile::Error) { Testing.get(Component::Checkbox) }
      end
    end

    describe ".dump" do
      it "indents by depth, relative to the searched root" do
        window
        assert_equal [
          "  #<Window rect=(0,0 40x10) caption=\"Settings\">",
          "    #<Layout::Vertical rect=(1,1 38x8)>",
          "      #<Button id=:save rect=(1,1 38x1) caption=\"Save\">",
          "      #<Button rect=(1,2 38x1) caption=\"Cancel\">",
          "      #<TextField rect=(1,3 38x1) value=\"Zaphod\">",
          "    #<Slot rect=(0,0 0x0)>" # the window's empty footer slot
        ], Testing.dump(window).lines(chomp: true)
      end

      it "flags the marked components, so a failed lookup shows which they were" do
        window
        marked = Testing.dump(column, [save]).lines(chomp: true).grep(/^→/)
        assert_equal ["→   #<Button id=:save rect=(1,1 38x1) caption=\"Save\">"], marked
      end

      it "rides in the failure message" do
        window
        e = assert_raises(Testing::LookupError) { Testing.get(Component::Button) }
        assert_includes e.message, "searched:\n"
        # Rooted at the pane, since the lookup was unscoped.
        assert_includes e.message, "  #<ScreenPane rect=(0,0 160x50)>\n"
        assert_equal 2, e.message.lines.grep(/^→ +#<Button/).size
      end
    end
  end
end
