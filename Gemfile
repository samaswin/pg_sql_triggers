# frozen_string_literal: true

source "https://rubygems.org"

# Allow Rails version to be overridden via RAILS_VERSION env var for CI
# This must come before gemspec to override the Rails dependency
if ENV["RAILS_VERSION"]
  rails_version = ENV["RAILS_VERSION"]
  gem "rails", "~> #{rails_version}.0"
end

# Specify your gem's dependencies in pg_sql_triggers.gemspec
gemspec

gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"
