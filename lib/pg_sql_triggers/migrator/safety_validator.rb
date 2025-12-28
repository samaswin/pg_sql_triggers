# frozen_string_literal: true

require_relative "../drift/db_queries"

module PgSqlTriggers
  class Migrator
    # Validates that migrations don't blindly DROP + CREATE objects
    # This ensures safety by detecting unsafe patterns and blocking them
    class SafetyValidator
      # Error raised when unsafe DROP + CREATE operations are detected
      class UnsafeOperationError < PgSqlTriggers::UnsafeMigrationError
        def initialize(message, violations)
          super(message)
          @violations = violations
        end

        attr_reader :violations

        def violation_summary
          @violations.map { |v| "  - #{v[:message]}" }.join("\n")
        end
      end

      class << self
        # Validate that a migration doesn't perform unsafe DROP + CREATE operations
        # Raises UnsafeOperationError if unsafe patterns are detected
        def validate!(migration_instance, direction: :up, allow_unsafe: false)
          return if allow_unsafe

          violations = detect_unsafe_patterns(migration_instance, direction)
          return if violations.empty?

          error_message = build_error_message(violations, migration_instance.class.name)
          raise UnsafeOperationError.new(error_message, violations)
        end

        # Detect unsafe patterns in migration SQL
        # Returns array of violation hashes
        def detect_unsafe_patterns(migration_instance, direction)
          violations = []

          # Capture SQL that would be executed
          captured_sql = capture_sql(migration_instance, direction)

          # Parse SQL to detect unsafe patterns
          sql_operations = parse_sql_operations(captured_sql)

          # Check for explicit DROP + CREATE patterns (the main safety concern)
          violations.concat(detect_drop_create_patterns(sql_operations))

          violations
        end

        private

        # Capture SQL that would be executed by the migration
        def capture_sql(migration_instance, direction)
          captured = []

          # Override execute to capture SQL instead of executing
          migration_instance.define_singleton_method(:execute) do |sql|
            captured << sql.to_s.strip
          end

          # Call the migration method (up or down) to capture SQL
          migration_instance.public_send(direction)

          captured
        end

        # Parse SQL into structured operations
        def parse_sql_operations(sql_array)
          operations = {
            drops: [],
            creates: [],
            replaces: []
          }

          sql_array.each do |sql|
            sql_normalized = sql.squish

            # Parse DROP statements
            if sql_normalized.match?(/DROP\s+(TRIGGER|FUNCTION)/i)
              drop_info = parse_drop(sql)
              operations[:drops] << drop_info if drop_info
            end

            # Parse CREATE statements (without OR REPLACE)
            if sql_normalized.match?(/CREATE\s+(?!OR\s+REPLACE)(TRIGGER|FUNCTION)/i)
              create_info = parse_create(sql)
              operations[:creates] << create_info if create_info
            end

            # Parse CREATE OR REPLACE statements
            # (only for functions - PostgreSQL doesn't support CREATE OR REPLACE TRIGGER)
            if sql_normalized.match?(/CREATE\s+OR\s+REPLACE\s+FUNCTION/i)
              replace_info = parse_replace(sql)
              operations[:replaces] << replace_info if replace_info
            end
          end

          operations
        end

        # Parse DROP SQL statement
        def parse_drop(sql)
          if sql.match?(/DROP\s+TRIGGER/i)
            match = sql.match(/DROP\s+TRIGGER\s+(?:IF\s+EXISTS\s+)?(\w+)\s+ON\s+(\w+)/i)
            return nil unless match

            {
              type: :trigger,
              name: match[1],
              table_name: match[2],
              sql: sql
            }
          elsif sql.match?(/DROP\s+FUNCTION/i)
            match = sql.match(/DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(\w+)\s*\(\)?/i)
            return nil unless match

            {
              type: :function,
              name: match[1],
              sql: sql
            }
          end
        end

        # Parse CREATE SQL statement (without OR REPLACE)
        def parse_create(sql)
          if sql.match?(/CREATE\s+TRIGGER/i)
            match = sql.match(/CREATE\s+TRIGGER\s+(\w+)\s+.*?\s+ON\s+(\w+)/i)
            return nil unless match

            {
              type: :trigger,
              name: match[1],
              table_name: match[2],
              sql: sql
            }
          elsif sql.match?(/CREATE\s+FUNCTION/i)
            match = sql.match(/CREATE\s+FUNCTION\s+(\w+)\s*\([^)]*\)/i)
            return nil unless match

            # Extract function body for comparison
            body_match = sql.match(/\$\$(.+?)\$\$/m) || sql.match(/AS\s+(.+)/im)
            function_body = body_match ? body_match[1].strip : sql

            {
              type: :function,
              name: match[1],
              function_body: function_body,
              sql: sql
            }
          end
        end

        # Parse CREATE OR REPLACE SQL statement (only for functions)
        def parse_replace(sql)
          # PostgreSQL doesn't support CREATE OR REPLACE TRIGGER, only functions
          return unless sql.match?(/CREATE\s+OR\s+REPLACE\s+FUNCTION/i)

          match = sql.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(\w+)\s*\([^)]*\)/i)
          return nil unless match

          # Extract function body for comparison
          body_match = sql.match(/\$\$(.+?)\$\$/m) || sql.match(/AS\s+(.+)/im)
          function_body = body_match ? body_match[1].strip : sql

          {
            type: :function,
            name: match[1],
            function_body: function_body,
            sql: sql
          }
        end

        # Detect explicit DROP + CREATE patterns
        # This is unsafe because it drops existing objects and recreates them without validation
        def detect_drop_create_patterns(operations)
          violations = []

          # Check if any DROP is followed by a CREATE of the same object
          operations[:drops].each do |drop|
            matching_create = operations[:creates].find do |create|
              create[:type] == drop[:type] && create[:name] == drop[:name]
            end

            next unless matching_create

            object_type = drop[:type] == :trigger ? "trigger" : "function"
            existing_object = case drop[:type]
                              when :function
                                function_exists?(drop[:name])
                              when :trigger
                                trigger_exists?(drop[:name])
                              end

            # Only flag as unsafe if the object actually exists
            next unless existing_object

            violations << {
              type: :drop_create_pattern,
              message: "Unsafe DROP + CREATE pattern detected for #{object_type} '#{drop[:name]}'. " \
                       "Migration will drop existing #{object_type} and recreate it. " \
                       "For functions, use CREATE OR REPLACE FUNCTION instead. " \
                       "For triggers, drop and recreate is sometimes necessary, but ensure this is intentional.",
              drop_sql: drop[:sql],
              create_sql: matching_create[:sql],
              object_name: drop[:name],
              object_type: drop[:type]
            }
          end

          violations
        end

        # Check if function exists in database
        def function_exists?(function_name)
          Drift::DbQueries.find_function(function_name).present?
        end

        # Check if trigger exists in database
        def trigger_exists?(trigger_name)
          Drift::DbQueries.find_trigger(trigger_name).present?
        end

        # Build error message from violations
        def build_error_message(violations, migration_class_name)
          message = []
          message << ("=" * 80)
          message << "UNSAFE MIGRATION DETECTED"
          message << "Migration: #{migration_class_name}"
          message << ("=" * 80)
          message << ""
          message << "The migration contains unsafe DROP + CREATE operations that would:"
          message << ""
          message << violations.map { |v| "  - #{v[:message]}" }.join("\n")
          message << ""
          message << "To proceed despite these warnings, set ALLOW_UNSAFE_MIGRATIONS=true"
          message << "or configure pg_sql_triggers to allow unsafe operations."
          message << ""
          message << ("=" * 80)

          message.join("\n")
        end
      end
    end
  end
end
