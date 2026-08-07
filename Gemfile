# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in tuile.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.2"

group :test do
  # Tuile's one optional runtime dep (Component::BigDecimalField), kept out of
  # the gemspec so only apps using that component pay for it — but the specs
  # and examples/sampler.rb do use it.
  gem "bigdecimal", ">= 3.1"
  gem "minitest", "~> 6.0"
  gem "rainbow", "~> 3.1" # Rainbow.uncolor in specs; styling in examples/
  gem "rspec-core", "~> 3.13"
  gem "simplecov", "~> 0.22", require: false
  gem "timecop", "~> 0.9"
end

group :development do
  gem "redcarpet", "~> 3.6" # Markdown formatting for YARD
  gem "rubocop", "~> 1.21"
  gem "sord", "~> 7.1"
  gem "yard", "~> 0.9.37"
end
