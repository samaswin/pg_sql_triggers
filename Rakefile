# frozen_string_literal: true

# Bundler gem tasks provide:
# - rake build: Build the gem file (creates pg_sql_triggers-X.X.X.gem)
# - rake install: Build and install the gem locally
# - rake release: Build, tag, push to git, and publish to RubyGems.org
require "bundler/gem_tasks"

# RSpec tasks:
# - rake spec: Run the test suite
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Default task runs the test suite
task default: :spec
