# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::AuditLog do
  describe "validations" do
    it "requires operation" do
      log = described_class.new(status: "success")
      expect(log).not_to be_valid
      expect(log.errors[:operation]).to be_present
    end

    it "requires status" do
      log = described_class.new(operation: "enable")
      expect(log).not_to be_valid
      expect(log.errors[:status]).to be_present
    end

    it "requires status to be success or failure" do
      log = described_class.new(operation: "enable", status: "invalid")
      expect(log).not_to be_valid
      expect(log.errors[:status]).to be_present
    end

    it "validates with success status" do
      log = described_class.new(operation: "enable", status: "success")
      expect(log).to be_valid
    end

    it "validates with failure status" do
      log = described_class.new(operation: "enable", status: "failure")
      expect(log).to be_valid
    end
  end

  describe "scopes" do
    let!(:successful_enable_log) do
      described_class.create!(
        trigger_name: "trigger_1",
        operation: "enable",
        status: "success",
        environment: "test"
      )
    end

    let!(:failed_disable_log) do
      described_class.create!(
        trigger_name: "trigger_2",
        operation: "disable",
        status: "failure",
        environment: "production"
      )
    end

    let!(:successful_drop_log) do
      described_class.create!(
        trigger_name: "trigger_1",
        operation: "drop",
        status: "success",
        environment: "test"
      )
    end

    describe ".for_trigger" do
      it "filters by trigger name" do
        logs = described_class.for_trigger("trigger_1")
        expect(logs.count).to eq(2)
        expect(logs).to include(successful_enable_log, successful_drop_log)
        expect(logs).not_to include(failed_disable_log)
      end
    end

    describe ".for_operation" do
      it "filters by operation" do
        logs = described_class.for_operation("enable")
        expect(logs.count).to eq(1)
        expect(logs).to include(successful_enable_log)
      end
    end

    describe ".for_environment" do
      it "filters by environment" do
        logs = described_class.for_environment("test")
        expect(logs.count).to eq(2)
        expect(logs).to include(successful_enable_log, successful_drop_log)
      end
    end

    describe ".successful" do
      it "returns only successful operations" do
        logs = described_class.successful
        expect(logs.count).to eq(2)
        expect(logs).to include(successful_enable_log, successful_drop_log)
        expect(logs).not_to include(failed_disable_log)
      end
    end

    describe ".failed" do
      it "returns only failed operations" do
        logs = described_class.failed
        expect(logs.count).to eq(1)
        expect(logs).to include(failed_disable_log)
      end
    end

    describe ".recent" do
      it "orders by created_at descending" do
        logs = described_class.recent
        expect(logs.first).to eq(successful_drop_log)
        expect(logs.last).to eq(successful_enable_log)
      end
    end
  end

  describe ".log_success" do
    let(:actor) { { type: "User", id: "123" } }

    it "creates a successful audit log entry" do
      log = described_class.log_success(
        operation: :enable,
        trigger_name: "test_trigger",
        actor: actor,
        environment: "test",
        reason: "Testing"
      )

      expect(log).to be_persisted
      expect(log.operation).to eq("enable")
      expect(log.status).to eq("success")
      expect(log.trigger_name).to eq("test_trigger")
      expect(log.environment).to eq("test")
      expect(log.reason).to eq("Testing")
      expect(log.actor).to eq({ "type" => "User", "id" => "123" })
    end

    it "handles optional parameters" do
      log = described_class.log_success(
        operation: :disable,
        actor: actor
      )

      expect(log).to be_persisted
      expect(log.operation).to eq("disable")
      expect(log.status).to eq("success")
      expect(log.trigger_name).to be_nil
      expect(log.environment).to be_nil
    end

    it "serializes actor hash" do
      log = described_class.log_success(
        operation: :enable,
        actor: { type: "Admin", id: "456" }
      )

      expect(log.actor).to eq({ "type" => "Admin", "id" => "456" })
    end

    it "serializes non-hash actor" do
      actor_obj = double("Actor", class: double(name: "User"), id: 789)
      log = described_class.log_success(
        operation: :enable,
        actor: actor_obj
      )

      expect(log.actor).to eq({ "type" => "User", "id" => "789" })
    end

    it "handles nil actor" do
      log = described_class.log_success(operation: :enable, actor: nil)
      expect(log.actor).to be_nil
    end

    it "stores before_state and after_state" do
      log = described_class.log_success(
        operation: :enable,
        actor: actor,
        before_state: { enabled: false },
        after_state: { enabled: true }
      )

      expect(log.before_state).to eq({ "enabled" => false })
      expect(log.after_state).to eq({ "enabled" => true })
    end

    it "stores diff" do
      log = described_class.log_success(
        operation: :re_execute,
        actor: actor,
        diff: "--- old\n+++ new\n"
      )

      expect(log.diff).to eq("--- old\n+++ new\n")
    end

    it "stores confirmation_text" do
      log = described_class.log_success(
        operation: :enable,
        actor: actor,
        confirmation_text: "EXECUTE TRIGGER_ENABLE"
      )

      expect(log.confirmation_text).to eq("EXECUTE TRIGGER_ENABLE")
    end

    it "handles errors gracefully" do
      allow(described_class).to receive(:create!).and_raise(StandardError.new("DB error"))
      allow(Rails.logger).to receive(:error)

      result = described_class.log_success(operation: :enable, actor: actor)
      expect(result).to be_nil
      expect(Rails.logger).to have_received(:error).with(/Failed to log audit entry/)
    end
  end

  describe ".log_failure" do
    let(:actor) { { type: "User", id: "123" } }

    it "creates a failed audit log entry" do
      log = described_class.log_failure(
        operation: :enable,
        trigger_name: "test_trigger",
        actor: actor,
        environment: "test",
        error_message: "Permission denied"
      )

      expect(log).to be_persisted
      expect(log.operation).to eq("enable")
      expect(log.status).to eq("failure")
      expect(log.error_message).to eq("Permission denied")
      expect(log.trigger_name).to eq("test_trigger")
    end

    it "handles optional parameters" do
      log = described_class.log_failure(
        operation: :disable,
        actor: actor,
        error_message: "Database error"
      )

      expect(log).to be_persisted
      expect(log.operation).to eq("disable")
      expect(log.status).to eq("failure")
      expect(log.error_message).to eq("Database error")
    end

    it "stores reason if provided before failure" do
      log = described_class.log_failure(
        operation: :drop,
        actor: actor,
        error_message: "Failed",
        reason: "No longer needed"
      )

      expect(log.reason).to eq("No longer needed")
    end

    it "stores before_state" do
      log = described_class.log_failure(
        operation: :enable,
        actor: actor,
        error_message: "Failed",
        before_state: { enabled: false }
      )

      expect(log.before_state).to eq({ "enabled" => false })
    end

    it "handles errors gracefully" do
      allow(described_class).to receive(:create!).and_raise(StandardError.new("DB error"))
      allow(Rails.logger).to receive(:error)

      result = described_class.log_failure(
        operation: :enable,
        actor: actor,
        error_message: "Test error"
      )
      expect(result).to be_nil
      expect(Rails.logger).to have_received(:error).with(/Failed to log audit entry/)
    end
  end

  describe ".for_trigger_name" do
    let!(:enable_log) do
      described_class.create!(
        trigger_name: "trigger_1",
        operation: "enable",
        status: "success"
      )
    end

    let!(:other_trigger_log) do
      described_class.create!(
        trigger_name: "trigger_2",
        operation: "disable",
        status: "success"
      )
    end

    let!(:drop_log) do
      described_class.create!(
        trigger_name: "trigger_1",
        operation: "drop",
        status: "success"
      )
    end

    it "returns logs for specific trigger ordered by recent" do
      logs = described_class.for_trigger_name("trigger_1")
      expect(logs.count).to eq(2)
      expect(logs.first).to eq(drop_log) # Most recent first
      expect(logs.last).to eq(enable_log)
    end
  end
end
