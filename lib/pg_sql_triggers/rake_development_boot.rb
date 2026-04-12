# frozen_string_literal: true

require "rails"
require "active_record"
require "logger"

# Minimal Rails app for running engine Rake tasks from the gem repo (see +rakelib/+).
module PgSqlTriggersRakeDevApp
  class Application < ::Rails::Application
    config.root = Pathname.new(Dir.pwd)
    config.eager_load = false
    config.active_support.deprecation = :stderr
    config.secret_key_base = "rake_dev_secret_for_pg_sql_triggers_gem"
    config.logger = Logger.new($stdout, level: Logger::ERROR)
  end
end

# Boots a minimal Rails app and ActiveRecord so engine +lib/tasks+ Rake tasks work when
# +bundle exec rake trigger:*+ is run from the gem repository (no host application).
module PgSqlTriggers
  module RakeDevelopmentBoot
    module_function

    def boot!
      return if @booted

      ENV["RAILS_ENV"] ||= "development"

      require_relative "../pg_sql_triggers"

      unless Rails.application
        PgSqlTriggersRakeDevApp::Application.config.paths["app/views"] <<
          PgSqlTriggers::Engine.root.join("app/views").to_s
        PgSqlTriggersRakeDevApp::Application.initialize!
      end

      establish_connection_from_env!
      load_engine_models
      @booted = true
    end

    def establish_connection_from_env!
      return if ::ActiveRecord::Base.connected?

      test_db_config = ENV["DATABASE_URL"] || {
        adapter: "postgresql",
        database: ENV["TEST_DATABASE"] || "pg_sql_triggers_test",
        username: ENV["TEST_DB_USER"] || "postgres",
        password: ENV["TEST_DB_PASSWORD"] || "",
        host: ENV["TEST_DB_HOST"] || "localhost"
      }

      ::ActiveRecord::Base.establish_connection(test_db_config)
      ::ActiveRecord::Base.connection
    rescue StandardError => e
      warn "PgSqlTriggers: could not connect to PostgreSQL for Rake tasks: #{e.message}"
      raise
    end

    def load_engine_models
      engine_root = PgSqlTriggers::Engine.root
      Dir[engine_root.join("app/models/**/*.rb")].each { |f| require f }
    end
  end
end
