# frozen_string_literal: true

# Bundler gem tasks provide:
# - rake build: Build the gem file (creates pg_sql_triggers-X.X.X.gem)
# - rake install: Build and install the gem locally
# - rake release: Build, tag, push to git, and publish to RubyGems.org
require "bundler/gem_tasks"

# Minimal Rails + engine task load so `bundle exec rake trigger:*` works from this repo
# (host apps load these via Rails::Engine#rake_tasks instead).
Dir[File.expand_path("rakelib/**/*.rake", __dir__)].each { |f| load f }
load File.expand_path("lib/tasks/trigger_migrations.rake", __dir__)

# RSpec tasks:
# - rake spec: Run the test suite
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Default task runs the test suite
task default: :spec
