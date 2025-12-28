# frozen_string_literal: true

module PgSqlTriggers
  module Drift
    module DbQueries
      class << self
        # Fetch all triggers from database
        def all_triggers
          sql = <<~SQL.squish
            SELECT
              t.oid AS trigger_oid,
              t.tgname AS trigger_name,
              c.relname AS table_name,
              n.nspname AS schema_name,
              p.proname AS function_name,
              pg_get_triggerdef(t.oid) AS trigger_definition,
              pg_get_functiondef(p.oid) AS function_definition,
              t.tgenabled AS enabled,
              t.tgisinternal AS is_internal
            FROM pg_trigger t
            JOIN pg_class c ON t.tgrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            JOIN pg_proc p ON t.tgfoid = p.oid
            WHERE NOT t.tgisinternal
              AND n.nspname = 'public'
              AND t.tgname NOT LIKE 'RI_%'
            ORDER BY c.relname, t.tgname;
          SQL

          execute_query(sql)
        end

        # Fetch single trigger
        def find_trigger(trigger_name)
          sql = <<~SQL.squish
            SELECT
              t.oid AS trigger_oid,
              t.tgname AS trigger_name,
              c.relname AS table_name,
              n.nspname AS schema_name,
              p.proname AS function_name,
              pg_get_triggerdef(t.oid) AS trigger_definition,
              pg_get_functiondef(p.oid) AS function_definition,
              t.tgenabled AS enabled,
              t.tgisinternal AS is_internal
            FROM pg_trigger t
            JOIN pg_class c ON t.tgrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            JOIN pg_proc p ON t.tgfoid = p.oid
            WHERE t.tgname = $1
              AND NOT t.tgisinternal
              AND n.nspname = 'public';
          SQL

          result = execute_query(sql, [trigger_name])
          result.first
        end

        # Fetch triggers for a specific table
        def find_triggers_for_table(table_name)
          sql = <<~SQL.squish
            SELECT
              t.oid AS trigger_oid,
              t.tgname AS trigger_name,
              c.relname AS table_name,
              n.nspname AS schema_name,
              p.proname AS function_name,
              pg_get_triggerdef(t.oid) AS trigger_definition,
              pg_get_functiondef(p.oid) AS function_definition,
              t.tgenabled AS enabled,
              t.tgisinternal AS is_internal
            FROM pg_trigger t
            JOIN pg_class c ON t.tgrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            JOIN pg_proc p ON t.tgfoid = p.oid
            WHERE c.relname = $1
              AND NOT t.tgisinternal
              AND n.nspname = 'public'
              AND t.tgname NOT LIKE 'RI_%'
            ORDER BY t.tgname;
          SQL

          execute_query(sql, [table_name])
        end

        # Fetch function body by function name
        def find_function(function_name)
          sql = <<~SQL.squish
            SELECT
              p.proname AS function_name,
              pg_get_functiondef(p.oid) AS function_definition
            FROM pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            WHERE p.proname = $1
              AND n.nspname = 'public';
          SQL

          result = execute_query(sql, [function_name])
          result.first
        end

        private

        def execute_query(sql, params = [])
          if params.any?
            # Use ActiveRecord's connection to execute parameterized queries
            result = ActiveRecord::Base.connection.exec_query(sql, "SQL", params)
            result.to_a
          else
            ActiveRecord::Base.connection.execute(sql).to_a
          end
        end
      end
    end
  end
end
