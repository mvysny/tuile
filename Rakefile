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

task default: %i[spec sig]
