# frozen_string_literal: true

module Tuile
  RSpec.describe Event do
    it "mandates no members" do
      assert_empty described_class.instance_methods(false)
    end

    it "matches a mouse event, parsed off the wire" do
      assert_kind_of described_class, Mouse.parse("\e[<0;1;1M")
    end

    it "matches every mouse event class" do
      %i[DownEvent UpEvent ScrollEvent MoveEvent DragEvent].each do |name|
        assert_includes Mouse.const_get(name).ancestors, described_class, name
      end
    end

    it "matches every queue event class" do
      %i[KeyEvent PasteEvent ErrorEvent TTYSizeEvent ColorSchemeEvent BackgroundColorEvent
         EmptyQueueEvent].each do |name|
        assert_includes EventQueue.const_get(name).ancestors, described_class, name
      end
    end

    it "lets a case match one class or the whole family" do
      matched = case Mouse.parse("\e[<0;1;1M")
                when Mouse::UpEvent then :up
                when described_class then :some_event
                end
      assert_equal :some_event, matched
    end
  end
end
