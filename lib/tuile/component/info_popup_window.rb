# frozen_string_literal: true

module Tuile
  class Component
    # Shows a bunch of lines as a helpful info. Call {.open} to quickly open the
    # window.
    class InfoPopupWindow < PopupWindow
      # Opens the info window.
      # @param caption [String]
      # @param lines [Array<String>] the content, may contain formatting.
      # @return [void]
      def self.open(caption, lines)
        w = InfoPopupWindow.new(caption)
        list = Component::List.new
        list.content = lines
        w.content = list
        w.open
      end
    end
  end
end
