# frozen_string_literal: true

# Provides :environment for engine tasks when developing the gem (see Rakefile).
# rubocop:disable Rails/RakeEnvironment -- this task *is* the Rails environment for gem dev
task :environment do
  require_relative "../lib/pg_sql_triggers/rake_development_boot"
  PgSqlTriggers::RakeDevelopmentBoot.boot!
end
# rubocop:enable Rails/RakeEnvironment
