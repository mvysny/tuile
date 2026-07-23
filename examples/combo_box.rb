#!/usr/bin/env ruby
# frozen_string_literal: true

# Tuile ComboBox demo: a filtering dropdown whose value is the *selected item*.
#
# Run from the gem root:
#   bundle exec ruby -Ilib examples/combo_box.rb
#
# Type to filter, ↑/↓ to move the highlight, Enter to accept. ESC dismisses the
# dropdown; pressing ESC again (field empty of focus) then q quits.

require "tuile"

# Screen must exist before any Component is built.
screen = Tuile::Screen.new

languages = %w[Ruby Python JavaScript TypeScript Rust Go Elixir Crystal Haskell Kotlin Swift Zig]
combo = Tuile::Component::ComboBox.new(items: languages)

status = Tuile::Component::Label.new("Pick a language — type to filter, ↑↓ to move, Enter to accept.")
combo.on_value_change = ->(value) { status.text = "Selected: #{value}" }

# Stacks the prompt and the combo a couple of rows apart inside the window.
class Form < Tuile::Component::Layout::Absolute
  def initialize(status, combo)
    super()
    @status = status
    @combo = combo
    add([status, combo])
  end

  def rect=(rect)
    super
    @status.rect = Tuile::Rect.new(rect.left + 2, rect.top + 1, [rect.width - 4, 0].max, 1)
    @combo.rect = Tuile::Rect.new(rect.left + 2, rect.top + 3, [rect.width - 4, 24].min, 1)
  end
end

window = Tuile::Component::Window.new("Languages")
window.content = Form.new(status, combo)

screen.content = window
combo.focus
begin
  screen.run_event_loop
ensure
  screen.close
end
