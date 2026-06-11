# frozen_string_literal: true

module Tuile
  describe ScreenPane do
    before { Screen.fake }
    after { Screen.close }
    let(:pane) { Screen.instance.pane }

    it "is the root of the component tree" do
      assert_nil pane.parent
      assert_equal pane, pane.root
    end

    it "reports itself as attached to the screen" do
      assert pane.attached?
    end

    it "owns the status bar and parents it" do
      assert_instance_of Component::Label, pane.status_bar
      assert_equal pane, pane.status_bar.parent
    end

    it "is exposed via Screen#pane" do
      assert_equal pane, Screen.instance.pane
    end

    context "rect propagation" do
      it "lays out content and status bar when its rect is set" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        pane.rect = Rect.new(0, 0, 80, 24)
        assert_equal Rect.new(0, 0, 80, 23), layout.rect
        assert_equal Rect.new(0, 23, 80, 1), pane.status_bar.rect
      end

      it "relayouts on a height-only change" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        pane.rect = Rect.new(0, 0, 80, 24)
        pane.rect = Rect.new(0, 0, 80, 30)
        assert_equal Rect.new(0, 0, 80, 29), layout.rect
        assert_equal Rect.new(0, 29, 80, 1), pane.status_bar.rect
      end
    end

    context "parenting" do
      it "parents content when assigned" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        assert_equal pane, layout.parent
      end

      it "parents popups when added" do
        list = Component::List.new
        list.lines = ["a"]
        popup = Component::Popup.new(content: list)
        Screen.instance.add_popup(popup)
        assert_equal pane, popup.parent
      end

      it "detaches popup parent when removed" do
        list = Component::List.new
        list.lines = ["a"]
        popup = Component::Popup.new(content: list)
        Screen.instance.add_popup(popup)
        Screen.instance.remove_popup(popup)
        assert_nil popup.parent
      end
    end

    context "validation" do
      it "rejects non-Component content" do
        assert_raises(TypeError) { Screen.instance.content = "nope" }
      end

      it "rejects content that already has a parent" do
        layout = Component::Layout::Absolute.new
        Component::Popup.new(content: layout)
        assert_raises(ArgumentError) { Screen.instance.content = layout }
      end

      it "rejects a non-Popup as a popup" do
        assert_raises(TypeError) { Screen.instance.add_popup(Component::Label.new) }
      end

      it "rejects a popup that already has a parent" do
        popup = Component::Popup.new(content: Component::Label.new)
        Screen.instance.add_popup(popup)
        assert_raises(ArgumentError) { Screen.instance.add_popup(popup) }
      end

      it "rejects removing a popup that is not open" do
        popup = Component::Popup.new(content: Component::Label.new)
        # Screen#remove_popup silently no-ops on a non-open popup, so reach the
        # pane's guard directly.
        assert_raises(Tuile::Error) { pane.remove_popup(popup) }
      end
    end

    context "handle_key (capture + bubble dispatch)" do
      # Builds `content` = a Layout holding the given children and returns it.
      def content_with(*children)
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(children)
        layout
      end

      def field(width = 10)
        f = Component::TextField.new
        f.rect = Rect.new(0, 0, width, 1)
        f
      end

      it "captures a key_shortcut anywhere in scope and focuses it" do
        focused = Component::Button.new("one")
        target = Component::Button.new("two")
        target.key_shortcut = "g"
        content_with(focused, target)
        Screen.instance.focused = focused

        assert pane.handle_key("g")
        assert_equal target, Screen.instance.focused
      end

      it "suppresses shortcut capture while a cursor-owner is mid-edit" do
        shortcut = Component::Button.new("b")
        shortcut.key_shortcut = "g"
        f = field
        content_with(shortcut, f)
        Screen.instance.focused = f

        assert pane.handle_key("g")
        assert_equal "g", f.text # typed into the field, not captured
        assert_equal f, Screen.instance.focused
      end

      it "delivers a freely-typed key to the focused component" do
        f = field
        content_with(f)
        Screen.instance.focused = f

        assert pane.handle_key("z")
        assert_equal "z", f.text
      end

      it "delivers nothing when focus is nil" do
        f = field
        content_with(f)
        Screen.instance.focused = nil

        assert !pane.handle_key("z")
        assert_equal "", f.text
      end

      it "bubbles an undeclined key up to an ancestor (popup closes on q)" do
        list = Component::List.new
        list.lines = ["a"]
        list.cursor = Component::List::Cursor.new
        popup = Component::Popup.new(content: list)
        popup.open
        assert_equal list, Screen.instance.focused # open cascades focus onto the list

        assert pane.handle_key("q") # list declines q; popup handles it
        assert !popup.open?
      end

      it "does not deliver to content beneath an open popup (modal)" do
        beneath = field
        content_with(beneath)
        Screen.instance.focused = beneath

        popup_got = []
        inner = Class.new(Component) { def focusable? = true }.new
        inner.rect = Rect.new(0, 0, 5, 1)
        inner.define_singleton_method(:handle_key) { |k| popup_got << k }
        Component::Popup.new(content: inner).open   # cascades focus onto `inner`

        pane.handle_key("z")
        assert_equal ["z"], popup_got               # the open popup's content receives it
        assert_equal "", beneath.text               # content beneath is untouched
      end
    end

    context "non-modal overlays" do
      def field(width = 10)
        f = Component::TextField.new
        f.rect = Rect.new(0, 0, width, 1)
        f
      end

      def list_of(line)
        Component::List.new.tap { _1.lines = [line] }
      end

      it "modal_popup ignores non-modal overlays but finds a modal popup" do
        Screen.instance.add_popup(Component::Popup.new(content: Component::Label.new, modal: false))
        assert_nil pane.modal_popup

        modal = Component::Popup.new(content: Component::Label.new)
        Screen.instance.add_popup(modal)
        assert_equal modal, pane.modal_popup
      end

      it "delivers keys to the focused content while an overlay floats above it" do
        f = field
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(f)
        Screen.instance.focused = f
        Component::Popup.new(content: Component::Label.new, modal: false).open

        assert pane.handle_key("z")
        assert_equal "z", f.text                    # the editor keeps receiving keys
      end

      it "routes a click outside the overlay through to the content beneath" do
        clicks = []
        beneath = Class.new(Component) { def focusable? = true }.new
        beneath.rect = Rect.new(0, 0, 80, 40)
        beneath.define_singleton_method(:handle_mouse) { |e| clicks << e.point }
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(beneath)

        overlay = Component::Popup.new(content: list_of("a"), modal: false)
        overlay.open
        overlay.rect = Rect.new(50, 1, 5, 3)

        pane.handle_mouse(MouseEvent.new(:left, 2, 2)) # outside the overlay rect
        assert_equal [Point.new(2, 2)], clicks
      end

      it "routes a click inside the overlay to the overlay, not the content" do
        clicks = []
        beneath = Class.new(Component) { def focusable? = true }.new
        beneath.rect = Rect.new(0, 0, 80, 40)
        beneath.define_singleton_method(:handle_mouse) { |_| clicks << :beneath }
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(beneath)

        inner = list_of("a")
        inner.define_singleton_method(:handle_mouse) { |_| clicks << :overlay }
        overlay = Component::Popup.new(content: inner, modal: false)
        overlay.open
        overlay.rect = Rect.new(50, 1, 5, 3)
        inner.rect = overlay.rect

        pane.handle_mouse(MouseEvent.new(:left, 51, 2)) # inside the overlay rect
        assert_equal [:overlay], clicks
      end
    end
  end
end
