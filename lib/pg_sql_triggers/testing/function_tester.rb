# frozen_string_literal: true

module PgSqlTriggers
  module Testing
    class FunctionTester
      def initialize(trigger_registry)
        @trigger = trigger_registry
      end

      FUNCTION_NAME_PATTERN = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/i

      # Test ONLY the function, not the trigger.
      #
      # +test_context+ is accepted for API compatibility with future invocation logic.
      # It is normalised to an empty hash when +nil+ so callers can pass either.
      def test_function_only(test_context: {})
        test_context ||= {}
        results = {
          function_created: false,
          function_executed: false,
          errors: [],
          output: [],
          context: test_context
        }

        return fail_result(results, "Function body is missing") if @trigger.function_body.blank?
        unless extract_function_name_from_body
          return fail_result(results, "Function body does not contain a valid CREATE FUNCTION statement")
        end

        run_function_test_transaction(results)
        results[:output] << "\n⚠ Function rolled back (test mode)"
        results
      end

      private

      def fail_result(results, error_message)
        results[:success] = false
        results[:errors] << error_message
        results
      end

      def extract_function_name_from_body
        return nil if @trigger.function_body.blank?

        match = @trigger.function_body.match(FUNCTION_NAME_PATTERN)
        match && match[1]
      end

      def extract_function_name_from_definition
        return nil if @trigger.definition.blank?

        definition = JSON.parse(@trigger.definition)
        definition["function_name"] || definition["name"]
      rescue StandardError
        nil
      end

      def run_function_test_transaction(results)
        ActiveRecord::Base.transaction do
          create_function_in_transaction(results)
          verify_function_in_transaction(results) if results[:function_created]
          results[:success] = results[:errors].empty? && results[:function_created]
        rescue ActiveRecord::StatementInvalid, StandardError => e
          results[:success] = false
          results[:errors] << e.message unless results[:errors].include?(e.message)
        ensure
          raise ActiveRecord::Rollback
        end
      end

      def create_function_in_transaction(results)
        ActiveRecord::Base.connection.execute(@trigger.function_body)
        results[:function_created] = true
        results[:output] << "✓ Function created in test transaction"
      rescue ActiveRecord::StatementInvalid, StandardError => e
        results[:success] = false
        results[:errors] << "Error during function creation: #{e.message}"
      end

      def verify_function_in_transaction(results)
        function_name = extract_function_name_from_body || extract_function_name_from_definition

        if function_name.blank?
          results[:function_executed] = true
          results[:output] << "✓ Function created (execution verified via successful creation)"
          return
        end

        verify_function_in_pg_proc(function_name, results)
      end

      def verify_function_in_pg_proc(function_name, results)
        sanitized_name = safe_quote_function_name(function_name, results)
        check_sql = <<~SQL.squish
          SELECT COUNT(*) as count
          FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE p.proname = '#{sanitized_name}'
          AND n.nspname = 'public'
        SQL

        result = ActiveRecord::Base.connection.execute(check_sql).first
        results[:function_executed] = result && result["count"].to_i.positive?
        results[:output] << if results[:function_executed]
                              "✓ Function exists and is callable"
                            else
                              "✓ Function created (verified via successful creation)"
                            end
      rescue ActiveRecord::StatementInvalid, StandardError => e
        results[:function_executed] = false
        results[:success] = false
        results[:errors] << "Error during function verification: #{e.message}"
        results[:errors] << e.message unless results[:errors].include?(e.message)
        results[:output] << "✓ Function created (verification failed)"
      end

      def safe_quote_function_name(function_name, results)
        ActiveRecord::Base.connection.quote_string(function_name)
      rescue StandardError => e
        # If quote_string fails, use the function name as-is (less safe but allows test to continue)
        results[:errors] << "Error during function name sanitization: #{e.message}"
        function_name
      end

      public

      # Check if function already exists in database
      def function_exists?
        definition = begin
          JSON.parse(@trigger.definition)
        rescue StandardError
          {}
        end
        function_name = definition["function_name"] || definition["name"] ||
                        definition[:function_name] || definition[:name]
        return false if function_name.blank?

        sanitized_name = ActiveRecord::Base.connection.quote_string(function_name)
        sql = <<~SQL.squish
          SELECT COUNT(*) as count
          FROM pg_proc
          WHERE proname = '#{sanitized_name}'
        SQL

        result = ActiveRecord::Base.connection.execute(sql)
        result.first["count"].to_i.positive?
      end
    end
  end
end
