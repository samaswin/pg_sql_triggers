# frozen_string_literal: true

namespace :trigger do
  desc "Migrate trigger migrations (options: VERSION=x, VERBOSE=false)"
  task migrate: :environment do
    PgSqlTriggers::Migrator.ensure_migrations_table!

    target_version = ENV["VERSION"]&.to_i
    verbose = ENV["VERBOSE"] != "false"

    if verbose
      puts "Running trigger migrations..."
      puts "Current version: #{PgSqlTriggers::Migrator.current_version}"
    end

    PgSqlTriggers::Migrator.run_up(target_version)

    puts "Trigger migrations complete. Current version: #{PgSqlTriggers::Migrator.current_version}" if verbose
  end

  desc "Rollback trigger migrations (specify steps w/ STEP=n)"
  task rollback: :environment do
    PgSqlTriggers::Migrator.ensure_migrations_table!

    steps = ENV["STEP"] ? ENV["STEP"].to_i : 1
    current_version = PgSqlTriggers::Migrator.current_version
    target_version = [0, current_version - steps].max

    puts "Rolling back trigger migrations..."
    puts "Current version: #{current_version}"
    puts "Target version: #{target_version}"

    PgSqlTriggers::Migrator.run_down(target_version)

    puts "Rollback complete. Current version: #{PgSqlTriggers::Migrator.current_version}"
  end

  desc "Display status of trigger migrations"
  task "migrate:status" => :environment do
    PgSqlTriggers::Migrator.ensure_migrations_table!

    statuses = PgSqlTriggers::Migrator.status

    if statuses.empty?
      puts "No trigger migrations found"
      return
    end

    puts "\nTrigger Migration Status"
    puts "=" * 80
    printf "%<version>-20s %<name>-40s %<status>-10s\n", version: "Version", name: "Name", status: "Status"
    puts "-" * 80

    statuses.each do |status|
      printf "%<version>-20s %<name>-40s %<status>-10s\n",
             version: status[:version],
             name: status[:name],
             status: status[:status]
    end

    puts "=" * 80
    puts "Current version: #{PgSqlTriggers::Migrator.current_version}"
  end

  desc "Runs the 'up' for a given migration VERSION"
  task "migrate:up" => :environment do
    version = ENV.fetch("VERSION", nil)
    raise "VERSION is required" unless version

    PgSqlTriggers::Migrator.ensure_migrations_table!
    PgSqlTriggers::Migrator.run_up(version.to_i)
    puts "Trigger migration #{version} up complete"
  end

  desc "Runs the 'down' for a given migration VERSION"
  task "migrate:down" => :environment do
    version = ENV.fetch("VERSION", nil)
    raise "VERSION is required" unless version

    PgSqlTriggers::Migrator.ensure_migrations_table!
    PgSqlTriggers::Migrator.run_down(version.to_i)
    puts "Trigger migration #{version} down complete"
  end

  desc "Rollbacks the database one migration and re migrate up (options: STEP=x, VERSION=x)"
  task "migrate:redo" => :environment do
    PgSqlTriggers::Migrator.ensure_migrations_table!

    if ENV["VERSION"]
      version = ENV["VERSION"].to_i
      PgSqlTriggers::Migrator.run_down(version)
      PgSqlTriggers::Migrator.run_up(version)
    else
      steps = ENV["STEP"] ? ENV["STEP"].to_i : 1
      current_version = PgSqlTriggers::Migrator.current_version
      target_version = [0, current_version - steps].max

      PgSqlTriggers::Migrator.run_down(target_version)
      PgSqlTriggers::Migrator.run_up
    end

    puts "Trigger migration redo complete"
  end

  desc "Retrieves the current schema version number for trigger migrations"
  task version: :environment do
    PgSqlTriggers::Migrator.ensure_migrations_table!
    puts "Current trigger migration version: #{PgSqlTriggers::Migrator.current_version}"
  end

  desc "Raises an error if there are pending trigger migrations"
  task "abort_if_pending_migrations" => :environment do
    PgSqlTriggers::Migrator.ensure_migrations_table!

    pending = PgSqlTriggers::Migrator.pending_migrations
    if pending.any?
      puts "You have #{pending.length} pending trigger migration(s):"
      pending.each do |migration|
        puts "  #{migration.version}_#{migration.name}"
      end
      raise "Pending trigger migrations found"
    end
  end
end

# Combined tasks for running both schema and trigger migrations
namespace :db do
  desc "Migrate the database schema and triggers (options: VERSION=x, VERBOSE=false)"
  task "migrate:with_triggers" => :environment do
    verbose = ENV["VERBOSE"] != "false"

    puts "Running schema and trigger migrations..." if verbose

    # Run schema migrations first
    Rake::Task["db:migrate"].invoke

    # Then run trigger migrations
    Rake::Task["trigger:migrate"].invoke
  end

  desc "Rollback schema and trigger migrations (specify steps w/ STEP=n)"
  task "rollback:with_triggers" => :environment do
    ENV["STEP"] ? ENV["STEP"].to_i : 1

    # Determine which type of migration was last run
    schema_version = ActiveRecord::Base.connection.schema_migration_context.current_version || 0
    trigger_version = PgSqlTriggers::Migrator.current_version

    # Rollback the most recent migration (schema or trigger)
    if schema_version > trigger_version
      Rake::Task["db:rollback"].invoke
    else
      Rake::Task["trigger:rollback"].invoke
    end
  end

  desc "Display status of schema and trigger migrations"
  task "migrate:status:with_triggers" => :environment do
    puts "\nSchema Migrations:"
    puts "=" * 80
    begin
      Rake::Task["db:migrate:status"].invoke
    rescue StandardError => e
      puts "Error displaying schema migration status: #{e.message}"
    end

    puts "\nTrigger Migrations:"
    puts "=" * 80
    Rake::Task["trigger:migrate:status"].invoke
  end

  desc "Runs the 'up' for a given migration VERSION (schema or trigger)"
  task "migrate:up:with_triggers" => :environment do
    version = ENV.fetch("VERSION", nil)
    raise "VERSION is required" unless version

    version_int = version.to_i

    # Check if it's a schema or trigger migration
    schema_migrations = ActiveRecord::Base.connection.migration_context.migrations
    trigger_migrations = PgSqlTriggers::Migrator.migrations

    schema_migration = schema_migrations.find { |m| m.version == version_int }
    trigger_migration = trigger_migrations.find { |m| m.version == version_int }

    if schema_migration && trigger_migration
      # Both exist - run schema first
      Rake::Task["db:migrate:up"].invoke
      Rake::Task["trigger:migrate:up"].invoke
    elsif schema_migration
      Rake::Task["db:migrate:up"].invoke
    elsif trigger_migration
      Rake::Task["trigger:migrate:up"].invoke
    else
      raise "No migration found with version #{version}"
    end
  rescue StandardError => e
    puts "Error: #{e.message}"
    raise
  end

  desc "Runs the 'down' for a given migration VERSION (schema or trigger)"
  task "migrate:down:with_triggers" => :environment do
    version = ENV.fetch("VERSION", nil)
    raise "VERSION is required" unless version

    version_int = version.to_i

    # Check if it's a schema or trigger migration
    schema_migrations = ActiveRecord::Base.connection.migration_context.migrations
    trigger_migrations = PgSqlTriggers::Migrator.migrations

    schema_migration = schema_migrations.find { |m| m.version == version_int }
    trigger_migration = trigger_migrations.find { |m| m.version == version_int }

    if schema_migration && trigger_migration
      # Both exist - run trigger down first
      Rake::Task["trigger:migrate:down"].invoke
      Rake::Task["db:migrate:down"].invoke
    elsif schema_migration
      Rake::Task["db:migrate:down"].invoke
    elsif trigger_migration
      Rake::Task["trigger:migrate:down"].invoke
    else
      raise "No migration found with version #{version}"
    end
  end

  desc "Rollbacks the database one migration and re migrate up (options: STEP=x, VERSION=x)"
  task "migrate:redo:with_triggers" => :environment do
    if ENV["VERSION"]
      Rake::Task["db:migrate:down:with_triggers"].invoke
      Rake::Task["db:migrate:up:with_triggers"].invoke
    else
      Rake::Task["db:rollback:with_triggers"].invoke
      Rake::Task["db:migrate:with_triggers"].invoke
    end
  end

  desc "Retrieves the current schema version numbers for schema and trigger migrations"
  task "version:with_triggers" => :environment do
    schema_version = ActiveRecord::Base.connection.schema_migration_context.current_version
    trigger_version = PgSqlTriggers::Migrator.current_version

    puts "Schema migration version: #{schema_version || 0}"
    puts "Trigger migration version: #{trigger_version}"
  end

  desc "Raises an error if there are pending migrations or trigger migrations"
  task "abort_if_pending_migrations:with_triggers" => :environment do
    Rake::Task["db:abort_if_pending_migrations"].invoke
    Rake::Task["trigger:abort_if_pending_migrations"].invoke
  end
end
