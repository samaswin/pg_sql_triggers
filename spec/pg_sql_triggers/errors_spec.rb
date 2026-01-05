# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Error do
  describe "base Error class" do
    describe "#initialize" do
      it "initializes with default values" do
        error = described_class.new
        expect(error.message).to eq("An error occurred in PgSqlTriggers")
        expect(error.error_code).to eq("ERROR")
        expect(error.recovery_suggestion).to eq("Please check the logs for more details and contact support if the issue persists.")
        expect(error.context).to eq({})
      end

      it "initializes with custom message" do
        error = described_class.new("Custom error message")
        expect(error.message).to eq("Custom error message")
      end

      it "initializes with custom error_code" do
        error = described_class.new(nil, error_code: "CUSTOM_ERROR")
        expect(error.error_code).to eq("CUSTOM_ERROR")
      end

      it "initializes with custom recovery_suggestion" do
        error = described_class.new(nil, recovery_suggestion: "Try again later")
        expect(error.recovery_suggestion).to eq("Try again later")
      end

      it "initializes with custom context" do
        context = { key: "value", nested: { data: 123 } }
        error = described_class.new(nil, context: context)
        expect(error.context).to eq(context)
      end

      it "handles nil context" do
        error = described_class.new(nil, context: nil)
        expect(error.context).to eq({})
      end

      it "initializes with all parameters" do
        context = { operation: "test" }
        error = described_class.new(
          "Test error",
          error_code: "TEST_ERROR",
          recovery_suggestion: "Fix it",
          context: context
        )
        expect(error.message).to eq("Test error")
        expect(error.error_code).to eq("TEST_ERROR")
        expect(error.recovery_suggestion).to eq("Fix it")
        expect(error.context).to eq(context)
      end
    end

    describe "#user_message" do
      it "returns the error message with default recovery suggestion when recovery_suggestion is nil" do
        error = described_class.new("Simple error", recovery_suggestion: nil)
        expect(error.user_message).to include("Simple error")
        expect(error.user_message).to include("Recovery:")
      end

      it "returns message with recovery suggestion" do
        error = described_class.new(
          "Error occurred",
          recovery_suggestion: "Try again"
        )
        expect(error.user_message).to eq("Error occurred\n\nRecovery: Try again")
      end

      it "returns message with empty recovery suggestion" do
        error = described_class.new("Error", recovery_suggestion: "")
        expect(error.user_message).to eq("Error\n\nRecovery: ")
      end
    end

    describe "#to_h" do
      it "returns error details as hash" do
        context = { key: "value" }
        error = described_class.new(
          "Test error",
          error_code: "TEST_ERROR",
          recovery_suggestion: "Fix it",
          context: context
        )
        hash = error.to_h
        expect(hash).to eq({
                             error_class: "PgSqlTriggers::Error",
                             error_code: "TEST_ERROR",
                             message: "Test error",
                             recovery_suggestion: "Fix it",
                             context: context
                           })
      end

      it "includes all error attributes in hash" do
        error = described_class.new
        hash = error.to_h
        expect(hash.keys).to contain_exactly(:error_class, :error_code, :message, :recovery_suggestion, :context)
      end
    end

    describe "#default_error_code" do
      it "converts class name to error code for Error class" do
        error = described_class.new
        expect(error.send(:default_error_code)).to eq("ERROR")
      end

      it "converts class name with multiple words to error code" do
        # Create a test class to verify the conversion logic
        test_class = Class.new(described_class) do
          def self.name
            "PgSqlTriggers::TestErrorClass"
          end
        end
        error = test_class.new
        expect(error.send(:default_error_code)).to eq("TEST_ERROR_CLASS")
      end

      it "handles consecutive capital letters correctly" do
        test_class = Class.new(described_class) do
          def self.name
            "PgSqlTriggers::HTTPError"
          end
        end
        error = test_class.new
        expect(error.send(:default_error_code)).to eq("HTTP_ERROR")
      end
    end

    describe "#default_message" do
      it "returns default message" do
        error = described_class.new
        expect(error.send(:default_message)).to eq("An error occurred in PgSqlTriggers")
      end
    end

    describe "#default_recovery_suggestion" do
      it "returns default recovery suggestion" do
        error = described_class.new
        expect(error.send(:default_recovery_suggestion)).to eq(
          "Please check the logs for more details and contact support if the issue persists."
        )
      end
    end
  end
end

RSpec.describe PgSqlTriggers::PermissionError do
  describe "#initialize" do
    it "uses default error code" do
      error = described_class.new
      expect(error.error_code).to eq("PERMISSION_DENIED")
    end

    it "uses default message" do
      error = described_class.new
      expect(error.message).to eq("Permission denied for this operation")
    end

    it "allows custom message" do
      error = described_class.new("Custom permission error")
      expect(error.message).to eq("Custom permission error")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes required_role when present in context" do
      error = described_class.new(nil, context: { required_role: "Admin" })
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("Admin")
      expect(suggestion).to include("Contact your administrator")
    end

    it "uses generic message when required_role is not present" do
      error = described_class.new(nil, context: {})
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to eq("This operation requires elevated permissions. Contact your administrator.")
      expect(suggestion).not_to match(/requires \w+ level access/)
    end

    it "handles nil context" do
      error = described_class.new(nil, context: nil)
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to eq("This operation requires elevated permissions. Contact your administrator.")
    end
  end

  describe "#default_error_code" do
    it "returns PERMISSION_DENIED" do
      error = described_class.new
      expect(error.send(:default_error_code)).to eq("PERMISSION_DENIED")
    end
  end

  describe "#default_message" do
    it "returns default permission error message" do
      error = described_class.new
      expect(error.send(:default_message)).to eq("Permission denied for this operation")
    end
  end
end

RSpec.describe PgSqlTriggers::KillSwitchError do
  describe "#initialize" do
    it "uses default error code" do
      error = described_class.new
      expect(error.error_code).to eq("KILL_SWITCH_ACTIVE")
    end

    it "uses default message" do
      error = described_class.new
      expect(error.message).to eq("Kill switch is active for this environment")
    end

    it "allows custom message" do
      error = described_class.new("Custom kill switch error")
      expect(error.message).to eq("Custom kill switch error")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes environment when present in context" do
      error = described_class.new(nil, context: { environment: "production", operation: "test_op" })
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("production")
      expect(suggestion).to include("KILL_SWITCH_OVERRIDE=true")
    end

    it "uses default environment text when not present" do
      error = described_class.new(nil, context: { operation: "test_op" })
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("this environment")
    end

    it "handles nil context" do
      error = described_class.new(nil, context: nil)
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("this environment")
    end

    it "includes KILL_SWITCH_OVERRIDE instruction" do
      error = described_class.new(nil, context: { operation: "test_operation" })
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("KILL_SWITCH_OVERRIDE=true")
      expect(suggestion).to include("CONFIRMATION_TEXT")
    end

    it "includes override instructions even when operation is not present" do
      error = described_class.new(nil, context: {})
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("KILL_SWITCH_OVERRIDE=true")
      expect(suggestion).to include("this environment")
    end
  end

  describe "#default_error_code" do
    it "returns KILL_SWITCH_ACTIVE" do
      error = described_class.new
      expect(error.send(:default_error_code)).to eq("KILL_SWITCH_ACTIVE")
    end
  end

  describe "#default_message" do
    it "returns default kill switch error message" do
      error = described_class.new
      expect(error.send(:default_message)).to eq("Kill switch is active for this environment")
    end
  end
end

RSpec.describe PgSqlTriggers::DriftError do
  describe "#initialize" do
    it "uses default error code" do
      error = described_class.new
      expect(error.error_code).to eq("DRIFT_DETECTED")
    end

    it "uses default message" do
      error = described_class.new
      expect(error.message).to eq("Trigger has drifted from its definition")
    end

    it "allows custom message" do
      error = described_class.new("Custom drift error")
      expect(error.message).to eq("Custom drift error")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes trigger_name when present in context" do
      error = described_class.new(nil, context: { trigger_name: "users_email_validation" })
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("users_email_validation")
      expect(suggestion).to include("rake trigger:migrate")
    end

    it "uses default trigger name when not present" do
      error = described_class.new(nil, context: {})
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("Trigger 'trigger' has drifted")
      expect(suggestion).to include("rake trigger:migrate")
    end

    it "handles nil context" do
      error = described_class.new(nil, context: nil)
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("Trigger 'trigger' has drifted")
    end
  end

  describe "#default_error_code" do
    it "returns DRIFT_DETECTED" do
      error = described_class.new
      expect(error.send(:default_error_code)).to eq("DRIFT_DETECTED")
    end
  end

  describe "#default_message" do
    it "returns default drift error message" do
      error = described_class.new
      expect(error.send(:default_message)).to eq("Trigger has drifted from its definition")
    end
  end
end

RSpec.describe PgSqlTriggers::ValidationError do
  describe "#initialize" do
    it "uses default error code" do
      error = described_class.new
      expect(error.error_code).to eq("VALIDATION_FAILED")
    end

    it "uses default message" do
      error = described_class.new
      expect(error.message).to eq("Validation failed")
    end

    it "allows custom message" do
      error = described_class.new("Custom validation error")
      expect(error.message).to eq("Custom validation error")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes field name when present in context" do
      error = described_class.new(nil, context: { field: :table_name })
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("table_name")
      expect(suggestion).to include("fix")
    end

    it "uses generic message when field is not present" do
      error = described_class.new(nil, context: {})
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to eq("Please review the input and ensure all required fields are provided.")
      expect(suggestion).not_to match(/fix the \w+ field/)
    end

    it "handles nil context" do
      error = described_class.new(nil, context: nil)
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to eq("Please review the input and ensure all required fields are provided.")
    end
  end

  describe "#default_error_code" do
    it "returns VALIDATION_FAILED" do
      error = described_class.new
      expect(error.send(:default_error_code)).to eq("VALIDATION_FAILED")
    end
  end

  describe "#default_message" do
    it "returns default validation error message" do
      error = described_class.new
      expect(error.send(:default_message)).to eq("Validation failed")
    end
  end
end

RSpec.describe PgSqlTriggers::ExecutionError do
  describe "#initialize" do
    it "uses default error code" do
      error = described_class.new
      expect(error.error_code).to eq("EXECUTION_FAILED")
    end

    it "uses default message" do
      error = described_class.new
      expect(error.message).to eq("SQL execution failed")
    end

    it "allows custom message" do
      error = described_class.new("Custom execution error")
      expect(error.message).to eq("Custom execution error")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes database_error when present in context" do
      error = described_class.new(nil, context: { database_error: "syntax error" })
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("database error")
      expect(suggestion).to include("table and column names")
    end

    it "uses generic message when database_error is not present" do
      error = described_class.new(nil, context: {})
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to eq("Review the SQL and ensure it is valid PostgreSQL syntax.")
      expect(suggestion).not_to include("database error")
    end

    it "handles nil context" do
      error = described_class.new(nil, context: nil)
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to eq("Review the SQL and ensure it is valid PostgreSQL syntax.")
    end
  end

  describe "#default_error_code" do
    it "returns EXECUTION_FAILED" do
      error = described_class.new
      expect(error.send(:default_error_code)).to eq("EXECUTION_FAILED")
    end
  end

  describe "#default_message" do
    it "returns default execution error message" do
      error = described_class.new
      expect(error.send(:default_message)).to eq("SQL execution failed")
    end
  end
end

RSpec.describe PgSqlTriggers::UnsafeMigrationError do
  describe "#initialize" do
    it "uses default error code" do
      error = described_class.new
      expect(error.error_code).to eq("UNSAFE_MIGRATION")
    end

    it "uses default message" do
      error = described_class.new
      expect(error.message).to eq("Migration contains unsafe operations")
    end

    it "allows custom message" do
      error = described_class.new("Custom unsafe migration error")
      expect(error.message).to eq("Custom unsafe migration error")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes configuration instructions" do
      error = described_class.new
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("allow_unsafe_migrations")
      expect(suggestion).to include("kill switch override")
    end
  end

  describe "#default_error_code" do
    it "returns UNSAFE_MIGRATION" do
      error = described_class.new
      expect(error.send(:default_error_code)).to eq("UNSAFE_MIGRATION")
    end
  end

  describe "#default_message" do
    it "returns default unsafe migration error message" do
      error = described_class.new
      expect(error.send(:default_message)).to eq("Migration contains unsafe operations")
    end
  end
end

RSpec.describe PgSqlTriggers::NotFoundError do
  describe "#initialize" do
    it "uses default error code" do
      error = described_class.new
      expect(error.error_code).to eq("NOT_FOUND")
    end

    it "uses default message" do
      error = described_class.new
      expect(error.message).to eq("Resource not found")
    end

    it "allows custom message" do
      error = described_class.new("Custom not found error")
      expect(error.message).to eq("Custom not found error")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes trigger_name when present in context" do
      error = described_class.new(nil, context: { trigger_name: "users_email_validation" })
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to include("users_email_validation")
      expect(suggestion).to include("create the trigger")
    end

    it "uses generic message when trigger_name is not present" do
      error = described_class.new(nil, context: {})
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to eq("The requested resource was not found. Verify the identifier and try again.")
      expect(suggestion).not_to include("Trigger")
    end

    it "handles nil context" do
      error = described_class.new(nil, context: nil)
      suggestion = error.send(:default_recovery_suggestion)
      expect(suggestion).to eq("The requested resource was not found. Verify the identifier and try again.")
    end
  end

  describe "#default_error_code" do
    it "returns NOT_FOUND" do
      error = described_class.new
      expect(error.send(:default_error_code)).to eq("NOT_FOUND")
    end
  end

  describe "#default_message" do
    it "returns default not found error message" do
      error = described_class.new
      expect(error.send(:default_message)).to eq("Resource not found")
    end
  end
end
