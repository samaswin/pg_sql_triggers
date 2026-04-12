# frozen_string_literal: true

require_relative "schema_dumper_extension"
require_relative "trigger_structure_dumper"

module PgSqlTriggers
  class Engine < ::Rails::Engine
    isolate_namespace PgSqlTriggers

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: "spec/factories"
    end

    # Configure assets
    initializer "pg_sql_triggers.assets" do |app|
      # Rails engines automatically add app/assets to paths, but we explicitly add
      # the stylesheets and javascripts directories to ensure they're found
      if app.config.respond_to?(:assets)
        app.config.assets.paths << root.join("app/assets/stylesheets").to_s
        app.config.assets.paths << root.join("app/assets/javascripts").to_s
        app.config.assets.precompile += %w[pg_sql_triggers/application.css pg_sql_triggers/application.js]
      end
    end

    # Load rake tasks
    rake_tasks do
      load root.join("lib/tasks/trigger_migrations.rake")
    end

    initializer "pg_sql_triggers.schema_integration", before: :load_config_initializers do
      ActiveSupport.on_load(:active_record) do
        unless ActiveRecord::SchemaDumper.ancestors.include?(PgSqlTriggers::SchemaDumperExtension)
          ActiveRecord::SchemaDumper.prepend(PgSqlTriggers::SchemaDumperExtension)
        end
      end
    end

    # Warn at startup if no permission_checker is set in a protected environment.
    # The default is to allow all actions (including admin-level ones), which is
    # unsafe in production without an explicit checker configured.
    config.after_initialize do
      install_schema_load_trigger_hook

      if PgSqlTriggers.permission_checker.nil? && defined?(Rails) && Rails.env.production?
        Rails.logger.warn(
          "[PgSqlTriggers] SECURITY WARNING: No permission_checker is configured. " \
          "All actions are permitted by default, including admin-level operations " \
          "(drop_trigger, execute_sql, override_drift). " \
          "Set PgSqlTriggers.permission_checker in an initializer before deploying to production."
        )
      end
    end

    def self.install_schema_load_trigger_hook
      return if @schema_load_trigger_hook_installed
      return unless PgSqlTriggers.migrate_triggers_after_schema_load
      return if ENV["SKIP_TRIGGER_MIGRATE_AFTER_SCHEMA_LOAD"].present?
      return unless defined?(Rake::Task)

      if defined?(Rails.application) && Rails.application.respond_to?(:load_tasks)
        Rails.application.load_tasks
      end

      return unless Rake::Task.task_defined?("db:schema:load")

      @schema_load_trigger_hook_installed = true

      Rake::Task["db:schema:load"].enhance do
        next unless PgSqlTriggers.migrate_triggers_after_schema_load
        next if ENV["SKIP_TRIGGER_MIGRATE_AFTER_SCHEMA_LOAD"].present?

        Rake::Task["trigger:migrate"].invoke
      end
    end
  end
end
