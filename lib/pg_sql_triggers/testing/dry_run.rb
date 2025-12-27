# frozen_string_literal: true

module PgTriggers
  module Testing
    class DryRun
      def initialize(trigger_registry)
        @trigger = trigger_registry
      end

      # Generate SQL that WOULD be executed (but don't execute)
      def generate_sql
        definition = JSON.parse(@trigger.definition)
        events = definition["events"].map(&:upcase).join(" OR ")

        sql_parts = []

        # 1. Function creation SQL
        if @trigger.function_body.present?
          sql_parts << {
            type: "CREATE FUNCTION",
            sql: @trigger.function_body,
            description: "Creates the trigger function '#{definition['function_name']}'"
          }
        end

        # 2. Trigger creation SQL
        trigger_timing = "BEFORE" # Could be configurable
        trigger_level = "ROW"     # Could be configurable

        trigger_sql = <<~SQL
          CREATE TRIGGER #{@trigger.trigger_name}
          #{trigger_timing} #{events} ON #{@trigger.table_name}
          FOR EACH #{trigger_level}
        SQL

        trigger_sql += "WHEN (#{@trigger.condition})\n" if @trigger.condition.present?
        trigger_sql += "EXECUTE FUNCTION #{definition['function_name']}();"

        sql_parts << {
          type: "CREATE TRIGGER",
          sql: trigger_sql,
          description: "Creates the trigger '#{@trigger.trigger_name}' on table '#{@trigger.table_name}'"
        }

        {
          success: true,
          sql_parts: sql_parts,
          estimated_impact: estimate_impact
        }
      end

      # Show what tables/functions would be affected
      def estimate_impact
        definition = JSON.parse(@trigger.definition)
        {
          tables_affected: [@trigger.table_name],
          functions_created: [definition["function_name"]],
          triggers_created: [@trigger.trigger_name]
        }
      end

      # Explain the execution plan (does not execute trigger)
      def explain
        sql = generate_sql[:sql_parts].map { |p| p[:sql] }.join("\n\n")

        {
          success: true,
          sql: sql,
          note: "This is a preview only. No changes will be made to the database."
        }
      end
    end
  end
end
