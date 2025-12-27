# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module PgTriggers
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_initializer
        template "initializer.rb", "config/initializers/pg_sql_triggers.rb"
      end

      def copy_migrations
        migration_template "create_pg_sql_triggers_tables.rb",
                          "db/migrate/create_pg_sql_triggers_tables.rb"
      end

      def mount_engine
        route 'mount PgTriggers::Engine => "/pg_sql_triggers"'
      end

      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end
