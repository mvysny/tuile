# frozen_string_literal: true

require "English"
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

desc "Run the display-width / repaint micro-benchmarks."
task :benchmark do
  ruby "-Ilib", "benchmark/display_width.rb"
end

namespace :sig do
  desc "Regenerate sig/tuile.rbs from YARD docs via sord. Fails if sord emits any warnings."
  task :generate do
    rm_rf ".yardoc"
    out = `bundle exec sord gen sig/tuile.rbs --rbs --regenerate 2>&1`
    print out
    raise "sord exited non-zero" unless $CHILD_STATUS.success?

    offenders = out.lines.grep(/^\[(OMIT|INFER|WARN|ERROR)/)
    raise "sord emitted #{offenders.size} warning(s); see output above" unless offenders.empty?
  end

  desc "Validate sig/tuile.rbs with the stdlib types tuile depends on."
  task :validate do
    sh "bundle exec rbs -r logger -r singleton -I sig validate"
  end
end

desc "Regenerate sig/tuile.rbs and validate it."
task sig: %w[sig:generate sig:validate]

desc "Full pre-release check suite: tests, lint, signature drift."
task check: %i[spec rubocop sig]

namespace :release do
  # Release-only metadata guards. Kept out of `check` so routine
  # `rake`/`rake check` during development — when Tuile::VERSION still
  # points at the last release and its next CHANGELOG entry isn't written
  # yet — don't fail.
  desc "Verify Tuile::VERSION has a dated CHANGELOG entry and isn't already tagged."
  task :guard_version do
    version = Bundler::GemHelper.gemspec.version.to_s
    tag = "v#{version}"

    # A dated '## [x.y.z] - YYYY-MM-DD' heading: the \d date both proves the
    # section exists and rejects the literal YYYY-MM-DD placeholder.
    unless File.read("CHANGELOG.md").match?(/^## \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}/)
      abort "CHANGELOG.md has no dated '## [#{version}] - YYYY-MM-DD' section. " \
            "Move the Unreleased entries under a dated heading for #{version} first."
    end

    # Pre-empts bundler's already_tagged? path, which would silently skip
    # tagging and then fail late on a duplicate `gem push`.
    if system("git", "rev-parse", "-q", "--verify", "refs/tags/#{tag}", out: File::NULL, err: File::NULL)
      abort "Tag #{tag} already exists — #{version} has been released. Bump Tuile::VERSION first."
    end
  end
end

# Gate `rake release`. guard_clean is the first release-only sub-task (build
# runs before it, but build is cheap and pkg/ is disposable), so the gate
# runs before any tag or push. Order: guard_version first (cheap metadata
# checks, fail fast) then check (the spec suite). A `sig` run that
# regenerates sig/tuile.rbs leaves the tree dirty, which guard_clean itself
# then catches — so signature drift fails the release without extra wiring.
task "release:guard_clean" => %w[release:guard_version check]

task default: :check
