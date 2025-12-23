# frozen_string_literal: true

require "ostruct"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/module/delegation"

module PgTriggers
  class Migrator
    MIGRATIONS_TABLE_NAME = "trigger_migrations"

    class << self
      def migrations_path
        Rails.root.join("db", "triggers")
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

        files = Dir.glob(migrations_path.join("*.rb")).sort
        files.map do |file|
          basename = File.basename(file, ".rb")
          # Handle Rails migration format: YYYYMMDDHHMMSS_name
          # Extract version (timestamp) and name
          if basename =~ /^(\d+)_(.+)$/
            version = $1.to_i
            name = $2
          else
            # Fallback: treat first part as version
            parts = basename.split("_", 2)
            version = parts[0].to_i
            name = parts[1] || basename
          end

          OpenStruct.new(
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

      def run_up(target_version = nil)
        pending = pending_migrations
        pending = pending.select { |m| m.version <= target_version } if target_version

        pending.each do |migration|
          run_migration(migration, :up)
        end
      end

      def run_down(target_version)
        current_ver = current_version
        return if current_ver == 0

        target_ver = target_version || (current_ver - 1)
        migrations_to_rollback = migrations
          .select { |m| m.version <= current_ver && m.version > target_ver }
          .sort_by(&:version)
          .reverse

        migrations_to_rollback.each do |migration|
          run_migration(migration, :down)
        end
      end

      def run_migration(migration, direction)
        require migration.path

        # Extract class name from migration name
        # e.g., "add_validation_trigger" -> "AddValidationTrigger"
        class_name = migration.name.camelize
        
        # Try to find the class in the main namespace first
        migration_class = begin
          class_name.constantize
        rescue NameError
          # If not found, try with PgTriggers namespace
          "PgTriggers::#{class_name}".constantize
        end

        ActiveRecord::Base.transaction do
          migration_instance = migration_class.new
          migration_instance.public_send(direction)

          if direction == :up
            ActiveRecord::Base.connection.execute(
              "INSERT INTO #{MIGRATIONS_TABLE_NAME} (version) VALUES (#{migration.version})"
            )
          else
            ActiveRecord::Base.connection.execute(
              "DELETE FROM #{MIGRATIONS_TABLE_NAME} WHERE version = #{migration.version}"
            )
          end
        end
      rescue LoadError => e
        raise StandardError, "Error loading trigger migration #{migration.filename}: #{e.message}"
      rescue => e
        raise StandardError, "Error running trigger migration #{migration.filename}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end

      def status
        ensure_migrations_table!
        current_ver = current_version

        migrations.map do |migration|
          ran = migration.version <= current_ver
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
    end
  end
end

