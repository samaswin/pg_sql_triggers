# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
  minimum_coverage 90
end

ENV["RAILS_ENV"] ||= "test"

# Set up minimal Rails environment for testing
require "rails"
require "active_record"
require "action_controller"
require "action_view"
require "active_support/testing/time_helpers"
require "rspec/rails"
require "rails-controller-testing"

# Load the engine first
require "pg_sql_triggers"

# Initialize a minimal Rails application for engine testing
unless Rails.application
  # Create a minimal Rails application
  module TestApp
    class Application < Rails::Application
      config.root = Pathname.new(Dir.pwd)
      config.eager_load = false
      config.active_support.deprecation = :stderr
      config.secret_key_base = "test_secret_key_base"
      config.logger = Logger.new(STDOUT)
      config.log_level = :error
    end
  end
  
  TestApp::Application.initialize!
end

# Manually load app files since we're not in a full Rails environment
engine_root = Pathname.new(File.expand_path("..", __dir__))
Dir[engine_root.join("app/models/**/*.rb")].each { |f| require f }
Dir[engine_root.join("app/controllers/**/*.rb")].each { |f| require f }

# Configure database
test_db_config = {
  adapter: "postgresql",
  database: ENV["TEST_DATABASE"] || "pg_sql_triggers_test",
  username: ENV["TEST_DB_USER"] || "postgres",
  password: ENV["TEST_DB_PASSWORD"] || "",
  host: ENV["TEST_DB_HOST"] || "localhost"
}

# Try to connect, create database if it doesn't exist
begin
  # First, try to connect to postgres to check if test database exists
  admin_config = test_db_config.merge(database: "postgres")
  ActiveRecord::Base.establish_connection(admin_config)
  conn = ActiveRecord::Base.connection
  
  # Check if database exists
  db_exists = conn.execute("SELECT 1 FROM pg_database WHERE datname = '#{test_db_config[:database]}'").any?
  
  unless db_exists
    conn.create_database(test_db_config[:database])
  end
  
  # Now connect to the test database
  ActiveRecord::Base.establish_connection(test_db_config)
  ActiveRecord::Base.connection
rescue => e
  # If we can't connect to postgres, try direct connection (database might already exist)
  begin
    ActiveRecord::Base.establish_connection(test_db_config)
    ActiveRecord::Base.connection
  rescue => e2
        puts "Warning: Could not create test database. Please create it manually:"
        puts "  createdb #{test_db_config[:database]}"
        raise e2
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Include Rails helpers
  config.include ActiveSupport::Testing::TimeHelpers
  if defined?(ActionController::TestCase)
    config.include ActionController::TestCase::Behavior, type: :controller
  end

  # Use database transactions for tests (only if rspec-rails is available)
  if config.respond_to?(:use_transactional_fixtures=)
    config.use_transactional_fixtures = true
  end

  # Clean database before each test
  config.before(:suite) do
    # Ensure connection is established
    ActiveRecord::Base.connection
    
    # Create tables if they don't exist
    unless ActiveRecord::Base.connection.table_exists?("pg_sql_triggers_registry")
      ActiveRecord::Base.connection.create_table "pg_sql_triggers_registry" do |t|
        t.string :trigger_name, null: false
        t.string :table_name, null: false
        t.integer :version, null: false, default: 1
        t.boolean :enabled, null: false, default: false
        t.string :checksum, null: false
        t.string :source, null: false
        t.string :environment
        t.text :definition
        t.text :function_body
        t.text :condition
        t.datetime :installed_at
        t.datetime :last_verified_at
        t.timestamps
      end

      ActiveRecord::Base.connection.add_index "pg_sql_triggers_registry", :trigger_name, unique: true
      ActiveRecord::Base.connection.add_index "pg_sql_triggers_registry", :table_name
    end

    unless ActiveRecord::Base.connection.table_exists?("trigger_migrations")
      ActiveRecord::Base.connection.create_table "trigger_migrations" do |t|
        t.string :version, null: false
      end
      ActiveRecord::Base.connection.add_index "trigger_migrations", :version, unique: true
    end
  end

  config.before(:each) do
    # Clean tables before each test
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE pg_sql_triggers_registry CASCADE") if ActiveRecord::Base.connection.table_exists?("pg_sql_triggers_registry")
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE trigger_migrations CASCADE") if ActiveRecord::Base.connection.table_exists?("trigger_migrations")
  end
end
