# frozen_string_literal: true

require "pathname"
require "time"

module PgSqlTriggers
  # Builds a SQL snapshot of PostgreSQL triggers for db/trigger_structure.sql and
  # emits schema.rb annotations so teams know triggers are outside schema.rb.
  class TriggerStructureDumper
    class << self
      def resolve_path(override = nil)
        base = override || PgSqlTriggers.trigger_structure_sql_path
        resolved = base.respond_to?(:call) ? base.call : base
        resolved ||= default_path
        Pathname(resolved.to_s)
      end

      def default_path
        raise "Rails.root is required" unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root

        Rails.root.join("db/trigger_structure.sql")
      end

      def dump_to(path = nil, connection: ActiveRecord::Base.connection)
        target = resolve_path(path)
        target.dirname.mkpath
        target.write(generate_sql(connection: connection))
        target
      end

      def load_from(path = nil, connection: ActiveRecord::Base.connection)
        target = resolve_path(path)
        raise Errno::ENOENT, target.to_s unless target.file?

        sql = target.read
        return if sql.strip.empty?

        connection.raw_connection.exec(sql)
        nil
      end

      def generate_sql(connection: ActiveRecord::Base.connection)
        header = <<~SQL
          -- pg_sql_triggers trigger_structure.sql
          -- Generated at: #{Time.now.utc.iso8601}
          --
          -- Apply with: bin/rails trigger:load
          -- Prefer checking this file into version control alongside db/triggers migrations.
        SQL

        rows = trigger_rows(connection)
        parts = [header]

        rows.each do |row|
          trigger_name = row["trigger_name"] || row[:trigger_name]
          parts << ""
          parts << "-- Trigger: #{trigger_name}"
          append_definition(parts, row["function_definition"] || row[:function_definition])
          append_definition(parts, row["trigger_definition"] || row[:trigger_definition])
        end

        parts.join("\n").strip.concat("\n")
      end

      def schema_rb_annotation(connection: ActiveRecord::Base.connection)
        names = managed_trigger_names(connection)
        lines = []
        lines << "  # ---------------------------------------------------------------------------"
        lines << "  # pg_sql_triggers: PostgreSQL triggers are not captured in schema.rb."
        lines << "  # After db:schema:load, run: bin/rails trigger:migrate (or trigger:load)."
        lines << "  # SQL snapshot: db/trigger_structure.sql (bin/rails trigger:dump)."
        lines << "  # For full fidelity use config.active_record.schema_format = :sql."
        lines << if names.any?
                   "  # Managed triggers (#{names.length}): #{names.join(', ')}"
                 else
                   "  # Managed triggers: (none registered in pg_sql_triggers_registry)"
                 end
        lines << "  # ---------------------------------------------------------------------------"
        lines.join("\n")
      end

      def managed_trigger_names(connection)
        return [] unless connection.table_exists?("pg_sql_triggers_registry")

        connection.select_values(
          "SELECT trigger_name FROM pg_sql_triggers_registry ORDER BY trigger_name"
        )
      end

      private

      def trigger_rows(connection)
        if connection.table_exists?("pg_sql_triggers_registry")
          managed_trigger_names(connection).filter_map do |name|
            PgSqlTriggers::Drift::DbQueries.find_trigger(name)
          end
        else
          PgSqlTriggers::Drift::DbQueries.all_triggers
        end
      end

      def append_definition(parts, definition)
        stmt = definition.to_s.strip
        return if stmt.empty?

        stmt += ";" unless stmt.end_with?(";")
        parts << stmt
      end
    end
  end
end
