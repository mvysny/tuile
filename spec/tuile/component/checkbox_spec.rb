# frozen_string_literal: true

module Tuile
  describe Component::Checkbox do
    before { Screen.fake }
    after { Screen.close }

    def checkbox(caption: "Syslog", width: 10, active: false, value: false)
      cb = Component::Checkbox.new(caption, value:)
      cb.rect = Rect.new(0, 0, width, 1)
      cb.active = active
      cb
    end

    # Attaches the checkbox to the screen so invalidation and click-to-focus,
    # both gated on `attached?`, actually do something.
    def attached_checkbox(**kwargs)
      layout = Component::Layout::Absolute.new
      Screen.instance.content = layout
      checkbox(**kwargs).tap { layout.add(_1) }
    end

    it "starts unchecked, and unchecked counts as empty" do
      cb = Component::Checkbox.new
      assert_equal false, cb.value
      assert cb.empty?
    end

    it "seeds the value from the constructor" do
      assert_equal true, Component::Checkbox.new("Syslog", value: true).value
    end

    it "stores the constructor caption as a StyledString" do
      assert_equal StyledString.plain("Syslog"), Component::Checkbox.new("Syslog").caption
    end

    it "is focusable and a tab stop" do
      cb = Component::Checkbox.new
      assert cb.focusable?
      assert cb.tab_stop?
    end

    context "value" do
      it "coerces a truthy value to true" do
        cb = Component::Checkbox.new
        cb.value = "yes"
        assert_equal true, cb.value
      end

      it "coerces nil to false — a no-op on a fresh checkbox, so nothing fires" do
        cb = Component::Checkbox.new
        fired = 0
        cb.on_value_change = ->(_) { fired += 1 }
        cb.value = nil
        assert_equal false, cb.value
        assert_equal 0, fired
      end

      it "fires on_value_change once per real change" do
        cb = Component::Checkbox.new
        seen = []
        cb.on_value_change = ->(v) { seen << v }
        cb.value = true
        cb.value = true
        cb.value = false
        assert_equal [true, false], seen
      end

      it "clears back to unchecked" do
        cb = Component::Checkbox.new(nil, value: true)
        cb.clear
        assert_equal false, cb.value
        assert cb.empty?
      end

      it "tracks value through checked?/checked=/toggle, firing the one listener" do
        cb = Component::Checkbox.new
        seen = []
        cb.on_value_change = ->(v) { seen << v }
        cb.checked = true
        assert cb.checked?
        cb.toggle
        assert_equal false, cb.checked?
        assert_equal [true, false], seen
      end

      it "invalidates when the value changes" do
        cb = attached_checkbox
        Screen.instance.invalidated_clear
        cb.toggle
        assert Screen.instance.invalidated?(cb)
      end
    end

    context "handle_key" do
      it "toggles on Space and reports the key handled" do
        cb = checkbox
        fired = 0
        cb.on_value_change = ->(_) { fired += 1 }
        assert_equal true, cb.handle_key(" ")
        assert_equal true, cb.value
        assert_equal 1, fired
      end

      it "toggles on Enter too, and consumes it rather than bubbling to a form" do
        cb = checkbox
        fired = 0
        cb.on_value_change = ->(_) { fired += 1 }
        assert_equal true, cb.handle_key(Keys::ENTER)
        assert_equal true, cb.value
        assert_equal 1, fired
      end

      it "returns false for other keys" do
        assert_equal false, checkbox.handle_key("x")
      end
    end

    context "handle_mouse" do
      it "toggles on a left click inside the extent" do
        cb = attached_checkbox
        cb.handle_mouse(MouseEvent.new(:left, 1, 0))
        assert_equal true, cb.value
      end

      it "focuses on a left click (via super)" do
        cb = attached_checkbox
        cb.handle_mouse(MouseEvent.new(:left, 1, 0))
        assert_equal cb, Screen.instance.focused
      end

      it "ignores non-left buttons" do
        cb = attached_checkbox
        cb.handle_mouse(MouseEvent.new(:right, 1, 0))
        assert_equal false, cb.value
      end

      it "focuses but does not toggle when the click lands on the blank tail" do
        cb = attached_checkbox(caption: "Syslog", width: 40) # extent is 10 columns
        cb.handle_mouse(MouseEvent.new(:left, 20, 0))
        assert_equal false, cb.value
        assert_equal cb, Screen.instance.focused
      end

      it "does not toggle on a row below the painted one" do
        cb = attached_checkbox(caption: "Syslog", width: 40)
        cb.rect = Rect.new(0, 0, 40, 3)
        cb.handle_mouse(MouseEvent.new(:left, 1, 2))
        assert_equal false, cb.value
      end

      it "keeps the extent — and so the hit test — independent of an inherited bg_color" do
        cb = attached_checkbox(caption: "Syslog", width: 40)
        cb.parent.bg_color = 52 # paints the dead tail, but must not widen the target
        assert_equal 10, cb.extent.width
        cb.handle_mouse(MouseEvent.new(:left, 20, 0))
        assert_equal false, cb.value
      end
    end

    context "extent" do
      it "is the caption plus the glyph, one row" do
        assert_equal Rect.new(0, 0, 10, 1), checkbox(caption: "Syslog", width: 40).extent
      end

      it "clips to a narrower rect" do
        assert_equal Rect.new(0, 0, 5, 1), checkbox(caption: "Syslog", width: 5).extent
      end
    end

    context "repaint" do
      it "is a no-op when rect is empty" do
        Component::Checkbox.new("Syslog").repaint
        assert_equal [], Screen.instance.prints
      end

      it "paints [ ] when unchecked and [x] when checked" do
        cb = checkbox(caption: "Syslog", width: 10)
        cb.repaint
        assert_equal "[ ] Syslog", Screen.instance.buffer.region_text(cb.rect).join
        cb.toggle
        cb.repaint
        assert_equal "[x] Syslog", Screen.instance.buffer.region_text(cb.rect).join
      end

      it "paints an unset caption without crashing" do
        cb = checkbox(caption: nil, width: 6)
        cb.repaint
        assert_equal "[ ]   ", Screen.instance.buffer.region_text(cb.rect).join
      end

      it "highlights the extent, not the whole row, when active" do
        cb = checkbox(caption: "Syslog", width: 20, active: true)
        cb.repaint
        buffer = Screen.instance.buffer
        assert_equal Screen.instance.theme.active_bg_color, buffer.cell(0, 0).style.bg
        assert_equal Screen.instance.theme.active_bg_color, buffer.cell(9, 0).style.bg
        assert_nil buffer.cell(10, 0).style.bg
      end

      it "ellipsizes a caption too wide for the rect" do
        cb = checkbox(caption: "Enable syslog", width: 8)
        cb.repaint
        assert_equal "[ ] Ena…", Screen.instance.buffer.region_text(cb.rect).join
      end

      it "keeps a double-width caption inside rect — clipping is by display width" do
        cb = checkbox(caption: "日本語テキスト", width: 8)
        cb.rect = Rect.new(2, 0, 8, 1)
        cb.repaint
        buffer = Screen.instance.buffer
        # "[ ] 日本語テキスト" is 18 columns; a char-count clip would have painted
        # 8 characters — 12 columns — running 4 past rect.right. The ellipsis
        # can't split the second wide glyph, so the row ends a column short.
        assert_equal "[ ] 日… ", buffer.region_text(cb.rect).join
        assert_equal " ", buffer.cell(10, 0).grapheme
      end

      it "shows an inherited bg_color on the row's blank tail" do
        parent = Component::Layout::Absolute.new
        cb = Component::Checkbox.new("Syslog")
        parent.add(cb)
        cb.rect = Rect.new(0, 0, 20, 1)
        parent.bg_color = 52
        cb.repaint
        buffer = Screen.instance.buffer
        assert_equal Color.new(52), buffer.cell(0, 0).style.bg  # behind the glyph
        assert_equal Color.new(52), buffer.cell(15, 0).style.bg # the dead tail
      end
    end

    context "integration: Tab cycling and Space activation" do
      it "Tab moves through checkboxes and Space toggles the focused one" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        a = Component::Checkbox.new("A")
        b = Component::Checkbox.new("B")
        layout.add([a, b])
        screen.focused = a

        screen.send(:handle_key, Keys::TAB)
        assert_equal b, screen.focused

        screen.send(:handle_key, " ")
        assert_equal false, a.value
        assert_equal true, b.value
      end
    end
  end
end
