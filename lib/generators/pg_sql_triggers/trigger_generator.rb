# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"
require "active_support/core_ext/string/inflections"

module PgSqlTriggers
  module Generators
    class TriggerGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Generates a pg_sql_triggers DSL file and migration for a new trigger."

      argument :trigger_name, type: :string,
               desc: "Name of the trigger (e.g. notify_on_insert_users)"
      argument :table_name, type: :string,
               desc: "Database table the trigger attaches to (e.g. users)"
      argument :events, type: :array, default: ["insert"], banner: "EVENT ...",
               desc: "Trigger events: insert, update, delete (default: insert)"

      class_option :timing, type: :string, default: "before",
                            desc: "Trigger timing: before or after (default: before)"
      class_option :function, type: :string,
                              desc: "Function name (default: TRIGGER_NAME_function)"

      def self.next_migration_number(_dirname)
        existing = if Rails.root.join("db/triggers").exist?
                     Rails.root.glob("db/triggers/*.rb")
                          .map { |f| File.basename(f, ".rb").split("_").first.to_i }
                          .reject(&:zero?)
                          .max || 0
                   else
                     0
                   end

        now = Time.now.utc
        base = now.strftime("%Y%m%d%H%M%S").to_i
        base = existing + 1 if existing.positive? && base <= existing
        base
      end

      def create_dsl_file
        template "trigger_dsl.rb.tt", "app/triggers/#{trigger_name}.rb"
      end

      def create_migration_file
        template "trigger_migration_full.rb.tt", "db/triggers/#{migration_file_name}.rb"
      end

      private

      def function_name
        options[:function].presence || "#{trigger_name}_function"
      end

      def timing
        options[:timing]
      end

      def events_list
        events.map { |e| ":#{e}" }.join(", ")
      end

      def events_sql
        events.map(&:upcase).join(" OR ")
      end

      def trigger_class_name
        "Add#{trigger_name.camelize}"
      end

      def migration_file_name
        "#{migration_number}_#{trigger_name}"
      end

      def migration_number
        self.class.next_migration_number(nil)
      end
    end
  end
end
