# frozen_string_literal: true

module Tuile
  describe Component::FormLayout do
    before { Screen.fake }
    after { Screen.close }

    let(:form) { Component::FormLayout.new }
    let(:username) { Component::TextField.new }
    let(:notes) { Component::TextArea.new }

    # Mounts the form and gives it `height` rows, 20 columns wide.
    # @param height [Integer]
    # @return [Component::FormLayout] `form`.
    def mount(height: 12)
      Screen.instance.content = form
      form.rect = Rect.new(0, 0, 20, height)
      form
    end

    # @param height [Integer]
    # @return [Array<String>] the mounted region, painted, one string per row.
    def painted(height = 12)
      Screen.instance.repaint
      Screen.instance.buffer.region_text(Rect.new(0, 0, 20, height))
    end

    context "add" do
      it "wraps the field and returns the item it built" do
        item = form.add(username, caption: "Username")
        assert_instance_of Component::FormItem, item
        assert_equal username, item.content
        assert_equal "Username", item.caption.to_s
        assert_equal [item], form.children
      end

      it "keeps children homogeneous, captioned or not" do
        form.add(username, caption: "Username")
        form.add(Component::Button.new("Save"))
        assert_equal [Component::FormItem, Component::FormItem], form.children.map(&:class)
      end

      it "adopts a ready-made item rather than wrapping it twice" do
        item = Component::FormItem.new(username, caption: "Username")
        assert_equal item, form.add(item)
        assert_equal [item], form.children
      end

      it "refuses chrome arguments alongside a ready-made item" do
        item = Component::FormItem.new(username)
        assert_raises(ArgumentError) { form.add(item, caption: "Username") }
        assert_raises(ArgumentError) { form.add(item, required: true) }
      end

      it "inserts at an index, which is paint and Tab order" do
        second = form.add(username, caption: "Username")
        first = form.add(notes, caption: "Notes", at: 0)
        assert_equal [first, second], form.children
      end

      it "refuses a field that is not a Component, and rows below one" do
        assert_raises(TypeError) { form.add("username", caption: "Username") }
        assert_raises(ArgumentError) { form.add(username, caption: "Username", rows: 0) }
        assert_raises(ArgumentError) { form.add(username, caption: "Username", rows: 1.5) }
      end

      it "inherits the item's refusal of a required field with no caption" do
        assert_raises(ArgumentError) { form.add(username, required: true) }
      end
    end

    context "geometry" do
      it "gives a captioned item its caption row, its content rows and the fused gap" do
        item = form.add(username, caption: "Username")
        mount
        assert_equal Rect.new(0, 0, 20, 3), item.rect
        assert_equal Rect.new(0, 1, 20, 1), username.rect
      end

      it "costs a captionless item one row less, with no caption row reserved" do
        item = form.add(Component::Button.new("Save"))
        mount
        assert_equal Rect.new(0, 0, 20, 2), item.rect
      end

      it "spends rows: on the content alone" do
        item = form.add(notes, caption: "Notes", rows: 5)
        mount
        assert_equal Rect.new(0, 0, 20, 7), item.rect
        assert_equal Rect.new(0, 1, 20, 5), notes.rect
      end

      it "stacks items with no gap of its own — the message row is the gap" do
        first = form.add(username, caption: "Username")
        second = form.add(notes, caption: "Notes", rows: 2)
        third = form.add(Component::Button.new("Save"))
        mount
        assert_equal Rect.new(0, 0, 20, 3), first.rect
        assert_equal Rect.new(0, 3, 20, 4), second.rect
        assert_equal Rect.new(0, 7, 20, 2), third.rect
      end

      it "paints the caption above the field, over the form's full width" do
        form.add(username, caption: "Username")
        mount
        username.text = "admin"
        assert_equal "Username            ", painted[0]
        assert_equal "admin               ", painted[1]
      end

      it "re-runs the pass when the form is resized" do
        item = form.add(username, caption: "Username")
        mount
        form.rect = Rect.new(2, 1, 30, 12)
        assert_equal Rect.new(2, 1, 30, 3), item.rect
      end
    end

    context "overflow" do
      it "clips the item straddling the bottom edge to the rows that are left" do
        form.add(username, caption: "Username")
        item = form.add(notes, caption: "Notes", rows: 3)
        mount(height: 6)
        assert_equal Rect.new(0, 3, 20, 3), item.rect
        refute notes.rect.empty?, "a FormItem serves its content first"
      end

      it "gives every item past the bottom an empty rect, never a stale one" do
        item = form.add(username, caption: "Username")
        mount
        overflowing = form.add(notes, caption: "Notes", rows: 20)
        assert_equal Rect.new(0, 3, 20, 9), overflowing.rect
        past = form.add(Component::Button.new("Save"))
        assert past.rect.empty?
        refute item.rect.empty?
      end

      it "assigns every item a rect even when its own is empty" do
        form.add(username, caption: "Username")
        form.add(Component::Button.new("Save"))
        mount
        form.rect = Rect.new(0, 0, 0, 0)
        assert(form.children.all? { _1.rect.empty? })
      end
    end

    context "visibility" do
      it "reclaims a hidden item's rows and its gap" do
        hidden = form.add(username, caption: "Username")
        below = form.add(Component::Button.new("Save"))
        mount
        hidden.visible = false
        assert hidden.rect.empty?
        assert_equal Rect.new(0, 0, 20, 2), below.rect
      end

      it "gives them back when it returns" do
        hidden = form.add(username, caption: "Username")
        below = form.add(Component::Button.new("Save"))
        mount
        hidden.visible = false
        hidden.visible = true
        assert_equal Rect.new(0, 0, 20, 3), hidden.rect
        assert_equal Rect.new(0, 3, 20, 2), below.rect
      end
    end

    context "remove and constrain" do
      it "takes the field it was handed, or the item around it" do
        item = form.add(username, caption: "Username")
        form.remove(username)
        assert_empty form.children
        assert_nil item.parent
      end

      it "closes the rows the removed item left" do
        form.add(username, caption: "Username")
        below = form.add(Component::Button.new("Save"))
        mount
        form.remove(username)
        assert_equal Rect.new(0, 0, 20, 2), below.rect
      end

      it "leaves the field in its item, so the item is what goes back" do
        item = form.add(notes, caption: "Notes", rows: 5)
        form.remove(notes)
        assert_equal notes, item.content
        assert_equal item, form.add(item)
      end

      it "forgets the placement, so a re-added item starts from the default" do
        item = form.add(notes, caption: "Notes", rows: 5)
        form.remove(item)
        form.add(item)
        mount
        assert_equal Rect.new(0, 0, 20, 3), item.rect
      end

      it "re-sizes a field's content rows in place" do
        item = form.add(notes, caption: "Notes")
        mount
        form.constrain(notes, 4)
        assert_equal Rect.new(0, 0, 20, 6), item.rect
        assert_equal Rect.new(0, 1, 20, 4), notes.rect
        assert_equal item, form.children.first, "the item, and its subscriptions, survive"
      end

      it "refuses a field that is in no item of this form" do
        form.add(username, caption: "Username")
        assert_raises(ArgumentError) { form.remove(notes) }
        assert_raises(ArgumentError) { form.constrain(notes, 4) }
        assert_raises(ArgumentError) { form.constrain(username, 0) }
      end
    end

    context "field_for" do
      it "answers the field under a caption" do
        form.add(username, caption: "Username")
        form.add(notes, caption: "Notes")
        assert_equal notes, form.field_for(caption: "Notes")
      end

      it "answers nil when nothing matches" do
        form.add(username, caption: "Username")
        assert_nil form.field_for(caption: "Password")
      end
    end

    context "focus" do
      it "forwards focus to the first field, not to an item" do
        form.add(username, caption: "Username")
        form.add(notes, caption: "Notes")
        mount
        Screen.instance.focused = form
        assert_equal username, Screen.instance.focused
      end
    end

    context "the message row" do
      it "is the item's to paint — the form never touches error_message" do
        form.add(username, caption: "Username")
        mount
        username.error_message = "Must not be blank"
        assert_equal "Must not be blank   ", painted[2]
      end
    end
  end
end
