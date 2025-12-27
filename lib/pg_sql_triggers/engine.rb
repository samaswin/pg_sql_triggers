# frozen_string_literal: true

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
  end
end
