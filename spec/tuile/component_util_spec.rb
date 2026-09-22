# frozen_string_literal: true

module Tuile
  describe ComponentUtil do
    before { Screen.fake }
    after { Screen.close }

    describe "#effectively_visible?" do
      # A field inside a panel, the pair mounted on the screen.
      def field_in_panel(mount: true)
        panel = Component::Layout::Vertical.new
        field = Component::TextField.new
        panel.add(field, Component::Layout::Fixed[1])
        mount_at(panel, Rect.new(0, 0, 20, 5)) if mount
        [panel, field]
      end

      it "is true for an attached component nothing hides" do
        _panel, field = field_in_panel
        assert ComponentUtil.effectively_visible?(field)
      end

      it "is false once the component itself is hidden" do
        _panel, field = field_in_panel
        field.visible = false
        refute ComponentUtil.effectively_visible?(field)
      end

      # The whole reason the predicate exists: the field's own flag still reads
      # visible, so a bare `visible?` test answers the wrong question.
      it "is false under a hidden ancestor, which still reports visible? itself" do
        panel, field = field_in_panel
        panel.visible = false
        assert field.visible?
        refute ComponentUtil.effectively_visible?(field)
      end

      it "is false for a tree with no screen" do
        _panel, field = field_in_panel(mount: false)
        refute ComponentUtil.effectively_visible?(field)
      end

      it "raises on nil rather than answering 'not visible'" do
        assert_raises(TypeError) { ComponentUtil.effectively_visible?(nil) }
      end
    end
  end
end
