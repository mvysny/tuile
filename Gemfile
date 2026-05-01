# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in tuile.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.2"

group :test do
  gem "minitest", "~> 5.26"
  gem "rspec-core", "~> 3.13"
  gem "timecop", "~> 0.9"
end

group :development do
  gem "redcarpet", "~> 3.6" # Markdown formatting for YARD
  gem "rubocop", "~> 1.21"
  gem "yard", "~> 0.9.37"
end
