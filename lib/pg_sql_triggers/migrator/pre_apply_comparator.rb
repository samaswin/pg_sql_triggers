# frozen_string_literal: true

require_relative "../drift/db_queries"

module PgSqlTriggers
  class Migrator
    # Pre-apply comparator that extracts expected SQL from migrations
    # and compares it with the current database state
    class PreApplyComparator
      class << self
        # Compare expected state from migration with actual database state
        # Returns a comparison result with diff information
        def compare(migration_instance, direction: :up)
          expected = extract_expected_state(migration_instance, direction)
          actual = extract_actual_state(expected)
          generate_diff(expected, actual)
        end

        private

        # Extract expected SQL and state from migration instance
        def extract_expected_state(migration_instance, direction)
          captured_sql = capture_sql(migration_instance, direction)
          parse_sql_to_state(captured_sql)
        end

        # Capture SQL that would be executed by the migration
        def capture_sql(migration_instance, direction)
          captured = []

          # Override execute to capture SQL instead of executing
          # Since we use a separate instance for comparison, we don't need to restore
          migration_instance.define_singleton_method(:execute) do |sql|
            captured << sql.to_s.strip
          end

          # Call the migration method (up or down) to capture SQL
          migration_instance.public_send(direction)

          captured
        end

        # Parse captured SQL into structured state (triggers, functions)
        def parse_sql_to_state(sql_array)
          state = {
            functions: [],
            triggers: []
          }

          sql_array.each do |sql|
            sql_normalized = sql.squish

            # Parse CREATE FUNCTION statements
            if sql_normalized.match?(/CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i)
              function_info = parse_function_sql(sql)
              state[:functions] << function_info if function_info
            end

            # Parse CREATE TRIGGER statements
            if sql_normalized.match?(/CREATE\s+TRIGGER/i)
              trigger_info = parse_trigger_sql(sql)
              state[:triggers] << trigger_info if trigger_info
            end

            # Parse DROP statements (for down migrations)
            next unless sql_normalized.match?(/DROP\s+(TRIGGER|FUNCTION)/i)

            drop_info = parse_drop_sql(sql)
            state[:drops] ||= []
            state[:drops] << drop_info if drop_info
          end

          state
        end

        # Parse function SQL to extract function name and body
        def parse_function_sql(sql)
          # Match CREATE [OR REPLACE] FUNCTION function_name(...) ... AS $$ body $$
          match = sql.match(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(\w+)\s*\([^)]*\)/i)
          return nil unless match

          function_name = match[1]

          # Extract function body (between $$ markers or AS ...)
          body_match = sql.match(/\$\$(.+?)\$\$/m) || sql.match(/AS\s+(.+)/im)
          function_body = body_match ? body_match[1].strip : sql

          {
            function_name: function_name,
            function_body: function_body,
            full_sql: sql
          }
        end

        # Parse trigger SQL to extract trigger details
        def parse_trigger_sql(sql)
          # Match CREATE TRIGGER trigger_name BEFORE/AFTER events ON table_name ...
          match = sql.match(/CREATE\s+TRIGGER\s+(\w+)\s+(BEFORE|AFTER)\s+([^ON]+)\s+ON\s+(\w+)/i)
          return nil unless match

          trigger_name = match[1]
          timing = match[2]
          events = match[3].strip.split(/\s+OR\s+/i).map(&:strip)
          table_name = match[4]

          # Extract WHEN condition if present
          condition_match = sql.match(/WHEN\s+\(([^)]+)\)/i)
          condition = condition_match ? condition_match[1].strip : nil

          # Extract function name
          function_match = sql.match(/EXECUTE\s+FUNCTION\s+(\w+)\s*\(\)/i)
          function_name = function_match ? function_match[1] : nil

          {
            trigger_name: trigger_name,
            table_name: table_name,
            timing: timing,
            events: events,
            condition: condition,
            function_name: function_name,
            full_sql: sql
          }
        end

        # Parse DROP SQL statements
        def parse_drop_sql(sql)
          if sql.match?(/DROP\s+TRIGGER/i)
            match = sql.match(/DROP\s+TRIGGER\s+(?:IF\s+EXISTS\s+)?(\w+)\s+ON\s+(\w+)/i)
            return nil unless match

            {
              type: :trigger,
              name: match[1],
              table_name: match[2]
            }
          elsif sql.match?(/DROP\s+FUNCTION/i)
            match = sql.match(/DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(\w+)\s*\(\)/i)
            return nil unless match

            {
              type: :function,
              name: match[1]
            }
          end
        end

        # Extract actual state from database
        def extract_actual_state(expected)
          actual = {
            functions: {},
            triggers: {}
          }

          # Get actual functions from database
          expected[:functions].each do |expected_func|
            db_func = Drift::DbQueries.find_function(expected_func[:function_name])
            actual[:functions][expected_func[:function_name]] = if db_func
                                                                  {
                                                                    function_name: db_func["function_name"],
                                                                    function_body: db_func["function_definition"],
                                                                    exists: true
                                                                  }
                                                                else
                                                                  {
                                                                    function_name: expected_func[:function_name],
                                                                    exists: false
                                                                  }
                                                                end
          end

          # Get actual triggers from database
          expected[:triggers].each do |expected_trigger|
            db_trigger = Drift::DbQueries.find_trigger(expected_trigger[:trigger_name])
            if db_trigger
              actual[:triggers][expected_trigger[:trigger_name]] = {
                trigger_name: db_trigger["trigger_name"],
                table_name: db_trigger["table_name"],
                function_name: db_trigger["function_name"],
                trigger_definition: db_trigger["trigger_definition"],
                function_definition: db_trigger["function_definition"],
                exists: true
              }
            else
              actual[:triggers][expected_trigger[:trigger_name]] = {
                trigger_name: expected_trigger[:trigger_name],
                table_name: expected_trigger[:table_name],
                exists: false
              }
            end
          end

          actual
        end

        # Generate diff between expected and actual state
        def generate_diff(expected, actual)
          diff = {
            has_differences: false,
            functions: [],
            triggers: [],
            drops: expected[:drops] || []
          }

          # Compare functions
          expected[:functions].each do |expected_func|
            func_name = expected_func[:function_name]
            actual_func = actual[:functions][func_name]

            if !actual_func || !actual_func[:exists]
              diff[:functions] << {
                function_name: func_name,
                status: :new,
                expected: expected_func[:function_body],
                actual: nil,
                message: "Function will be created"
              }
              diff[:has_differences] = true
            elsif actual_func[:function_body] != expected_func[:function_body]
              diff[:functions] << {
                function_name: func_name,
                status: :modified,
                expected: expected_func[:function_body],
                actual: actual_func[:function_body],
                message: "Function body differs from expected"
              }
              diff[:has_differences] = true
            else
              diff[:functions] << {
                function_name: func_name,
                status: :unchanged,
                message: "Function matches expected state"
              }
            end
          end

          # Compare triggers
          expected[:triggers].each do |expected_trigger|
            trigger_name = expected_trigger[:trigger_name]
            actual_trigger = actual[:triggers][trigger_name]

            if !actual_trigger || !actual_trigger[:exists]
              diff[:triggers] << {
                trigger_name: trigger_name,
                status: :new,
                expected: expected_trigger[:full_sql],
                actual: nil,
                message: "Trigger will be created"
              }
              diff[:has_differences] = true
            else
              # Compare trigger definitions
              expected_def = normalize_trigger_definition(expected_trigger)
              actual_def = normalize_trigger_definition_from_db(actual_trigger)

              if expected_def == actual_def
                diff[:triggers] << {
                  trigger_name: trigger_name,
                  status: :unchanged,
                  message: "Trigger matches expected state"
                }
              else
                diff[:triggers] << {
                  trigger_name: trigger_name,
                  status: :modified,
                  expected: expected_trigger[:full_sql],
                  actual: actual_trigger[:trigger_definition],
                  message: "Trigger definition differs from expected",
                  differences: compare_trigger_details(expected_trigger, actual_trigger)
                }
                diff[:has_differences] = true
              end
            end
          end

          diff
        end

        # Normalize trigger definition for comparison
        def normalize_trigger_definition(trigger)
          {
            trigger_name: trigger[:trigger_name],
            table_name: trigger[:table_name],
            events: trigger[:events].sort,
            condition: trigger[:condition],
            function_name: trigger[:function_name]
          }
        end

        # Normalize trigger definition from database for comparison
        def normalize_trigger_definition_from_db(db_trigger)
          # Parse trigger definition from pg_get_triggerdef output
          def_str = db_trigger[:trigger_definition] || ""

          # Extract events, condition, etc. from definition string
          events_match = def_str.match(/BEFORE\s+(.+?)\s+ON/i) || def_str.match(/AFTER\s+(.+?)\s+ON/i)
          events = events_match ? events_match[1].split(/\s+OR\s+/i).map(&:strip).sort : []

          condition_match = def_str.match(/WHEN\s+\(([^)]+)\)/i)
          condition = condition_match ? condition_match[1].strip : nil

          {
            trigger_name: db_trigger[:trigger_name],
            table_name: db_trigger[:table_name],
            events: events,
            condition: condition,
            function_name: db_trigger[:function_name]
          }
        end

        # Compare trigger details to find specific differences
        def compare_trigger_details(expected, actual_db_trigger)
          differences = []

          # Normalize actual trigger for comparison
          actual = normalize_trigger_definition_from_db(actual_db_trigger)

          if expected[:table_name] != actual[:table_name]
            differences << "Table name: expected '#{expected[:table_name]}', actual '#{actual[:table_name]}'"
          end

          expected_events = expected[:events].sort
          actual_events = actual[:events] || []
          if expected_events != actual_events.sort
            differences << "Events: expected #{expected_events.inspect}, actual #{actual_events.inspect}"
          end

          if expected[:condition] != actual[:condition]
            differences << "Condition: expected '#{expected[:condition]}', actual '#{actual[:condition]}'"
          end

          if expected[:function_name] != actual[:function_name]
            differences << "Function: expected '#{expected[:function_name]}', actual '#{actual[:function_name]}'"
          end

          differences
        end
      end
    end
  end
end
