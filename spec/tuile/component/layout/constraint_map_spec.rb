# frozen_string_literal: true

module Tuile
  describe Component::Layout::ConstraintMap do
    before { Screen.fake }
    after { Screen.close }

    let(:layout) { Component::Layout.new }
    let(:constraints) { layout.send(:constraints) }
    let(:child) { Component.new.tap { layout.add(_1) } }

    it "answers nil for a child never constrained, and fetch raises" do
      assert_nil constraints[child]
      assert_raises(KeyError) { constraints.fetch(child) }
    end

    it "is built once, on first read" do
      assert_same constraints, layout.send(:constraints)
    end

    it "marks the layout on a write" do
      child
      layout.flush_layout
      constraints[child] = Rect.new(0, 0, 1, 1)
      assert layout.layout_dirty?
      assert_equal Rect.new(0, 0, 1, 1), constraints.fetch(child)
    end

    it "marks nothing when the entry is unchanged" do
      constraints[child] = Rect.new(0, 0, 1, 1)
      layout.flush_layout
      constraints[child] = Rect.new(0, 0, 1, 1)
      refute layout.layout_dirty?
    end

    it "refuses a component that is not a child" do
      assert_raises(ArgumentError) { constraints[Component.new] = Rect.new(0, 0, 1, 1) }
    end

    it "keys by identity, so two == children are two entries" do
      twin = Class.new(Component) do
        def ==(other) = other.is_a?(self.class)
        alias_method :eql?, :==
        def hash = 0
      end
      a = twin.new.tap { layout.add(_1) }
      b = twin.new.tap { layout.add(_1) }
      constraints[a] = :a
      constraints[b] = :b
      assert_equal %i[a b], [constraints[a], constraints[b]]
    end

    it "is forgotten by Layout#remove, so a re-added child starts over" do
      constraints[child] = :x
      layout.remove(child)
      layout.add(child)
      assert_nil constraints[child]
    end

    it "survives hiding" do
      constraints[child] = :x
      child.visible = false
      assert_equal :x, constraints[child]
    end

    # children stays the sole ordering authority (AGENTS.md, the tree).
    it "cannot be enumerated" do
      %i[each keys values size to_a].each { refute_respond_to constraints, _1 }
    end
  end
end
