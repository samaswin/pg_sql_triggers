# frozen_string_literal: true

require_relative "pg_sql_triggers/version"
require_relative "pg_sql_triggers/engine"

# Rails 6.0 compatibility: compact_blank was added in Rails 6.1
unless Array.instance_methods.include?(:compact_blank)
  class Array
    def compact_blank
      reject(&:blank?)
    end
  end
end

module PgSqlTriggers
  class Error < StandardError; end
  class PermissionError < Error; end
  class DriftError < Error; end
  class KillSwitchError < Error; end
  class ValidationError < Error; end

  # Configuration
  mattr_accessor :kill_switch_enabled
  self.kill_switch_enabled = true

  mattr_accessor :kill_switch_environments
  self.kill_switch_environments = %i[production staging]

  mattr_accessor :kill_switch_confirmation_required
  self.kill_switch_confirmation_required = true

  mattr_accessor :kill_switch_confirmation_pattern
  self.kill_switch_confirmation_pattern = ->(operation) { "EXECUTE #{operation.to_s.upcase}" }

  mattr_accessor :kill_switch_logger
  self.kill_switch_logger = nil # Will default to Rails.logger if available

  mattr_accessor :default_environment
  self.default_environment = -> { Rails.env }

  mattr_accessor :permission_checker
  self.permission_checker = nil

  mattr_accessor :excluded_tables
  self.excluded_tables = []

  def self.configure
    yield self
  end

  # Autoload components
  autoload :DSL, "pg_sql_triggers/dsl"
  autoload :Registry, "pg_sql_triggers/registry"
  autoload :Drift, "pg_sql_triggers/drift"
  autoload :Permissions, "pg_sql_triggers/permissions"
  autoload :SQL, "pg_sql_triggers/sql"
  autoload :DatabaseIntrospection, "pg_sql_triggers/database_introspection"
  autoload :Generator, "pg_sql_triggers/generator"
  autoload :Testing, "pg_sql_triggers/testing"
  autoload :Migration, "pg_sql_triggers/migration"
  autoload :Migrator, "pg_sql_triggers/migrator"
end
