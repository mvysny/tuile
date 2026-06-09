# frozen_string_literal: true

require "English"
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

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

# Gate `rake release` on the check suite. guard_clean is the first
# release-only sub-task (build runs before it, but build is cheap and pkg/
# is disposable), so the checks run before any tag or push. A `sig` run that
# regenerates sig/tuile.rbs leaves the tree dirty, which guard_clean then
# catches — so signature drift fails the release without extra wiring.
task "release:guard_clean" => :check

task default: :check
