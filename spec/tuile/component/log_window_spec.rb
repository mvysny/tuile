# frozen_string_literal: true

module Tuile
  describe Component::LogWindow do
    before { Screen.fake }
    after { Screen.close }

    let(:window) { Component::LogWindow.new }

    it "frames a LogTextView" do
      assert_kind_of Component::LogTextView, window.content
    end

    it "delegates #log to the view" do
      window.log("hello")
      assert_equal "hello", window.content.text.to_s
    end

    it "keeps LogWindow::IO as an alias that accepts the window itself" do
      io = Component::LogWindow::IO.new(window)
      io.write("hello\n")
      assert_equal "hello", window.content.text.to_s
    end
  end
end
