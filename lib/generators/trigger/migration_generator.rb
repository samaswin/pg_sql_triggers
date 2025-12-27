# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"
require "active_support/core_ext/string/inflections"

module Trigger
  module Generators
    class MigrationGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("../../pg_sql_triggers/templates", __dir__)

      argument :name, type: :string, desc: "Name of the trigger migration"

      def self.next_migration_number(dirname)
        # Get the highest migration number from existing migrations
        if Dir.exist?(Rails.root.join("db", "triggers"))
          existing = Dir.glob(Rails.root.join("db", "triggers", "*.rb"))
            .map { |f| File.basename(f, ".rb").split("_").first.to_i }
            .reject(&:zero?)
            .max || 0
        else
          existing = 0
        end

        # Generate next timestamp-based version
        # Format: YYYYMMDDHHMMSS
        now = Time.now.utc
        base = now.strftime("%Y%m%d%H%M%S").to_i

        # If we have existing migrations, ensure we're incrementing
        if existing > 0 && base <= existing
          base = existing + 1
        end

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

      def class_name
        name.camelize
      end

      def migration_number
        self.class.next_migration_number(nil)
      end
    end
  end
end

