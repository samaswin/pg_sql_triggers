# frozen_string_literal: true

module PgSqlTriggers
  class DatabaseIntrospection
    # Default tables to exclude from listing (Rails defaults and pg_sql_triggers internal tables)
    DEFAULT_EXCLUDED_TABLES = %w[
      ar_internal_metadata
      schema_migrations
      pg_sql_triggers_registry
      trigger_migrations
    ].freeze

    # Get list of all excluded tables (defaults + user-configured)
    def excluded_tables
      (DEFAULT_EXCLUDED_TABLES + Array(PgSqlTriggers.excluded_tables)).uniq
    end

    # Get list of all user tables in the database
    def list_tables
      sql = <<~SQL.squish
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
        ORDER BY table_name
      SQL

      result = ActiveRecord::Base.connection.execute(sql)
      tables = result.pluck("table_name")
      tables.reject { |table| excluded_tables.include?(table) }
    rescue StandardError => e
      Rails.logger.error("Failed to fetch tables: #{e.message}") if defined?(Rails.logger)
      []
    end

    # Validate that a table exists
    def validate_table(table_name)
      return { valid: false, error: "Table name cannot be blank" } if table_name.blank?

      # Use case-insensitive comparison and sanitize input
      sanitized_name = sanitize(table_name)

      # First, check if table exists and get column count
      column_count_sql = <<~SQL.squish
        SELECT COUNT(*) as column_count
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND LOWER(table_name) = LOWER('#{sanitized_name}')
      SQL

      column_result = ActiveRecord::Base.connection.execute(column_count_sql).first
      column_count = column_result ? column_result["column_count"].to_i : 0

      if column_count.positive?
        # Get table comment separately
        comment_sql = <<~SQL.squish
          SELECT obj_description(c.oid, 'pg_class') as comment
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public'
          AND LOWER(c.relname) = LOWER('#{sanitized_name}')
          AND c.relkind = 'r'
        SQL

        comment_result = ActiveRecord::Base.connection.execute(comment_sql).first
        comment = comment_result ? comment_result["comment"] : nil

        {
          valid: true,
          table_name: table_name,
          column_count: column_count,
          comment: comment
        }
      else
        {
          valid: false,
          error: "Table '#{table_name}' not found in database"
        }
      end
    rescue StandardError => e
      Rails.logger.error("Table validation error for '#{table_name}': #{e.message}")
      {
        valid: false,
        error: e.message
      }
    end

    # Get table columns
    def table_columns(table_name)
      sql = <<~SQL.squish
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = '#{sanitize(table_name)}'
        ORDER BY ordinal_position
      SQL

      result = ActiveRecord::Base.connection.execute(sql)
      result.map do |row|
        {
          name: row["column_name"],
          type: row["data_type"],
          nullable: row["is_nullable"] == "YES"
        }
      end
    end

    # Check if function exists
    def function_exists?(function_name)
      sql = <<~SQL.squish
        SELECT COUNT(*) as count
        FROM pg_proc
        WHERE proname = '#{sanitize(function_name)}'
      SQL

      result = ActiveRecord::Base.connection.execute(sql).first
      result["count"].to_i.positive?
    end

    # Check if trigger exists
    def trigger_exists?(trigger_name)
      sql = <<~SQL.squish
        SELECT COUNT(*) as count
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE t.tgname = '#{sanitize(trigger_name)}'
        AND n.nspname = 'public'
        AND NOT t.tgisinternal
      SQL

      result = ActiveRecord::Base.connection.execute(sql).first
      result["count"].to_i.positive?
    rescue StandardError => e
      Rails.logger.error("Failed to check if trigger exists: #{e.message}") if defined?(Rails.logger)
      false
    end

    # Get all tables with their triggers and functions
    def tables_with_triggers
      # Get all tables
      tables = list_tables

      # Get all triggers from registry
      triggers_by_table = PgSqlTriggers::TriggerRegistry.all.group_by(&:table_name)

      # Get actual database triggers
      db_triggers_sql = <<~SQL.squish
        SELECT#{' '}
          t.tgname as trigger_name,
          c.relname as table_name,
          p.proname as function_name,
          pg_get_triggerdef(t.oid) as trigger_definition
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_proc p ON t.tgfoid = p.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE NOT t.tgisinternal
        AND n.nspname = 'public'
        ORDER BY c.relname, t.tgname
      SQL

      db_triggers = {}
      begin
        result = ActiveRecord::Base.connection.execute(db_triggers_sql)
        result.each do |row|
          table_name = row["table_name"]
          db_triggers[table_name] ||= []
          db_triggers[table_name] << {
            trigger_name: row["trigger_name"],
            function_name: row["function_name"],
            definition: row["trigger_definition"]
          }
        end
      rescue StandardError => e
        Rails.logger.error("Failed to fetch database triggers: #{e.message}")
      end

      # Combine registry and database triggers
      tables.map do |table_name|
        registry_triggers = triggers_by_table[table_name] || []
        db_table_triggers = db_triggers[table_name] || []

        {
          table_name: table_name,
          registry_triggers: registry_triggers.map do |t|
            {
              id: t.id,
              trigger_name: t.trigger_name,
              function_name: t.definition.present? ? JSON.parse(t.definition)["function_name"] : nil,
              enabled: t.enabled,
              version: t.version,
              source: t.source,
              function_body: t.function_body
            }
          end,
          database_triggers: db_table_triggers,
          trigger_count: registry_triggers.count + db_table_triggers.count
        }
      end
    end

    # Get triggers for a specific table
    def table_triggers(table_name)
      # From registry
      registry_triggers = PgSqlTriggers::TriggerRegistry.for_table(table_name)

      # From database
      db_triggers_sql = <<~SQL.squish
        SELECT#{' '}
          t.tgname as trigger_name,
          p.proname as function_name,
          pg_get_triggerdef(t.oid) as trigger_definition
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_proc p ON t.tgfoid = p.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE NOT t.tgisinternal
        AND c.relname = '#{sanitize(table_name)}'
        AND n.nspname = 'public'
        ORDER BY t.tgname
      SQL

      db_triggers = []
      begin
        result = ActiveRecord::Base.connection.execute(db_triggers_sql)
        result.each do |row|
          db_triggers << {
            trigger_name: row["trigger_name"],
            function_name: row["function_name"],
            definition: row["trigger_definition"]
          }
        end
      rescue StandardError => e
        Rails.logger.error("Failed to fetch database triggers: #{e.message}")
      end

      {
        table_name: table_name,
        registry_triggers: registry_triggers,
        database_triggers: db_triggers
      }
    end

    private

    def sanitize(value)
      ActiveRecord::Base.connection.quote_string(value.to_s)
    end
  end
end
