# frozen_string_literal: true

module Tuile
  describe Component::Button do
    before { Screen.fake }
    after { Screen.close }

    def button(caption: "OK", width: 10, active: true, &on_click)
      b = Component::Button.new(caption, &on_click)
      b.rect = Rect.new(0, 0, width, 1)
      b.active = active if active
      b
    end

    it "defaults to empty caption" do
      assert_equal "", Component::Button.new.caption
    end

    it "stores the constructor caption" do
      assert_equal "Save", Component::Button.new("Save").caption
    end

    it "is focusable" do
      assert Component::Button.new.focusable?
    end

    it "is a tab stop" do
      assert Component::Button.new.tab_stop?
    end

    context "caption=" do
      it "updates the caption" do
        b = Component::Button.new("a")
        b.caption = "b"
        assert_equal "b", b.caption
      end

      it "invalidates when the caption changes" do
        b = Component::Button.new("a")
        Screen.instance.invalidated_clear
        b.caption = "b"
        assert Screen.instance.invalidated?(b)
      end

      it "is a no-op when the caption is unchanged" do
        b = Component::Button.new("a")
        Screen.instance.invalidated_clear
        b.caption = "a"
        assert !Screen.instance.invalidated?(b)
      end
    end

    context "content_size" do
      it "fits `[ caption ]` plus borders on a single row" do
        b = Component::Button.new("Ok")
        # "[ Ok ]" → 6 chars
        assert_equal Size.new(6, 1), b.content_size
      end

      it "is `[]` width for an empty caption" do
        # "[  ]" → 4 chars (open-bracket, space, space, close-bracket)
        assert_equal Size.new(4, 1), Component::Button.new.content_size
      end
    end

    context "handle_key" do
      it "fires on_click on Enter when active" do
        fired = 0
        b = button { fired += 1 }
        assert_equal true, b.handle_key(Keys::ENTER)
        assert_equal 1, fired
      end

      it "fires on_click on Space when active" do
        fired = 0
        b = button { fired += 1 }
        assert_equal true, b.handle_key(" ")
        assert_equal 1, fired
      end

      it "does not fire on Enter when inactive" do
        fired = 0
        b = button(active: false) { fired += 1 }
        assert_equal false, b.handle_key(Keys::ENTER)
        assert_equal 0, fired
      end

      it "returns false for non-activation keys" do
        b = button { raise "shouldn't fire" }
        assert_equal false, b.handle_key("x")
      end

      it "does not crash when on_click is nil" do
        b = button
        b.on_click = nil
        assert_equal true, b.handle_key(Keys::ENTER)
      end
    end

    context "handle_mouse" do
      it "fires on_click on a left-click inside the rect" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        fired = 0
        b = button(active: false) { fired += 1 }
        layout.add(b)
        b.handle_mouse(MouseEvent.new(:left, 0, 0))
        assert_equal 1, fired
      end

      it "focuses the button on left-click (via super)" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        b = button(active: false)
        layout.add(b)
        b.handle_mouse(MouseEvent.new(:left, 0, 0))
        assert_equal b, screen.focused
      end

      it "ignores non-left-button events" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        fired = 0
        b = button { fired += 1 }
        layout.add(b)
        b.handle_mouse(MouseEvent.new(:right, 0, 0))
        assert_equal 0, fired
      end

      it "ignores clicks outside the rect" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        fired = 0
        b = button { fired += 1 }
        layout.add(b)
        b.handle_mouse(MouseEvent.new(:left, 50, 0))
        assert_equal 0, fired
      end
    end

    context "repaint" do
      it "is a no-op when rect is empty" do
        b = Component::Button.new("Ok")
        b.repaint
        assert_equal [], Screen.instance.prints
      end

      it "draws `[ caption ]` plain when inactive" do
        b = button(caption: "Ok", width: 6, active: false)
        Screen.instance.prints.clear
        b.repaint
        assert_includes Screen.instance.prints.join, "[ Ok ]"
      end

      it "applies a Rainbow background style when active" do
        old_rainbow = Rainbow.enabled
        Rainbow.enabled = true
        begin
          b = button(caption: "Ok", width: 6, active: true)
          Screen.instance.prints.clear
          b.repaint
          painted = Screen.instance.prints.join
          # Active button is wrapped in a Rainbow style; strip and the caption
          # is still there. Verifies the painted output is not equal to the
          # uncolored caption (i.e. some escape was added).
          assert_includes Rainbow.uncolor(painted), "[ Ok ]"
          refute_equal painted, Rainbow.uncolor(painted)
        ensure
          Rainbow.enabled = old_rainbow
        end
      end

      it "clips the label to rect.width" do
        b = button(caption: "WideCaption", width: 6, active: false)
        Screen.instance.prints.clear
        b.repaint
        # "[ WideCaption ]" clipped to 6 chars = "[ Wide"
        assert_includes Screen.instance.prints.join, "[ Wide"
        refute_includes Screen.instance.prints.join, "Caption ]"
      end
    end

    context "integration: Tab cycling and Enter activation" do
      it "Tab moves through buttons and Enter fires the focused one" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        a_fired = 0
        b_fired = 0
        a = Component::Button.new("A") { a_fired += 1 }
        b = Component::Button.new("B") { b_fired += 1 }
        layout.add([a, b])
        screen.focused = a
        assert_equal a, screen.focused

        screen.send(:handle_key, Keys::TAB)
        assert_equal b, screen.focused

        screen.send(:handle_key, Keys::ENTER)
        assert_equal 0, a_fired
        assert_equal 1, b_fired
      end
    end
  end
end
