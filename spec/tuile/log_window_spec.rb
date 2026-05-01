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
        assert_equal ["hello"], window.content.content
      end

      it "appends a line on #puts" do
        io.puts("hello")
        assert_equal ["hello"], window.content.content
      end

      it "responds to #close as a no-op" do
        io.close
      end
    end
  end
end
