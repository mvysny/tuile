# frozen_string_literal: true

module Tuile
  describe Component::LogWindow do
    before { Screen.fake }
    after { Screen.close }

    describe Component::LogWindow::IO do
      let(:window) { Component::LogWindow.new }
      let(:io) { Component::LogWindow::IO.new(window) }

      it "appends a line on #write, stripping the trailing newline" do
        io.write("hello\n")
        assert_equal "hello", window.content.text.to_s
      end

      it "appends a line on #puts" do
        io.puts("hello")
        assert_equal "hello", window.content.text.to_s
      end

      it "responds to #close as a no-op" do
        io.close
      end
    end

    describe "popup sizing advice" do
      # Screen.fake is 160x50.
      it "advises a popup to floor at half the screen height" do
        assert_equal 25, Component::LogWindow.new.popup_min_height
      end

      it "advises a popup to grow to the full screen height" do
        assert_equal 50, Component::LogWindow.new.popup_max_height
      end

      it "keeps a sparse log popup at half the screen even with few lines" do
        window = Component::LogWindow.new
        window.content.add_line("one")
        p = Component::Popup.new(content: window)
        assert_equal 25, p.rect.height
      end
    end
  end
end
