# frozen_string_literal: true

module Tuile
  describe Component::LogDialog do
    before { Screen.fake }
    after { Screen.close }

    let(:window) { Component::LogDialog.new }

    it "frames a LogTextView" do
      assert_kind_of Component::LogTextView, window.content
    end

    it "delegates #log to the view" do
      window.log("hello")
      Testing.loop
      assert_equal "hello", window.content.text.to_s
    end

    it "keeps LogDialog::IO as an alias that accepts the window itself" do
      io = Component::LogDialog::IO.new(window)
      io.write("hello\n")
      Testing.loop
      assert_equal "hello", window.content.text.to_s
    end
  end
end
