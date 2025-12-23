# frozen_string_literal: true

require_relative "pg_triggers/version"
require_relative "pg_triggers/engine"

module PgTriggers
  class Error < StandardError; end
  class PermissionError < Error; end
  class DriftError < Error; end
  class KillSwitchError < Error; end
  class ValidationError < Error; end

  # Configuration
  mattr_accessor :kill_switch_enabled
  self.kill_switch_enabled = true

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
  autoload :DSL, "pg_triggers/dsl"
  autoload :Registry, "pg_triggers/registry"
  autoload :Drift, "pg_triggers/drift"
  autoload :Permissions, "pg_triggers/permissions"
  autoload :SQL, "pg_triggers/sql"
  autoload :DatabaseIntrospection, "pg_triggers/database_introspection"
  autoload :Generator, "pg_triggers/generator"
  autoload :Testing, "pg_triggers/testing"
  autoload :Migration, "pg_triggers/migration"
  autoload :Migrator, "pg_triggers/migrator"
end
