# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers do
  it "has a version number" do
    expect(PgSqlTriggers::VERSION).not_to be_nil
    expect(PgSqlTriggers::VERSION).to be_a(String)
  end

  describe ".configure" do
    it "yields self for configuration" do
      described_class.configure do |config|
        expect(config).to eq(described_class)
      end
    end

    it "allows setting kill_switch_enabled" do
      original = described_class.kill_switch_enabled
      described_class.configure do |config|
        config.kill_switch_enabled = false
      end
      expect(described_class.kill_switch_enabled).to be(false)
      described_class.kill_switch_enabled = original
    end

    it "allows setting default_environment" do
      original = described_class.default_environment
      described_class.configure do |config|
        config.default_environment = -> { "test" }
      end
      expect(described_class.default_environment.call).to eq("test")
      described_class.default_environment = original
    end
  end

  describe "error classes" do
    it "defines Error base class" do
      expect(PgSqlTriggers::Error).to be < StandardError
    end

    it "defines PermissionError" do
      expect(PgSqlTriggers::PermissionError).to be < PgSqlTriggers::Error
    end

    it "defines DriftError" do
      expect(PgSqlTriggers::DriftError).to be < PgSqlTriggers::Error
    end

    it "defines KillSwitchError" do
      expect(PgSqlTriggers::KillSwitchError).to be < PgSqlTriggers::Error
    end

    it "defines ValidationError" do
      expect(PgSqlTriggers::ValidationError).to be < PgSqlTriggers::Error
    end

    it "defines ExecutionError" do
      expect(PgSqlTriggers::ExecutionError).to be < PgSqlTriggers::Error
    end

    it "defines UnsafeMigrationError" do
      expect(PgSqlTriggers::UnsafeMigrationError).to be < PgSqlTriggers::Error
    end

    it "defines NotFoundError" do
      expect(PgSqlTriggers::NotFoundError).to be < PgSqlTriggers::Error
    end
  end
end

RSpec.describe PgSqlTriggers::Error do
  describe "#initialize" do
    it "accepts message" do
      error = described_class.new("Test error")
      expect(error.message).to eq("Test error")
    end

    it "accepts error_code" do
      error = described_class.new("Test", error_code: "TEST_ERROR")
      expect(error.error_code).to eq("TEST_ERROR")
    end

    it "accepts recovery_suggestion" do
      error = described_class.new("Test", recovery_suggestion: "Try again")
      expect(error.recovery_suggestion).to eq("Try again")
    end

    it "accepts context" do
      error = described_class.new("Test", context: { key: "value" })
      expect(error.context).to eq({ key: "value" })
    end

    it "uses default error code when not provided" do
      error = described_class.new("Test")
      expect(error.error_code).to eq("ERROR")
    end

    it "uses default message when not provided" do
      error = described_class.new
      expect(error.message).to eq("An error occurred in PgSqlTriggers")
    end

    it "uses default recovery suggestion when not provided" do
      error = described_class.new("Test")
      expect(error.recovery_suggestion).to include("check the logs")
    end

    it "handles nil context" do
      error = described_class.new("Test", context: nil)
      expect(error.context).to eq({})
    end
  end

  describe "#user_message" do
    it "returns message when no recovery suggestion" do
      error = described_class.new("Test error")
      expect(error.user_message).to eq("Test error")
    end

    it "includes recovery suggestion when present" do
      error = described_class.new("Test error", recovery_suggestion: "Try again")
      expect(error.user_message).to include("Test error")
      expect(error.user_message).to include("Recovery: Try again")
    end
  end

  describe "#to_h" do
    it "returns error details as hash" do
      error = described_class.new("Test error", error_code: "TEST", recovery_suggestion: "Fix it", context: { key: "value" })
      hash = error.to_h
      expect(hash).to include(
        error_class: "PgSqlTriggers::Error",
        error_code: "TEST",
        message: "Test error",
        recovery_suggestion: "Fix it",
        context: { key: "value" }
      )
    end
  end

  describe "#default_error_code" do
    it "converts class name to error code" do
      error = described_class.new
      expect(error.send(:default_error_code)).to eq("ERROR")
    end
  end
end

RSpec.describe PgSqlTriggers::PermissionError do
  describe "#default_error_code" do
    it "returns PERMISSION_DENIED" do
      error = described_class.new
      expect(error.error_code).to eq("PERMISSION_DENIED")
    end
  end

  describe "#default_message" do
    it "returns permission denied message" do
      error = described_class.new
      expect(error.message).to include("Permission denied")
    end
  end

  describe "#default_recovery_suggestion" do
    context "when required_role is in context" do
      it "includes role in suggestion" do
        error = described_class.new("Denied", context: { required_role: "Admin" })
        expect(error.recovery_suggestion).to include("Admin")
        expect(error.recovery_suggestion).to include("administrator")
      end
    end

    context "when required_role is not in context" do
      it "provides generic suggestion" do
        error = described_class.new("Denied")
        expect(error.recovery_suggestion).to include("elevated permissions")
        expect(error.recovery_suggestion).to include("administrator")
      end
    end
  end
end

RSpec.describe PgSqlTriggers::KillSwitchError do
  describe "#default_error_code" do
    it "returns KILL_SWITCH_ACTIVE" do
      error = described_class.new
      expect(error.error_code).to eq("KILL_SWITCH_ACTIVE")
    end
  end

  describe "#default_message" do
    it "returns kill switch active message" do
      error = described_class.new
      expect(error.message).to include("kill switch is active")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes environment in suggestion" do
      error = described_class.new("Active", context: { environment: "production" })
      expect(error.recovery_suggestion).to include("production")
      expect(error.recovery_suggestion).to include("confirmation text")
    end

    it "includes operation in suggestion" do
      error = described_class.new("Active", context: { operation: :trigger_enable })
      expect(error.recovery_suggestion).to include("confirmation text")
    end

    it "handles missing context gracefully" do
      error = described_class.new("Active")
      expect(error.recovery_suggestion).to include("Kill switch is active")
    end
  end
end

RSpec.describe PgSqlTriggers::DriftError do
  describe "#default_error_code" do
    it "returns DRIFT_DETECTED" do
      error = described_class.new
      expect(error.error_code).to eq("DRIFT_DETECTED")
    end
  end

  describe "#default_message" do
    it "returns drift detected message" do
      error = described_class.new
      expect(error.message).to include("drifted")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes trigger name when present" do
      error = described_class.new("Drift", context: { trigger_name: "test_trigger" })
      expect(error.recovery_suggestion).to include("test_trigger")
      expect(error.recovery_suggestion).to include("re-execute")
    end

    it "uses generic trigger name when not present" do
      error = described_class.new("Drift")
      expect(error.recovery_suggestion).to include("trigger")
    end
  end
end

RSpec.describe PgSqlTriggers::ValidationError do
  describe "#default_error_code" do
    it "returns VALIDATION_FAILED" do
      error = described_class.new
      expect(error.error_code).to eq("VALIDATION_FAILED")
    end
  end

  describe "#default_message" do
    it "returns validation failed message" do
      error = described_class.new
      expect(error.message).to eq("Validation failed")
    end
  end

  describe "#default_recovery_suggestion" do
    context "when field is in context" do
      it "includes field name in suggestion" do
        error = described_class.new("Failed", context: { field: :table_name })
        expect(error.recovery_suggestion).to include("table_name")
      end
    end

    context "when field is not in context" do
      it "provides generic suggestion" do
        error = described_class.new("Failed")
        expect(error.recovery_suggestion).to include("required fields")
      end
    end
  end
end

RSpec.describe PgSqlTriggers::ExecutionError do
  describe "#default_error_code" do
    it "returns EXECUTION_FAILED" do
      error = described_class.new
      expect(error.error_code).to eq("EXECUTION_FAILED")
    end
  end

  describe "#default_message" do
    it "returns execution failed message" do
      error = described_class.new
      expect(error.message).to eq("SQL execution failed")
    end
  end

  describe "#default_recovery_suggestion" do
    context "when database_error is in context" do
      it "includes database error guidance" do
        error = described_class.new("Failed", context: { database_error: "syntax error" })
        expect(error.recovery_suggestion).to include("database error")
        expect(error.recovery_suggestion).to include("table and column names")
      end
    end

    context "when database_error is not in context" do
      it "provides generic suggestion" do
        error = described_class.new("Failed")
        expect(error.recovery_suggestion).to include("PostgreSQL syntax")
      end
    end
  end
end

RSpec.describe PgSqlTriggers::UnsafeMigrationError do
  describe "#default_error_code" do
    it "returns UNSAFE_MIGRATION" do
      error = described_class.new
      expect(error.error_code).to eq("UNSAFE_MIGRATION")
    end
  end

  describe "#default_message" do
    it "returns unsafe migration message" do
      error = described_class.new
      expect(error.message).to include("unsafe operations")
    end
  end

  describe "#default_recovery_suggestion" do
    it "includes allow_unsafe_migrations guidance" do
      error = described_class.new("Unsafe")
      expect(error.recovery_suggestion).to include("allow_unsafe_migrations")
      expect(error.recovery_suggestion).to include("kill switch override")
    end
  end
end

RSpec.describe PgSqlTriggers::NotFoundError do
  describe "#default_error_code" do
    it "returns NOT_FOUND" do
      error = described_class.new
      expect(error.error_code).to eq("NOT_FOUND")
    end
  end

  describe "#default_message" do
    it "returns not found message" do
      error = described_class.new
      expect(error.message).to eq("Resource not found")
    end
  end

  describe "#default_recovery_suggestion" do
    context "when trigger_name is in context" do
      it "includes trigger name in suggestion" do
        error = described_class.new("Not found", context: { trigger_name: "test_trigger" })
        expect(error.recovery_suggestion).to include("test_trigger")
        expect(error.recovery_suggestion).to include("generator or DSL")
      end
    end

    context "when trigger_name is not in context" do
      it "provides generic suggestion" do
        error = described_class.new("Not found")
        expect(error.recovery_suggestion).to include("identifier")
      end
    end
  end
end
