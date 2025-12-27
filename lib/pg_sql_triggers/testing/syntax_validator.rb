# frozen_string_literal: true

module PgSqlTriggers
  module Testing
    class SyntaxValidator
      def initialize(trigger_registry)
        @trigger = trigger_registry
      end

      # Validate DSL structure
      def validate_dsl
        return { valid: false, errors: ["Missing definition"], definition: {} } if @trigger.definition.blank?

        definition = begin
          JSON.parse(@trigger.definition)
        rescue StandardError
          {}
        end
        errors = []

        errors << "Missing trigger name" if definition["name"].blank?
        errors << "Missing table name" if definition["table_name"].blank?
        errors << "Missing function name" if definition["function_name"].blank?
        errors << "Missing events" if definition["events"].blank?
        errors << "Invalid version" unless definition["version"].to_i.positive?

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
        rescue StandardError
          # Ignore rollback errors
        end
        { valid: false, error: e.message }
      end

      # Validate WHEN condition syntax
      def validate_condition
        return { valid: true } if @trigger.condition.blank?
        return { valid: false, error: "Table name is required for condition validation" } if @trigger.table_name.blank?

        if @trigger.definition.blank?
          return { valid: false,
                   error: "Function name is required for condition validation" }
        end

        definition = begin
          JSON.parse(@trigger.definition)
        rescue StandardError
          {}
        end
        function_name = definition["function_name"] || "test_validation_function"
        sanitized_table = ActiveRecord::Base.connection.quote_string(@trigger.table_name)
        sanitized_function = ActiveRecord::Base.connection.quote_string(function_name)
        sanitized_condition = @trigger.condition

        # Validate condition by creating a temporary trigger with the condition
        # This is the only way to validate WHEN conditions since they use NEW/OLD
        test_function_sql = <<~SQL.squish
          CREATE OR REPLACE FUNCTION #{sanitized_function}() RETURNS TRIGGER AS $$
          BEGIN
            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;
        SQL

        test_trigger_sql = <<~SQL.squish
          CREATE TRIGGER test_validation_trigger
          BEFORE INSERT ON #{sanitized_table}
          FOR EACH ROW
          WHEN (#{sanitized_condition})
          EXECUTE FUNCTION #{sanitized_function}();
        SQL

        ActiveRecord::Base.connection.execute("BEGIN")
        ActiveRecord::Base.connection.execute(test_function_sql)
        ActiveRecord::Base.connection.execute(test_trigger_sql)
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_validation_trigger ON #{sanitized_table}")
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS #{sanitized_function}()")
        ActiveRecord::Base.connection.execute("ROLLBACK")

        { valid: true, message: "Condition syntax is valid" }
      rescue ActiveRecord::StatementInvalid => e
        begin
          ActiveRecord::Base.connection.execute("ROLLBACK")
        rescue StandardError
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
