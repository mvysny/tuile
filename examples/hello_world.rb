#!/usr/bin/env ruby
# frozen_string_literal: true

# Tuile hello-world. A Window wrapping a Label.
#
# Run from the gem root:
#   bundle exec ruby -Ilib examples/hello_world.rb
#
# Press q or ESC to exit.

require "tuile"

# Screen must exist before any Component is built: components reach for
# Tuile::Screen.instance during invalidate/repaint hooks.
screen = Tuile::Screen.new

label = Tuile::Component::Label.new
label.text = "Hello, world!"

window = Tuile::Component::Window.new("Tuile")
window.content = label

screen.content = window
window.focus
begin
  screen.run_event_loop
ensure
  screen.close
end
