# frozen_string_literal: true

module Tuile
  class Component
    # A {Window} preconfigured with a {List} of static lines. Useful for
    # showing read-only information.
    #
    # Usable tiled (just add to a {Layout}) or as a popup via {.open}, which
    # wraps it in a {Popup}.
    class InfoWindow < Window
      # @param caption [String]
      # @param lines [Array<String>] initial content; each entry may contain
      #   Rainbow formatting.
      def initialize(caption = "", lines = [])
        super(caption)
        list = Component::List.new
        list.lines = lines
        self.content = list
      end

      # Opens the info window as a popup.
      # @param caption [String]
      # @param lines [Array<String>] the content, may contain formatting.
      # @param size [Size, Fraction] the popup's size, applied top-down; the
      #   list wraps and scrolls within it. Defaults to {Fraction::HALF}.
      # @return [Popup] the opened popup.
      def self.open(caption, lines, size: Fraction::HALF)
        Popup.open(content: InfoWindow.new(caption, lines), size: size)
      end
    end
  end
end
