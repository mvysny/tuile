# frozen_string_literal: true

module Tuile
  describe Component::LogTextView do
    before { Screen.fake }
    after { Screen.close }

    let(:view) { Component::LogTextView.new }

    it "has auto_scroll enabled" do
      assert view.auto_scroll
    end

    it "has scrollbar visible" do
      assert_equal :visible, view.scrollbar_visibility
    end

    describe "#log" do
      it "appends the line" do
        view.log("hello")
        view.log("world")
        assert_equal "hello\nworld", view.text.to_s
      end

      it "does nothing when passed nil" do
        view.log(nil)
        assert_equal "", view.text.to_s
      end
    end

    describe Component::LogTextView::IO do
      let(:io) { Component::LogTextView::IO.new(view) }

      it "appends a line on #write, stripping the trailing newline" do
        io.write("hello\n")
        assert_equal "hello", view.text.to_s
      end

      it "appends a line on #puts" do
        io.puts("hello")
        assert_equal "hello", view.text.to_s
      end

      it "responds to #close as a no-op" do
        io.close
      end

      it "routes stdlib Logger lines into the view" do
        log = Logger.new(io)
        log.formatter = ->(severity, _time, _progname, msg) { "#{severity}: #{msg}\n" }
        log.error "foo"
        log.warn "bar"
        assert_equal "ERROR: foo\nWARN: bar", view.text.to_s
      end
    end
  end
end
