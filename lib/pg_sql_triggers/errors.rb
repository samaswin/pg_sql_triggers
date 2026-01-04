# frozen_string_literal: true

module PgSqlTriggers
  # Base error class for all PgSqlTriggers errors
  #
  # All errors in PgSqlTriggers inherit from this base class and include
  # error codes for programmatic handling, standardized messages, and
  # recovery suggestions.
  class Error < StandardError
    attr_reader :error_code, :recovery_suggestion, :context

    def initialize(message = nil, error_code: nil, recovery_suggestion: nil, context: {})
      @context = context || {}
      @error_code = error_code || default_error_code
      @recovery_suggestion = recovery_suggestion || default_recovery_suggestion
      super(message || default_message)
    end

    # Returns a user-friendly error message suitable for UI display
    def user_message
      msg = message
      msg += "\n\nRecovery: #{recovery_suggestion}" if recovery_suggestion
      msg
    end

    # Returns error details as a hash for programmatic access
    def to_h
      {
        error_class: self.class.name,
        error_code: error_code,
        message: message,
        recovery_suggestion: recovery_suggestion,
        context: context
      }
    end

    protected

    def default_error_code
      # Convert class name to error code (e.g., "PermissionError" -> "PERMISSION_ERROR")
      class_name = self.class.name.split("::").last
      class_name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                .upcase
    end

    def default_message
      "An error occurred in PgSqlTriggers"
    end

    def default_recovery_suggestion
      "Please check the logs for more details and contact support if the issue persists."
    end
  end

  # Error raised when permission checks fail
  #
  # @example
  #   raise PgSqlTriggers::PermissionError.new(
  #     "Permission denied: enable_trigger requires Operator level access",
  #     error_code: "PERMISSION_DENIED",
  #     recovery_suggestion: "Contact your administrator to request Operator or Admin access",
  #     context: { action: :enable_trigger, required_role: "Operator" }
  #   )
  class PermissionError < Error
    def default_error_code
      "PERMISSION_DENIED"
    end

    def default_message
      "Permission denied for this operation"
    end

    def default_recovery_suggestion
      if context[:required_role]
        "This operation requires #{context[:required_role]} level access. " \
          "Contact your administrator to request appropriate permissions."
      else
        "This operation requires elevated permissions. Contact your administrator."
      end
    end
  end

  # Error raised when kill switch blocks an operation
  #
  # @example
  #   raise PgSqlTriggers::KillSwitchError.new(
  #     "Kill switch is active for production environment",
  #     error_code: "KILL_SWITCH_ACTIVE",
  #     recovery_suggestion: "Provide confirmation text to override: EXECUTE OPERATION_NAME",
  #     context: { operation: :trigger_enable, environment: "production" }
  #   )
  class KillSwitchError < Error
    def default_error_code
      "KILL_SWITCH_ACTIVE"
    end

    def default_message
      "Kill switch is active for this environment"
    end

    def default_recovery_suggestion
      ctx = @context || {}
      ctx[:operation] || "this operation"
      environment = ctx[:environment] || "this environment"
      "Kill switch is active for #{environment}. " \
        "To override, provide the required confirmation text. " \
        "For CLI/rake tasks, use: KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT=\"...\" rake your:task"
    end
  end

  # Error raised when drift is detected
  #
  # @example
  #   raise PgSqlTriggers::DriftError.new(
  #     "Trigger 'users_email_validation' has drifted from definition",
  #     error_code: "DRIFT_DETECTED",
  #     recovery_suggestion: "Run migration to sync trigger, or re-execute trigger to apply current definition",
  #     context: { trigger_name: "users_email_validation", drift_type: "function_body" }
  #   )
  class DriftError < Error
    def default_error_code
      "DRIFT_DETECTED"
    end

    def default_message
      "Trigger has drifted from its definition"
    end

    def default_recovery_suggestion
      trigger_name = context[:trigger_name] || "trigger"
      "Trigger '#{trigger_name}' has drifted. " \
        "Run 'rake trigger:migrate' to sync the trigger, or use the re-execute feature " \
        "to apply the current definition."
    end
  end

  # Error raised when validation fails
  #
  # @example
  #   raise PgSqlTriggers::ValidationError.new(
  #     "Invalid trigger definition: table name is required",
  #     error_code: "VALIDATION_FAILED",
  #     recovery_suggestion: "Ensure all required fields are provided in the trigger definition",
  #     context: { field: :table_name, errors: ["is required"] }
  #   )
  class ValidationError < Error
    def default_error_code
      "VALIDATION_FAILED"
    end

    def default_message
      "Validation failed"
    end

    def default_recovery_suggestion
      if context[:field]
        "Please fix the #{context[:field]} field and try again."
      else
        "Please review the input and ensure all required fields are provided."
      end
    end
  end

  # Error raised when SQL execution fails
  #
  # @example
  #   raise PgSqlTriggers::ExecutionError.new(
  #     "SQL execution failed: syntax error near 'INVALID'",
  #     error_code: "EXECUTION_FAILED",
  #     recovery_suggestion: "Review SQL syntax and ensure all references are valid",
  #     context: { sql: "SELECT * FROM...", database_error: "..." }
  #   )
  class ExecutionError < Error
    def default_error_code
      "EXECUTION_FAILED"
    end

    def default_message
      "SQL execution failed"
    end

    def default_recovery_suggestion
      if context[:database_error]
        "Review the SQL syntax and database error. Ensure all table and column names are correct."
      else
        "Review the SQL and ensure it is valid PostgreSQL syntax."
      end
    end
  end

  # Error raised when unsafe migrations are attempted
  #
  # @example
  #   raise PgSqlTriggers::UnsafeMigrationError.new(
  #     "Migration contains unsafe DROP + CREATE operations",
  #     error_code: "UNSAFE_MIGRATION",
  #     recovery_suggestion: "Review migration safety or set allow_unsafe_migrations=true",
  #     context: { violations: [...] }
  #   )
  class UnsafeMigrationError < Error
    def default_error_code
      "UNSAFE_MIGRATION"
    end

    def default_message
      "Migration contains unsafe operations"
    end

    def default_recovery_suggestion
      "Review the migration for unsafe operations. " \
        "If you are certain the migration is safe, you can set " \
        "PgSqlTriggers.configure { |c| c.allow_unsafe_migrations = true } " \
        "or use the kill switch override mechanism."
    end
  end

  # Error raised when a trigger is not found
  #
  # @example
  #   raise PgSqlTriggers::NotFoundError.new(
  #     "Trigger 'users_email_validation' not found",
  #     error_code: "TRIGGER_NOT_FOUND",
  #     recovery_suggestion: "Verify trigger name or create the trigger first",
  #     context: { trigger_name: "users_email_validation" }
  #   )
  class NotFoundError < Error
    def default_error_code
      "NOT_FOUND"
    end

    def default_message
      "Resource not found"
    end

    def default_recovery_suggestion
      if context[:trigger_name]
        "Trigger '#{context[:trigger_name]}' not found. " \
          "Verify the trigger name or create the trigger first using the generator or DSL."
      else
        "The requested resource was not found. Verify the identifier and try again."
      end
    end
  end
end
