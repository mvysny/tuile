# frozen_string_literal: true

module Tuile
  describe Screen do
    before { Screen.fake }
    after { Screen.close }
    let(:screen) { Screen.instance }

    it "provides singleton instance" do
      assert_equal screen, Screen.instance
    end

    context "focused=" do
      before { screen.content = Component::Layout::Absolute.new }

      def add_window
        w = Window.new
        screen.content.add(w)
        w
      end

      it "raises when given a non-component" do
        assert_raises(RuntimeError) { screen.focused = "not a component" }
      end

      it "raises when component is not in the content tree" do
        screen.focused = nil
        w = Window.new
        assert_raises(RuntimeError) { screen.focused = w }
      end

      it "sets focused to the given component" do
        w = add_window
        screen.focused = w
        assert_equal w.content, screen.focused
      end

      it "marks focused component as active" do
        w = add_window
        screen.focused = w
        assert w.active?
      end

      it "deactivates windows not in the focused path" do
        w1 = add_window
        w2 = add_window
        screen.focused = w1
        screen.focused = w2
        assert !w1.active?
        assert w2.active?
      end

      it "with nil clears active on all components" do
        w = add_window
        screen.focused = w
        screen.focused = nil
        assert !w.active?
      end

      it "with nil and no content does not raise" do
        screen2 = Screen.fake
        assert_nil screen2.content
        screen2.focused = nil
      end

      it "marks all ancestor layouts active when focusing a nested window" do
        nested_layout = Component::Layout::Absolute.new
        screen.content.add(nested_layout)
        w = Window.new
        nested_layout.add(w)
        screen.focused = w
        assert w.active?
        assert nested_layout.active?
      end

      it "deactivates ancestor layouts when focus moves to a different branch" do
        layout1 = Component::Layout::Absolute.new
        layout2 = Component::Layout::Absolute.new
        screen.content.add(layout1)
        screen.content.add(layout2)
        w1 = Window.new
        w2 = Window.new
        layout1.add(w1)
        layout2.add(w2)
        screen.focused = w1
        screen.focused = w2
        assert !w1.active?
        assert !layout1.active?
        assert w2.active?
        assert layout2.active?
      end

      it "propagates handle_key through nested layouts to focused window" do
        nested_layout = Component::Layout::Absolute.new
        screen.content.add(nested_layout)
        w = Window.new
        nested_layout.add(w)
        screen.focused = w
        handled = false
        w.define_singleton_method(:handle_key) { |_key| handled = true }
        screen.content.handle_key("x")
        assert handled
      end
    end

    context "active_window" do
      it "is nil when no windows" do
        assert_nil screen.active_window
      end

      it "returns the active window" do
        w = Window.new
        screen.content = Component::Layout::Absolute.new
        screen.content.add(w)
        w.active = true
        assert_equal w, screen.active_window
      end
    end

    context "status bar" do
      def status_text = Rainbow.uncolor(screen.pane.status_bar.instance_variable_get(:@lines).first || "")

      it "shows 'q quit' and the active window's hint when no popup is open" do
        w = Class.new(Window) { def keyboard_hint = "h help" }.new
        screen.content = Component::Layout::Absolute.new
        screen.content.add(w)
        screen.focused = w
        assert_equal "q quit  h help", status_text
      end

      it "shows 'q close' and the popup's hint when a popup is open" do
        popup = Class.new(PopupWindow) { def keyboard_hint = "a all" }.new("foo")
        screen.add_popup(popup)
        assert_equal "q close  a all", status_text
      end

      it "reverts to 'q quit' after the popup closes" do
        popup = PopupWindow.new("foo")
        screen.add_popup(popup)
        popup.close
        assert_equal "q quit", status_text
      end
    end

    context "size" do
      it "returns screen dimensions" do
        assert_equal 160, screen.size.width
        assert_equal 50, screen.size.height
      end
    end

    context "content=" do
      it "sets the content" do
        layout = Component::Layout::Absolute.new
        screen.content = layout
        assert_equal layout, screen.content
      end

      it "positions content to fill the screen minus the status bar row" do
        layout = Component::Layout::Absolute.new
        screen.content = layout
        assert_equal Rect.new(0, 0, 160, 49), layout.rect
      end

      it "deactivates all components in the old content tree when content changes" do
        layout = Component::Layout::Absolute.new
        w = Window.new
        screen.content = layout
        layout.add(w)
        screen.focused = w
        assert w.active?
        screen.content = Component::Layout::Absolute.new
        assert !w.active?
      end
    end

    context "invalidate" do
      it "marks a component as invalidated" do
        w = Window.new
        screen.content = Component::Layout::Absolute.new
        screen.content.add(w)
        screen.invalidated_clear
        screen.invalidate(w)
        assert screen.invalidated?(w)
      end
    end

    context "repaint" do
      before do
        screen.content = Component::Layout::Absolute.new
        screen.invalidated_clear
      end

      def add_window
        w = Window.new
        screen.content.add(w)
        screen.invalidated_clear
        w
      end

      it "calls repaint on each invalidated component" do
        w = add_window
        repainted = false
        w.define_singleton_method(:repaint) { repainted = true }
        screen.invalidate(w)
        screen.repaint
        assert repainted
      end

      it "clears the invalidated set after repaint" do
        w = add_window
        screen.invalidate(w)
        screen.repaint
        assert !screen.invalidated?(w)
      end

      it "does nothing when nothing is invalidated" do
        repainted = false
        screen.content.define_singleton_method(:repaint) { repainted = true }
        screen.repaint
        assert !repainted
      end

      it "repaints parent before child (sorted by depth)" do
        w = add_window
        order = []
        screen.content.define_singleton_method(:repaint) { order << :parent }
        w.define_singleton_method(:repaint) { order << :child }
        screen.invalidate(screen.content)
        screen.invalidate(w)
        screen.repaint
        assert_equal %i[parent child], order
      end

      it "also repaints open popups when tiled content is invalidated" do
        w = add_window
        popup = PopupWindow.new
        screen.add_popup(popup)
        screen.invalidated_clear

        popup_repainted = false
        popup.define_singleton_method(:repaint) { popup_repainted = true }
        screen.invalidate(w)
        screen.repaint
        assert popup_repainted
      end

      it "does not repaint tiled content when only a popup is invalidated" do
        w = add_window
        popup = PopupWindow.new
        screen.add_popup(popup)
        screen.invalidated_clear

        tiled_repainted = false
        w.define_singleton_method(:repaint) { tiled_repainted = true }
        screen.invalidate(popup)
        screen.repaint
        assert !tiled_repainted
      end

      it "paints popup descendants after tiled descendants so popup contents are not overdrawn" do
        # Regression: ScreenPane refactor put popups under the pane (depth 1) and
        # their contents at depth 2. A tiled list at depth 3 would then sort *after*
        # popup.content and overdraw it, leaving the popup empty until the user
        # nudged the popup's cursor and triggered a fresh paint.
        w = add_window
        popup = PopupWindow.new
        popup.content = ["option"]
        screen.add_popup(popup)
        screen.invalidated_clear

        order = []
        w.content.define_singleton_method(:repaint) { order << :tiled_content }
        popup.content.define_singleton_method(:repaint) { order << :popup_content }
        screen.invalidate(w.content)
        screen.invalidate(popup.content)
        screen.repaint

        assert_equal %i[tiled_content popup_content], order
      end

      it "hides the hardware cursor after repaint when no component owns it" do
        w = add_window
        screen.invalidate(w)
        screen.prints.clear
        screen.repaint
        assert_includes screen.prints, TTY::Cursor.hide
      end

      it "shows and positions the hardware cursor when a focused component supplies a cursor_position" do
        w = add_window
        w.content.define_singleton_method(:can_activate?) { true }
        w.content.define_singleton_method(:cursor_position) { Point.new(7, 4) }
        screen.focused = w.content
        screen.prints.clear
        screen.invalidate(w)
        screen.repaint
        assert_includes screen.prints, TTY::Cursor.move_to(7, 4)
        assert_includes screen.prints, TTY::Cursor.show
      end

      it "does not emit cursor commands when nothing is invalidated" do
        screen.prints.clear
        screen.repaint
        assert_equal [], screen.prints
      end

      it "prefers a cursor_position from a popup over tiled content" do
        w = add_window
        w.content.define_singleton_method(:can_activate?) { true }
        w.content.define_singleton_method(:cursor_position) { Point.new(1, 1) }
        screen.focused = w.content
        popup = PopupWindow.new
        popup.content.define_singleton_method(:can_activate?) { true }
        popup.content.define_singleton_method(:cursor_position) { Point.new(99, 33) }
        screen.add_popup(popup)
        screen.focused = popup
        screen.prints.clear
        screen.invalidate(popup)
        screen.repaint
        assert_includes screen.prints, TTY::Cursor.move_to(99, 33)
        refute_includes screen.prints, TTY::Cursor.move_to(1, 1)
      end
    end

    context "handle_key (private)" do
      it "returns false when there is no content" do
        assert !screen.send(:handle_key, "x")
      end

      it "delegates to content when no popup is open" do
        screen.content = Component::Layout::Absolute.new
        handled = false
        screen.content.define_singleton_method(:handle_key) { |_|
          handled = true
          true
        }
        screen.send(:handle_key, "x")
        assert handled
      end
    end

    context "handle_mouse (private)" do
      it "delegates to content when no popups are open" do
        screen.content = Component::Layout::Absolute.new
        received = false
        screen.content.define_singleton_method(:handle_mouse) { |_| received = true }
        screen.send(:handle_mouse, MouseEvent.new(:left, 0, 0))
        assert received
      end

      it "does not delegate to content when popups are open and click is outside them" do
        screen.content = Component::Layout::Absolute.new
        received = false
        screen.content.define_singleton_method(:handle_mouse) { |_| received = true }
        screen.add_popup(PopupWindow.new)
        screen.send(:handle_mouse, MouseEvent.new(:left, 0, 0))
        assert !received
      end
    end

    context "popups" do
      it "adds popup" do
        w = PopupWindow.new
        screen.add_popup w
        assert screen.has_popup? w
      end

      it "close removes popup" do
        w = PopupWindow.new
        screen.add_popup w
        screen.remove_popup w
        assert !screen.has_popup?(w)
      end

      context "remove_popup focus repair" do
        it "falls back to the now-topmost popup when the closed popup held focus" do
          screen.content = Component::Layout::Absolute.new
          screen.content.add(Window.new)
          bottom = PopupWindow.new
          bottom.content = ["a"]
          screen.add_popup(bottom)
          top = PopupWindow.new
          top.content = ["b"]
          screen.add_popup(top)
          # focus is currently inside top (add_popup focused it)
          assert_equal top.content, screen.focused

          screen.remove_popup(top)
          assert_equal bottom.content, screen.focused
        end

        it "falls back to content when the only popup closes and held focus" do
          layout = Component::Layout::Absolute.new
          screen.content = layout
          w = Window.new
          layout.add(w)
          popup = PopupWindow.new
          popup.content = ["a"]
          screen.add_popup(popup)
          assert_equal popup.content, screen.focused

          screen.remove_popup(popup)
          # focus cascades down through layout → window → content
          assert_equal w.content, screen.focused
        end

        it "falls back to nil when the only popup closes with no content" do
          popup = PopupWindow.new
          popup.content = ["a"]
          screen.add_popup(popup)
          assert_equal popup.content, screen.focused

          screen.remove_popup(popup)
          assert_nil screen.focused
        end

        it "leaves focus untouched when the closed popup did not own focus" do
          layout = Component::Layout::Absolute.new
          screen.content = layout
          w = Window.new
          layout.add(w)
          popup = PopupWindow.new
          popup.content = ["a"]
          screen.add_popup(popup)
          screen.focused = w
          prior = screen.focused
          refute_nil prior

          screen.remove_popup(popup)
          assert_equal prior, screen.focused
        end

        it "leaves focus untouched when a non-topmost popup closes (focus is in the topmost)" do
          screen.content = Component::Layout::Absolute.new
          screen.content.add(Window.new)
          bottom = PopupWindow.new
          bottom.content = ["a"]
          screen.add_popup(bottom)
          top = PopupWindow.new
          top.content = ["b"]
          screen.add_popup(top)
          prior = screen.focused
          assert_equal top.content, prior

          screen.remove_popup(bottom)
          assert_equal prior, screen.focused
        end

        it "restores prior focus inside a sibling window instead of cascading to the first child" do
          # Reproduces the bug where opening a popup from window B (not the first
          # child) and pressing ESC moved focus to window A (the first child)
          # because the layout cascade picks the first activatable child.
          layout = Component::Layout::Absolute.new
          screen.content = layout
          first = Window.new
          second = Window.new
          layout.add(first)
          layout.add(second)
          screen.focused = second
          prior = screen.focused
          assert_equal second.content, prior

          popup = PopupWindow.new
          popup.content = ["a"]
          screen.add_popup(popup)
          assert_equal popup.content, screen.focused

          screen.remove_popup(popup)
          assert_equal prior, screen.focused
        end

        it "forwards a closed popup's prior focus to popups that pointed at it" do
          # bottom remembers vms-style focus; top remembers bottom's content.
          # If we close bottom (focus is in top, so focus is untouched), then
          # close top, focus should still climb back to the original owner —
          # not get stranded on a detached component and fall through to content.
          layout = Component::Layout::Absolute.new
          screen.content = layout
          first = Window.new
          second = Window.new
          layout.add(first)
          layout.add(second)
          screen.focused = second
          original = screen.focused

          bottom = PopupWindow.new
          bottom.content = ["a"]
          screen.add_popup(bottom)
          top = PopupWindow.new
          top.content = ["b"]
          screen.add_popup(top)

          # Close the non-topmost popup first; focus stays in top.
          screen.remove_popup(bottom)
          assert_equal top.content, screen.focused

          # Closing top should now restore the original focus (second.content),
          # not cascade to first.content.
          screen.remove_popup(top)
          assert_equal original, screen.focused
        end
      end

      context "event routing" do
        let(:popup) do
          w = PopupWindow.new("test")
          w.content = ["hello"]
          screen.add_popup(w)
          w
        end

        before do
          screen.content = Component::Layout::Absolute.new
          screen.content.add(Window.new)
        end

        def content_window = screen.content.children.first

        it "routes keyboard events to popup, not content" do
          popup_received = false
          popup.define_singleton_method(:handle_key) do |_key|
            popup_received = true
            true
          end
          content_received = false
          content_window.define_singleton_method(:handle_key) do |_key|
            content_received = true
            false
          end

          screen.send(:handle_key, "x")

          assert popup_received
          assert !content_received
        end

        it "routes mouse clicks inside popup to popup" do
          popup_received = false
          popup.define_singleton_method(:handle_mouse) { |_event| popup_received = true }
          content_received = false
          content_window.define_singleton_method(:handle_mouse) { |_event| content_received = true }

          # popup rect: left=75, top=23, width=9, height=3 (centered on 160x50);
          # (75,23) is the popup's top-left corner.
          screen.send(:handle_mouse, MouseEvent.new(:left, 75, 23))

          assert popup_received
          assert !content_received
        end

        it "does not route mouse clicks outside popup to content" do
          content_received = false
          content_window.define_singleton_method(:handle_mouse) { |_event| content_received = true }

          # click at (0,0) is outside the popup
          screen.send(:handle_mouse, MouseEvent.new(:left, 0, 0))

          assert !content_received
        end
      end
    end
  end
end
