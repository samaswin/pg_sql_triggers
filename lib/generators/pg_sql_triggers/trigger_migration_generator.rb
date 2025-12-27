# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"
require "active_support/core_ext/string/inflections"

module PgSqlTriggers
  module Generators
    class TriggerMigrationGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :name, type: :string, desc: "Name of the trigger migration"

      def self.next_migration_number(_dirname)
        # Get the highest migration number from existing migrations
        existing = if Rails.root.join("db/triggers").exist?
                     Rails.root.glob("db/triggers/*.rb")
                          .map { |f| File.basename(f, ".rb").split("_").first.to_i }
                          .reject(&:zero?)
                          .max || 0
                   else
                     0
                   end

        # Generate next timestamp-based version
        # Format: YYYYMMDDHHMMSS
        now = Time.now.utc
        base = now.strftime("%Y%m%d%H%M%S").to_i

        # If we have existing migrations, ensure we're incrementing
        base = existing + 1 if existing.positive? && base <= existing

        base
      end

      def create_trigger_migration
        migration_template(
          "trigger_migration.rb.erb",
          "db/triggers/#{file_name}.rb"
        )
      end

      private

      def file_name
        "#{migration_number}_#{name.underscore}"
      end

      def migration_number
        self.class.next_migration_number(nil)
      end

      def class_name
        name.camelize
      end
    end
  end
end
