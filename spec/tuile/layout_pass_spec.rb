# frozen_string_literal: true

module Tuile
  describe LayoutPass do
    # A child in a layout, both screen-free — a pass needs no Screen.
    def parent_and_child
      parent = Component::Layout::Absolute.new
      child = Component::Label.new("x")
      parent.add(child, Rect.new(0, 0, 4, 1))
      [parent, child]
    end

    describe "#check" do
      it "passes while the child's own placer is the one running" do
        parent, child = parent_and_child
        LayoutPass.run(parent) { LayoutPass.check(child) }
      end

      it "refuses outside any pass, naming the parent to constrain instead" do
        _parent, child = parent_and_child
        e = assert_raises(Tuile::Error) { LayoutPass.check(child) }
        assert_includes e.message, "Absolute#constrain"
      end

      it "refuses while a different component is placing" do
        parent, child = parent_and_child
        other = Component::Layout::Absolute.new
        assert_raises(Tuile::Error) { LayoutPass.run(other) { LayoutPass.check(child) } }
        LayoutPass.run(parent) { LayoutPass.check(child) } # …and the same one still passes
      end

      it "points a parentless component at Layout::Absolute instead" do
        e = assert_raises(Tuile::Error) { LayoutPass.check(Component::Label.new("x")) }
        assert_includes e.message, "no parent to place it"
      end
    end

    describe "#run" do
      it "restores the enclosing pass, so a nested one does not end the outer" do
        outer, child = parent_and_child
        inner, inner_child = parent_and_child
        LayoutPass.run(outer) do
          LayoutPass.run(inner) { LayoutPass.check(inner_child) }
          LayoutPass.check(child) # the outer pass is still in force
        end
      end

      it "restores it after a raise, so one bad pass doesn't strand the flag" do
        parent, child = parent_and_child
        assert_raises(RuntimeError) { LayoutPass.run(parent) { raise "boom" } }
        assert_raises(Tuile::Error) { LayoutPass.check(child) }
      end

      it "answers the block's value" do
        assert_equal 42, LayoutPass.run(Component::Layout::Absolute.new) { 42 }
      end
    end

    describe "#before_first_placement?" do
      it "is true only inside the component's own pass, until it places" do
        parent, _child = parent_and_child
        refute LayoutPass.before_first_placement?(parent)
        LayoutPass.run(parent) do
          assert LayoutPass.before_first_placement?(parent)
          LayoutPass.note_placement
          refute LayoutPass.before_first_placement?(parent)
        end
      end

      it "is false for anyone but the running placer" do
        parent, child = parent_and_child
        LayoutPass.run(parent) { refute LayoutPass.before_first_placement?(child) }
      end
    end
  end
end
