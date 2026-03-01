# frozen_string_literal: true

require "ostruct"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/module/delegation"
require_relative "migrator/pre_apply_comparator"
require_relative "migrator/pre_apply_diff_reporter"
require_relative "migrator/safety_validator"

module PgSqlTriggers
  # rubocop:disable Metrics/ClassLength
  class Migrator
    MIGRATIONS_TABLE_NAME = "trigger_migrations"

    class << self
      def migrations_path
        Rails.root.join("db/triggers")
      end

      def migrations_table_exists?
        ActiveRecord::Base.connection.table_exists?(MIGRATIONS_TABLE_NAME)
      end

      def ensure_migrations_table!
        return if migrations_table_exists?

        ActiveRecord::Base.connection.create_table MIGRATIONS_TABLE_NAME do |t|
          t.string :version, null: false
        end

        ActiveRecord::Base.connection.add_index MIGRATIONS_TABLE_NAME, :version, unique: true
      end

      def current_version
        ensure_migrations_table!
        result = ActiveRecord::Base.connection.select_one(
          "SELECT version FROM #{MIGRATIONS_TABLE_NAME} ORDER BY version DESC LIMIT 1"
        )
        result ? result["version"].to_i : 0
      end

      def migrations
        return [] unless Dir.exist?(migrations_path)

        files = Dir.glob(migrations_path.join("*.rb"))
        files.map do |file|
          basename = File.basename(file, ".rb")
          # Handle Rails migration format: YYYYMMDDHHMMSS_name
          # Extract version (timestamp) and name
          if basename =~ /^(\d+)_(.+)$/
            version = ::Regexp.last_match(1).to_i
            name = ::Regexp.last_match(2)
          else
            # Fallback: treat first part as version
            parts = basename.split("_", 2)
            version = parts[0].to_i
            name = parts[1] || basename
          end

          Struct.new(:version, :name, :filename, :path, keyword_init: true).new(
            version: version,
            name: name,
            filename: File.basename(file),
            path: file
          )
        end
      end

      def pending_migrations
        current_ver = current_version
        migrations.select { |m| m.version > current_ver }
      end

      def run(direction = :up, target_version = nil)
        ensure_migrations_table!

        case direction
        when :up
          run_up(target_version)
        when :down
          run_down(target_version)
        end
      end

      def run_up(target_version = nil, confirmation: nil)
        # Check kill switch before running migrations
        # This provides protection when called directly from console
        # When called from rake tasks, the ENV override will already be in place
        # Use ENV["CONFIRMATION_TEXT"] if confirmation is not provided (for rake task compatibility)
        confirmation ||= ENV.fetch("CONFIRMATION_TEXT", nil)
        PgSqlTriggers::SQL::KillSwitch.check!(
          operation: :migrator_run_up,
          environment: Rails.env,
          confirmation: confirmation,
          actor: { type: "Console", id: "Migrator.run_up" }
        )

        if target_version
          # Apply a specific migration version
          migration_to_apply = migrations.find { |m| m.version == target_version }
          raise StandardError, "Migration version #{target_version} not found" if migration_to_apply.nil?

          # Check if it's already applied
          quoted_version = ActiveRecord::Base.connection.quote(target_version.to_s)
          version_exists = ActiveRecord::Base.connection.select_value(
            "SELECT 1 FROM #{MIGRATIONS_TABLE_NAME} WHERE version = #{quoted_version} LIMIT 1"
          )

          raise StandardError, "Migration version #{target_version} is already applied" if version_exists.present?

          run_migration(migration_to_apply, :up)
        else
          # Apply all pending migrations
          pending = pending_migrations
          pending.each do |migration|
            run_migration(migration, :up)
          end
        end
      end

      def run_down(target_version = nil, confirmation: nil)
        # Check kill switch before running migrations
        # This provides protection when called directly from console
        # When called from rake tasks, the ENV override will already be in place
        # Use ENV["CONFIRMATION_TEXT"] if confirmation is not provided (for rake task compatibility)
        confirmation ||= ENV.fetch("CONFIRMATION_TEXT", nil)
        PgSqlTriggers::SQL::KillSwitch.check!(
          operation: :migrator_run_down,
          environment: Rails.env,
          confirmation: confirmation,
          actor: { type: "Console", id: "Migrator.run_down" }
        )

        current_ver = current_version
        return if current_ver.zero?

        if target_version
          # Rollback to the specified version (rollback all migrations with version > target_version)
          target_migration = migrations.find { |m| m.version == target_version }

          raise StandardError, "Migration version #{target_version} not found or not applied" if target_migration.nil?

          if current_ver <= target_version
            raise StandardError, "Migration version #{target_version} not found or not applied"
          end

          migrations_to_rollback = migrations
                                   .select { |m| m.version > target_version && m.version <= current_ver }
                                   .sort_by(&:version)
                                   .reverse

        else
          # Rollback the last migration by default
          migrations_to_rollback = migrations
                                   .select { |m| m.version == current_ver }
                                   .sort_by(&:version)
                                   .reverse

        end
        migrations_to_rollback.each do |migration|
          run_migration(migration, :down)
        end
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def run_migration(migration, direction)
        require migration.path

        # Extract class name from migration name
        # e.g., "posts_comment_count_validation" -> "PostsCommentCountValidation"
        base_class_name = migration.name.camelize

        # Try to find the class, trying multiple patterns:
        # 1. Direct name (for backwards compatibility)
        # 2. With "Add" prefix (for new migrations following Rails conventions)
        # 3. With PgSqlTriggers namespace
        migration_class = begin
          base_class_name.constantize
        rescue NameError
          begin
            # Try with "Add" prefix (Rails migration naming convention)
            "Add#{base_class_name}".constantize
          rescue NameError
            begin
              # Try with PgSqlTriggers namespace
              "PgSqlTriggers::#{base_class_name}".constantize
            rescue NameError
              # Try with both Add prefix and PgSqlTriggers namespace
              "PgSqlTriggers::Add#{base_class_name}".constantize
            end
          end
        end

        # Capture SQL once from a single inspection instance so that both the
        # safety validator and comparator work from the same snapshot without
        # running the migration code a second time.
        captured_sql = capture_migration_sql(migration_class.new, direction)

        # Perform safety validation (prevent unsafe DROP + CREATE operations)
        begin
          allow_unsafe = ENV["ALLOW_UNSAFE_MIGRATIONS"] == "true" ||
                         (defined?(PgSqlTriggers) && PgSqlTriggers.allow_unsafe_migrations == true)

          SafetyValidator.validate_sql!(captured_sql, direction: direction, allow_unsafe: allow_unsafe)
        rescue SafetyValidator::UnsafeOperationError => e
          # Safety validation failed - block the migration
          error_msg = "\n#{e.message}\n\n"
          Rails.logger.error(error_msg) if defined?(Rails.logger)
          Rails.logger.debug error_msg if ENV["VERBOSE"] != "false" || defined?(Rails::Console)
          raise StandardError, "Migration blocked due to unsafe DROP + CREATE operations. " \
                               "Review the errors above and set ALLOW_UNSAFE_MIGRATIONS=true if you must proceed."
        rescue StandardError => e
          # Don't fail the migration if validation fails for other reasons - just log it
          if defined?(Rails.logger)
            Rails.logger.warn("Safety validation failed for migration #{migration.name}: #{e.message}")
          end
        end

        # Perform pre-apply comparison (diff expected vs actual) using the same captured SQL
        begin
          diff_result = PreApplyComparator.compare_sql(captured_sql)

          # Log the comparison result
          if diff_result[:has_differences]
            diff_report = PreApplyDiffReporter.format(diff_result, migration_name: migration.name)
            if defined?(Rails.logger)
              Rails.logger.warn("Pre-apply comparison for migration #{migration.name}:\n#{diff_report}")
            end

            # In verbose mode or when called from console, print the diff
            if ENV["VERBOSE"] != "false" || defined?(Rails::Console)
              Rails.logger.debug { "\n#{PreApplyDiffReporter.format_summary(diff_result)}\n" }
            end
          elsif defined?(Rails.logger)
            Rails.logger.info(
              "Pre-apply comparison: No differences detected for migration #{migration.name}"
            )
          end
        rescue StandardError => e
          # Don't fail the migration if comparison fails - just log it
          if defined?(Rails.logger)
            Rails.logger.warn("Pre-apply comparison failed for migration #{migration.name}: #{e.message}")
          end
        end

        ActiveRecord::Base.transaction do
          # Create a fresh instance for actual execution
          migration_instance = migration_class.new
          migration_instance.public_send(direction)

          connection = ActiveRecord::Base.connection
          version_str = connection.quote(migration.version.to_s)

          if direction == :up
            connection.execute(
              "INSERT INTO #{MIGRATIONS_TABLE_NAME} (version) VALUES (#{version_str})"
            )
          else
            connection.execute(
              "DELETE FROM #{MIGRATIONS_TABLE_NAME} WHERE version = #{version_str}"
            )
            # Clean up registry entries for triggers that no longer exist in database
            cleanup_orphaned_registry_entries
          end
        end

        enforce_disabled_triggers if direction == :up
      rescue LoadError => e
        raise StandardError, "Error loading trigger migration #{migration.filename}: #{e.message}"
      rescue StandardError => e
        raise StandardError,
              "Error running trigger migration #{migration.filename}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      def status
        ensure_migrations_table!
        current_version

        migrations.map do |migration|
          # Check if this specific migration version exists in the migrations table
          # This is more reliable than just comparing versions
          quoted_version = ActiveRecord::Base.connection.quote(migration.version.to_s)
          version_exists = ActiveRecord::Base.connection.select_value(
            "SELECT 1 FROM #{MIGRATIONS_TABLE_NAME} WHERE version = #{quoted_version} LIMIT 1"
          )
          ran = version_exists.present?

          {
            version: migration.version,
            name: migration.name,
            status: ran ? "up" : "down",
            filename: migration.filename
          }
        end
      end

      def version
        current_version
      end

      private

      # Capture the SQL statements a migration would execute for a given direction
      # without committing any side effects.  The migration's +execute+ method is
      # overridden on the singleton so raw SQL strings are intercepted, and the
      # whole run is wrapped in a transaction that is always rolled back so that
      # any ActiveRecord migration helpers (add_column, create_table, …) don't
      # persist their effects during the inspection phase.
      def capture_migration_sql(migration_instance, direction)
        captured = []

        migration_instance.define_singleton_method(:execute) do |sql|
          captured << sql.to_s.strip
        end

        ActiveRecord::Base.transaction do
          migration_instance.public_send(direction)
          raise ActiveRecord::Rollback
        end

        captured
      end

      def enforce_disabled_triggers
        return unless ActiveRecord::Base.connection.table_exists?("pg_sql_triggers_registry")

        introspection = PgSqlTriggers::DatabaseIntrospection.new
        PgSqlTriggers::TriggerRegistry.disabled.each do |registry|
          next unless introspection.trigger_exists?(registry.trigger_name)

          conn           = ActiveRecord::Base.connection
          quoted_table   = conn.quote_table_name(registry.table_name.to_s)
          quoted_trigger = conn.quote_table_name(registry.trigger_name.to_s)
          conn.execute("ALTER TABLE #{quoted_table} DISABLE TRIGGER #{quoted_trigger};")
        rescue StandardError => e
          Rails.logger.warn("[MIGRATOR] Could not disable trigger #{registry.trigger_name}: #{e.message}") if defined?(Rails.logger)
        end
      end

      public

      # Clean up registry entries for triggers that no longer exist in the database
      # This is called after rolling back migrations to keep the registry in sync
      def cleanup_orphaned_registry_entries
        return unless ActiveRecord::Base.connection.table_exists?("pg_sql_triggers_registry")

        introspection = PgSqlTriggers::DatabaseIntrospection.new

        # Get all triggers from registry
        registry_triggers = PgSqlTriggers::TriggerRegistry.all

        # Remove registry entries for triggers that don't exist in database
        registry_triggers.each do |registry_trigger|
          unless introspection.trigger_exists?(registry_trigger.trigger_name)
            Rails.logger.info("Removing orphaned registry entry for trigger: #{registry_trigger.trigger_name}")
            registry_trigger.destroy
          end
        end
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
