# frozen_string_literal: true

module PgTriggers
  module Testing
    class SyntaxValidator
      def initialize(trigger_registry)
        @trigger = trigger_registry
      end

      # Validate DSL structure
      def validate_dsl
        definition = JSON.parse(@trigger.definition)
        errors = []

        errors << "Missing trigger name" if definition["name"].blank?
        errors << "Missing table name" if definition["table_name"].blank?
        errors << "Missing function name" if definition["function_name"].blank?
        errors << "Missing events" if definition["events"].blank?
        errors << "Invalid version" unless definition["version"].to_i > 0

        {
          valid: errors.empty?,
          errors: errors,
          definition: definition
        }
      end

      # Validate PL/pgSQL function syntax (uses PostgreSQL's parser)
      def validate_function_syntax
        return { valid: false, error: "No function body defined" } if @trigger.function_body.blank?

        ActiveRecord::Base.connection.execute("BEGIN")
        ActiveRecord::Base.connection.execute(@trigger.function_body)
        ActiveRecord::Base.connection.execute("ROLLBACK")

        { valid: true, message: "Function syntax is valid" }
      rescue ActiveRecord::StatementInvalid => e
        begin
          ActiveRecord::Base.connection.execute("ROLLBACK")
        rescue
          # Ignore rollback errors
        end
        { valid: false, error: e.message }
      end

      # Validate WHEN condition syntax
      def validate_condition
        return { valid: true } if @trigger.condition.blank?

        # Try to parse condition in a dummy SELECT
        test_sql = "SELECT * FROM #{@trigger.table_name} WHERE #{@trigger.condition} LIMIT 0"

        ActiveRecord::Base.connection.execute("BEGIN")
        ActiveRecord::Base.connection.execute(test_sql)
        ActiveRecord::Base.connection.execute("ROLLBACK")

        { valid: true, message: "Condition syntax is valid" }
      rescue ActiveRecord::StatementInvalid => e
        begin
          ActiveRecord::Base.connection.execute("ROLLBACK")
        rescue
          # Ignore rollback errors
        end
        { valid: false, error: e.message }
      end

      # Run all validations
      def validate_all
        dsl_result = validate_dsl
        function_result = validate_function_syntax
        condition_result = validate_condition

        {
          dsl: dsl_result,
          function: function_result,
          condition: condition_result,
          overall_valid: dsl_result[:valid] &&
                        function_result[:valid] &&
                        condition_result[:valid]
        }
      end
    end
  end
end
