# frozen_string_literal: true

module Tuile
  class Component
    # A {Window} preconfigured with a {List} of static lines. Useful for
    # showing read-only information.
    #
    # Usable tiled (just add to a {Layout}) or as a popup via {.open}, which
    # wraps it in a {Popup}.
    class InfoPopupWindow < Window
      # @param caption [String]
      # @param lines [Array<String>] initial content; each entry may contain
      #   Rainbow formatting.
      def initialize(caption = "", lines = [])
        super(caption)
        list = Component::List.new
        list.content = lines
        self.content = list
      end

      # Opens the info window as a popup.
      # @param caption [String]
      # @param lines [Array<String>] the content, may contain formatting.
      # @return [Popup] the opened popup.
      def self.open(caption, lines)
        Popup.new(content: InfoPopupWindow.new(caption, lines)).tap(&:open)
      end
    end
  end
end
