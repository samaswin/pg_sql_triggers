# frozen_string_literal: true

module PgSqlTriggersRakeHelpers
  module MigrateTasks
    module_function

    def run_migrate
      PgSqlTriggersRakeHelpers.check_kill_switch!(:trigger_migrate)
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

    def run_rollback
      PgSqlTriggersRakeHelpers.check_kill_switch!(:trigger_rollback)
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

    def print_migrate_status
      PgSqlTriggers::Migrator.ensure_migrations_table!
      statuses = PgSqlTriggers::Migrator.status
      return puts "No trigger migrations found" if statuses.empty?

      print_status_table(statuses)
    end

    def print_status_table(statuses)
      puts "\nTrigger Migration Status"
      puts "=" * 80
      printf "%<version>-20s %<name>-40s %<status>-10s\n", version: "Version", name: "Name", status: "Status"
      puts "-" * 80
      statuses.each do |status|
        printf "%<version>-20s %<name>-40s %<status>-10s\n",
               version: status[:version], name: status[:name], status: status[:status]
      end
      puts "=" * 80
      puts "Current version: #{PgSqlTriggers::Migrator.current_version}"
    end

    def run_migrate_up
      PgSqlTriggersRakeHelpers.check_kill_switch!(:trigger_migrate_up)
      version = ENV.fetch("VERSION", nil)
      raise "VERSION is required" unless version

      PgSqlTriggers::Migrator.ensure_migrations_table!
      PgSqlTriggers::Migrator.run_up(version.to_i)
      puts "Trigger migration #{version} up complete"
    end

    def run_migrate_down
      PgSqlTriggersRakeHelpers.check_kill_switch!(:trigger_migrate_down)
      version = ENV.fetch("VERSION", nil)
      raise "VERSION is required" unless version

      PgSqlTriggers::Migrator.ensure_migrations_table!
      PgSqlTriggers::Migrator.run_down(version.to_i)
      puts "Trigger migration #{version} down complete"
    end

    def run_migrate_redo
      PgSqlTriggersRakeHelpers.check_kill_switch!(:trigger_migrate_redo)
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
  end

  module_function

  extend MigrateTasks

  # @param result [Hash] single drift result from {PgSqlTriggers::Drift::Detector}
  def drift_check_trigger_label(result)
    result[:registry_entry]&.trigger_name ||
      result[:db_trigger]&.fetch("trigger_name", nil) ||
      "(unknown)"
  end

  def check_kill_switch!(operation)
    PgSqlTriggers::SQL::KillSwitch.check!(
      operation: operation,
      environment: Rails.env,
      confirmation: ENV.fetch("CONFIRMATION_TEXT", nil),
      actor: { type: "CLI", id: ENV.fetch("USER", "unknown") }
    )
  rescue PgSqlTriggers::KillSwitchError => e
    puts "\n#{e.message}\n"
    exit 1
  end

  def dump_trigger_structure
    path = ENV["FILE"].presence || ENV["TRIGGER_STRUCTURE_SQL"].presence
    written = PgSqlTriggers::TriggerStructureDumper.dump_to(path)
    puts "Wrote #{written}"
  end

  def load_trigger_structure
    check_kill_switch!(:trigger_load)
    path = ENV["FILE"].presence || ENV["TRIGGER_STRUCTURE_SQL"].presence
    PgSqlTriggers::TriggerStructureDumper.load_from(path)
    puts "Loaded #{PgSqlTriggers::TriggerStructureDumper.resolve_path(path)}"
  end

  def run_check_drift
    outcome = PgSqlTriggers::Alerting.check_and_notify
    results = outcome[:results]
    alertable = outcome[:alertable]

    puts "PgSqlTriggers drift check: #{results.size} trigger(s), #{alertable.size} problem(s)."
    alertable.each do |r|
      puts "  - #{drift_check_trigger_label(r)}: #{r[:state]} — #{r[:details]}"
    end
    puts "Notifier invoked." if outcome[:notified]
    if alertable.any? && !outcome[:notified]
      puts "No drift notifier configured; set PgSqlTriggers.drift_notifier to receive alerts."
    end

    exit 1 if ENV["FAIL_ON_DRIFT"].present? && alertable.any?
  end

  def run_validate_order
    errors = PgSqlTriggers::Registry::Validator.trigger_order_validation_errors
    if errors.empty?
      puts "PgSqlTriggers: trigger depends_on / name order OK."
    else
      puts "PgSqlTriggers: trigger order validation failed:"
      errors.each { |msg| puts "  - #{msg}" }
      exit 1
    end
  end

  def abort_if_pending_trigger_migrations
    PgSqlTriggers::Migrator.ensure_migrations_table!
    pending = PgSqlTriggers::Migrator.pending_migrations
    return if pending.empty?

    puts "You have #{pending.length} pending trigger migration(s):"
    pending.each { |migration| puts "  #{migration.version}_#{migration.name}" }
    raise "Pending trigger migrations found"
  end
end

module PgSqlTriggersDbRakeHelpers
  module_function

  def check_kill_switch!(operation)
    PgSqlTriggersRakeHelpers.check_kill_switch!(operation)
  end

  def run_db_migrate_with_triggers
    check_kill_switch!(:db_migrate_with_triggers)
    verbose = ENV["VERBOSE"] != "false"
    puts "Running schema and trigger migrations..." if verbose
    Rake::Task["db:migrate"].invoke
    Rake::Task["trigger:migrate"].invoke
  end

  def run_db_rollback_with_triggers
    check_kill_switch!(:db_rollback_with_triggers)
    ENV["STEP"] ? ENV["STEP"].to_i : 1

    schema_version = ActiveRecord::Base.connection.schema_migration_context.current_version || 0
    trigger_version = PgSqlTriggers::Migrator.current_version

    if schema_version > trigger_version
      Rake::Task["db:rollback"].invoke
    else
      Rake::Task["trigger:rollback"].invoke
    end
  end

  def print_migrate_status_with_triggers
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

  def run_db_migrate_up_with_triggers
    check_kill_switch!(:db_migrate_up_with_triggers)
    version = ENV.fetch("VERSION", nil)
    raise "VERSION is required" unless version

    invoke_up_for_version(version.to_i, version)
  rescue StandardError => e
    puts "Error: #{e.message}"
    raise
  end

  def invoke_up_for_version(version_int, version)
    schema_migration, trigger_migration = find_migrations(version_int)

    if schema_migration && trigger_migration
      Rake::Task["db:migrate:up"].invoke
      Rake::Task["trigger:migrate:up"].invoke
    elsif schema_migration
      Rake::Task["db:migrate:up"].invoke
    elsif trigger_migration
      Rake::Task["trigger:migrate:up"].invoke
    else
      raise "No migration found with version #{version}"
    end
  end

  def run_db_migrate_down_with_triggers
    check_kill_switch!(:db_migrate_down_with_triggers)
    version = ENV.fetch("VERSION", nil)
    raise "VERSION is required" unless version

    invoke_down_for_version(version.to_i, version)
  end

  def invoke_down_for_version(version_int, version)
    schema_migration, trigger_migration = find_migrations(version_int)

    if schema_migration && trigger_migration
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

  def find_migrations(version_int)
    schema_migrations = ActiveRecord::Base.connection.migration_context.migrations
    trigger_migrations = PgSqlTriggers::Migrator.migrations
    [
      schema_migrations.find { |m| m.version == version_int },
      trigger_migrations.find { |m| m.version == version_int }
    ]
  end

  def run_db_migrate_redo_with_triggers
    check_kill_switch!(:db_migrate_redo_with_triggers)

    if ENV["VERSION"]
      Rake::Task["db:migrate:down:with_triggers"].invoke
      Rake::Task["db:migrate:up:with_triggers"].invoke
    else
      Rake::Task["db:rollback:with_triggers"].invoke
      Rake::Task["db:migrate:with_triggers"].invoke
    end
  end

  def print_version_with_triggers
    schema_version = ActiveRecord::Base.connection.schema_migration_context.current_version
    trigger_version = PgSqlTriggers::Migrator.current_version

    puts "Schema migration version: #{schema_version || 0}"
    puts "Trigger migration version: #{trigger_version}"
  end
end

namespace :trigger do
  desc "Dump managed PostgreSQL triggers to db/trigger_structure.sql (FILE=path to override)"
  task(dump: :environment) { PgSqlTriggersRakeHelpers.dump_trigger_structure }

  desc "Execute SQL from db/trigger_structure.sql (FILE=path to override)"
  task(load: :environment) { PgSqlTriggersRakeHelpers.load_trigger_structure }

  desc "Migrate trigger migrations (options: VERSION=x, VERBOSE=false)"
  task(migrate: :environment) { PgSqlTriggersRakeHelpers.run_migrate }

  desc "Rollback trigger migrations (specify steps w/ STEP=n)"
  task(rollback: :environment) { PgSqlTriggersRakeHelpers.run_rollback }

  desc "Display status of trigger migrations"
  task("migrate:status" => :environment) { PgSqlTriggersRakeHelpers.print_migrate_status }

  desc "Runs the 'up' for a given migration VERSION"
  task("migrate:up" => :environment) { PgSqlTriggersRakeHelpers.run_migrate_up }

  desc "Runs the 'down' for a given migration VERSION"
  task("migrate:down" => :environment) { PgSqlTriggersRakeHelpers.run_migrate_down }

  desc "Rollbacks the database one migration and re migrate up (options: STEP=x, VERSION=x)"
  task("migrate:redo" => :environment) { PgSqlTriggersRakeHelpers.run_migrate_redo }

  desc "Retrieves the current schema version number for trigger migrations"
  task version: :environment do
    PgSqlTriggers::Migrator.ensure_migrations_table!
    puts "Current trigger migration version: #{PgSqlTriggers::Migrator.current_version}"
  end

  desc "Detect trigger drift; calls drift_notifier when drifted/dropped/unknown (FAIL_ON_DRIFT=1 exits non-zero)"
  task(check_drift: :environment) { PgSqlTriggersRakeHelpers.run_check_drift }

  desc "Validate trigger depends_on metadata (refs, cycles, compatibility, PostgreSQL name order)"
  task(validate_order: :environment) { PgSqlTriggersRakeHelpers.run_validate_order }

  desc "Raises an error if there are pending trigger migrations"
  task("abort_if_pending_migrations" => :environment) do
    PgSqlTriggersRakeHelpers.abort_if_pending_trigger_migrations
  end
end

# Combined tasks for running both schema and trigger migrations
namespace :db do
  desc "Migrate the database schema and triggers (options: VERSION=x, VERBOSE=false)"
  task("migrate:with_triggers" => :environment) { PgSqlTriggersDbRakeHelpers.run_db_migrate_with_triggers }

  desc "Rollback schema and trigger migrations (specify steps w/ STEP=n)"
  task("rollback:with_triggers" => :environment) { PgSqlTriggersDbRakeHelpers.run_db_rollback_with_triggers }

  desc "Display status of schema and trigger migrations"
  task("migrate:status:with_triggers" => :environment) { PgSqlTriggersDbRakeHelpers.print_migrate_status_with_triggers }

  desc "Runs the 'up' for a given migration VERSION (schema or trigger)"
  task("migrate:up:with_triggers" => :environment) { PgSqlTriggersDbRakeHelpers.run_db_migrate_up_with_triggers }

  desc "Runs the 'down' for a given migration VERSION (schema or trigger)"
  task("migrate:down:with_triggers" => :environment) { PgSqlTriggersDbRakeHelpers.run_db_migrate_down_with_triggers }

  desc "Rollbacks the database one migration and re migrate up (options: STEP=x, VERSION=x)"
  task("migrate:redo:with_triggers" => :environment) { PgSqlTriggersDbRakeHelpers.run_db_migrate_redo_with_triggers }

  desc "Retrieves the current schema version numbers for schema and trigger migrations"
  task("version:with_triggers" => :environment) { PgSqlTriggersDbRakeHelpers.print_version_with_triggers }

  desc "Raises an error if there are pending migrations or trigger migrations"
  task("abort_if_pending_migrations:with_triggers" => :environment) do
    Rake::Task["db:abort_if_pending_migrations"].invoke
    Rake::Task["trigger:abort_if_pending_migrations"].invoke
  end
end
