# frozen_string_literal: true

module PgTriggers
  module Testing
    class SafeExecutor
      def initialize(trigger_registry)
        @trigger = trigger_registry
      end

      # Execute trigger in a transaction and rollback
      def test_execute(test_data: nil)
        results = {
          function_created: false,
          trigger_created: false,
          test_insert_executed: false,
          errors: [],
          output: []
        }

        ActiveRecord::Base.transaction do
          begin
            # Step 1: Create function
            if @trigger.function_body.present?
              ActiveRecord::Base.connection.execute(@trigger.function_body)
              results[:function_created] = true
              results[:output] << "✓ Function created successfully"
            end

            # Step 2: Create trigger
            trigger_sql = DryRun.new(@trigger).generate_sql[:sql_parts]
                                .find { |p| p[:type] == "CREATE TRIGGER" }[:sql]
            ActiveRecord::Base.connection.execute(trigger_sql)
            results[:trigger_created] = true
            results[:output] << "✓ Trigger created successfully"

            # Step 3: Test with sample data (if provided)
            if test_data
              test_sql = build_test_insert(test_data)
              ActiveRecord::Base.connection.execute(test_sql)
              results[:test_insert_executed] = true
              results[:output] << "✓ Test insert executed successfully"
            end

            results[:success] = true

          rescue ActiveRecord::StatementInvalid => e
            results[:success] = false
            results[:errors] << e.message
          ensure
            # ALWAYS ROLLBACK - this is a test!
            raise ActiveRecord::Rollback
          end
        end

        results[:output] << "\n⚠ All changes rolled back (test mode)"
        results
      end

      private

      def build_test_insert(test_data)
        columns = test_data.keys.join(", ")
        values = test_data.values.map { |v| ActiveRecord::Base.connection.quote(v) }.join(", ")

        "INSERT INTO #{@trigger.table_name} (#{columns}) VALUES (#{values})"
      end
    end
  end
end
