# frozen_string_literal: true

module Tuile
  class Component
    # A {Window} with a read-only body, in one of two presentations:
    # **prose** ({#message=}) wraps in a scrollable {TextView}, **rows**
    # ({#lines=}) stay one per row in a {List}, truncating instead of
    # wrapping — the presentation for columnar output, where a wrap would
    # destroy the alignment. Usable tiled (add it to a {Layout}) or as a
    # popup via {.open}; the constructor and {.open} pick the presentation
    # from the body's type:
    #
    #   Component::InfoWindow.open("Help", "A long explanation, wrapped to fit.")
    #   Component::InfoWindow.open("Files", ["drwx  src/", "-rw-  README.md"])
    #
    # Both write the same body slot — the last writer wins.
    class InfoWindow < Window
      # @param caption [String, StyledString, nil] the border title.
      # @param body [String, StyledString, Component, Array, nil] an `Array`
      #   is assigned through {#lines=}, anything else through {#message=}.
      def initialize(caption = "", body = nil)
        @message = nil
        super(caption)
        if body.is_a?(Array)
          self.lines = body
        else
          self.message = body
        end
      end

      # @return [String, StyledString, Component, nil] whatever {#message=}
      #   was given — set a `String`, read that `String` back. After
      #   {#lines=} it is the {List} that setter mounted.
      attr_reader :message

      # Sets the prose body. Text (`String` / {StyledString}) is rendered by
      # a word-wrapping, scrollable {TextView} the window owns; a {Component}
      # is mounted as-is. `nil` clears.
      # @param value [String, StyledString, Component, nil]
      # @raise [TypeError] on any other type.
      # @return [void]
      def message=(value)
        occupant =
          case value
          when nil then nil
          when Component then value
          when String, StyledString then TextView.new.tap { _1.text = value }
          else raise TypeError, "expected String, StyledString, Component or nil, got #{value.inspect}"
          end
        @message = value
        self.content = occupant
      end

      # Sets the rows body: a {List} populated via {List#lines=} (so entries
      # are coerced, `\n`-split and rstripped exactly as there), one item per
      # row, long rows truncated — never wrapped. For prose use {#message=}.
      # @param lines [Array] entries are `String`, `StyledString`, or anything
      #   that responds to `#to_s`.
      # @raise [TypeError] unless an `Array`.
      # @return [void]
      def lines=(lines)
        list = List.new
        list.lines = lines
        self.message = list
      end

      # Opens the info window as a popup.
      # @param caption [String, StyledString, nil] the border title.
      # @param body [String, StyledString, Component, Array, nil] dispatched
      #   by type as in {#initialize}.
      # @param declared_size [Size, Fraction] the popup's box, applied
      #   top-down; the body wraps or scrolls within it. Defaults to
      #   {Fraction::HALF}.
      # @return [Popup] the opened popup.
      def self.open(caption, body = nil, declared_size: Fraction::HALF)
        Popup.new(content: InfoWindow.new(caption, body), declared_size: declared_size).open
      end
    end
  end
end
