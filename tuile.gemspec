# frozen_string_literal: true

require_relative "lib/tuile/version"

Gem::Specification.new do |spec|
  spec.name = "tuile"
  spec.version = Tuile::VERSION
  spec.authors = ["Martin Vysny"]
  spec.email = ["martin@vysny.me"]

  spec.summary = "A component-oriented terminal UI toolkit for Ruby."
  spec.description = <<~DESC
    Tuile is a small TUI framework built on top of the TTY toolkit. It models
    the terminal as a tree of components (windows, lists, text fields, popups)
    with an invalidation-based repaint model and a single-threaded event queue,
    so apps don't have to think about locking. The name is French for "roof
    tile" — a small piece that composes into a larger whole.
  DESC
  spec.homepage = "https://github.com/mvysny/tuile"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.3"
  spec.add_dependency "logger", "~> 1.7"
  spec.add_dependency "rainbow", "~> 3.1"
  spec.add_dependency "strings-truncation", "~> 0.1"
  spec.add_dependency "tty-box", "~> 0.7"
  spec.add_dependency "tty-cursor", "~> 0.7"
  spec.add_dependency "tty-screen", "~> 0.8"
  spec.add_dependency "unicode-display_width", ">= 2.6", "< 4.0"
  spec.add_dependency "zeitwerk", "~> 2.7"
end
