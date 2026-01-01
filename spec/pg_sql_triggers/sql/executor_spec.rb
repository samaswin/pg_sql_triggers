# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::SQL::Executor do
  let(:capsule) do
    PgSqlTriggers::SQL::Capsule.new(
      name: "test_capsule",
      environment: "production",
      purpose: "Test SQL execution",
      sql: "SELECT 1 AS result;"
    )
  end

  let(:actor) { { type: "User", id: 1 } }

  before do
    # Stub permissions by default
    allow(PgSqlTriggers::Permissions).to receive(:check!).and_return(true)
    # Stub kill switch by default
    allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
    # Stub logger
    allow(Rails).to receive(:logger).and_return(double("Logger", info: nil, error: nil))
  end

  describe ".execute" do
    context "with valid capsule and permissions" do
      it "executes SQL successfully" do
        result = described_class.execute(capsule, actor: actor)

        expect(result[:success]).to be true
        expect(result[:message]).to match(/executed successfully/)
        expect(result[:data][:checksum]).to eq(capsule.checksum)
      end

      it "returns rows affected count" do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_return(
          double("Result", cmd_tuples: 5)
        )

        result = described_class.execute(capsule, actor: actor)

        expect(result[:data][:rows_affected]).to eq(5)
      end

      it "executes within a transaction" do
        expect(ActiveRecord::Base).to receive(:transaction).and_call_original

        described_class.execute(capsule, actor: actor)
      end

      it "updates registry after successful execution" do
        result = described_class.execute(capsule, actor: actor)

        expect(result[:success]).to be true

        registry_entry = PgSqlTriggers::TriggerRegistry.find_by(
          trigger_name: "sql_capsule_test_capsule"
        )

        expect(registry_entry).to be_present
        expect(registry_entry.source).to eq("manual_sql")
        expect(registry_entry.checksum).to eq(capsule.checksum)
        expect(registry_entry.function_body).to eq(capsule.sql)
        expect(registry_entry.enabled).to be true
        expect(registry_entry.last_executed_at).to be_present
      end

      it "includes capsule checksum in result" do
        result = described_class.execute(capsule, actor: actor)

        expect(result[:data][:checksum]).to eq(capsule.checksum)
      end
    end

    context "with dry_run mode" do
      before do
        # Clean up any existing registry entries for this capsule
        PgSqlTriggers::TriggerRegistry.where(trigger_name: "sql_capsule_test_capsule").destroy_all
      end

      it "validates without executing SQL" do
        expect(ActiveRecord::Base.connection).not_to receive(:execute)

        result = described_class.execute(capsule, actor: actor, dry_run: true)

        expect(result[:success]).to be true
        expect(result[:message]).to match(/Dry run successful/)
      end

      it "does not update registry" do
        described_class.execute(capsule, actor: actor, dry_run: true)

        registry_entry = PgSqlTriggers::TriggerRegistry.find_by(
          trigger_name: "sql_capsule_test_capsule"
        )

        expect(registry_entry).to be_nil
      end

      it "returns checksum in dry run result" do
        result = described_class.execute(capsule, actor: actor, dry_run: true)

        expect(result[:data][:checksum]).to eq(capsule.checksum)
      end
    end

    context "with validation checks" do
      it "validates capsule is a Capsule instance" do
        # Suppress logger errors for this invalid input
        allow(Rails.logger).to receive(:error)

        result = described_class.execute("not a capsule", actor: actor)
        expect(result[:success]).to be false
        expect(result[:message]).to match(/Execution failed/)
      end

      it "checks permissions before execution" do
        expect(PgSqlTriggers::Permissions).to receive(:check!).with(actor, :execute_sql)

        described_class.execute(capsule, actor: actor)
      end

      it "checks kill switch before execution" do
        expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
          operation: :execute_sql_capsule,
          environment: Rails.env,
          confirmation: nil,
          actor: actor
        )

        described_class.execute(capsule, actor: actor)
      end

      it "passes confirmation to kill switch" do
        expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
          operation: :execute_sql_capsule,
          environment: Rails.env,
          confirmation: "EXECUTE SQL",
          actor: actor
        )

        described_class.execute(capsule, actor: actor, confirmation: "EXECUTE SQL")
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:check!)
          .and_raise(PgSqlTriggers::PermissionError.new("Permission denied"))
      end

      it "returns failure result with permission error" do
        result = described_class.execute(capsule, actor: actor)
        expect(result[:success]).to be false
        expect(result[:message]).to match(/Execution failed/)
      end

      it "does not execute SQL" do
        expect(ActiveRecord::Base.connection).not_to receive(:execute)
        described_class.execute(capsule, actor: actor)
      end
    end

    context "when kill switch blocks execution" do
      before do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!)
          .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch active"))
      end

      it "returns failure result" do
        result = described_class.execute(capsule, actor: actor)

        expect(result[:success]).to be false
        expect(result[:message]).to match(/Execution failed/)
      end

      it "does not execute SQL" do
        expect(ActiveRecord::Base.connection).not_to receive(:execute)

        described_class.execute(capsule, actor: actor)
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/ERROR/)

        described_class.execute(capsule, actor: actor)
      end
    end

    context "when SQL execution fails" do
      before do
        # Clean up any existing registry entries for this capsule
        PgSqlTriggers::TriggerRegistry.where(trigger_name: "sql_capsule_test_capsule").destroy_all
        allow(ActiveRecord::Base.connection).to receive(:execute)
          .and_raise(ActiveRecord::StatementInvalid.new("SQL syntax error"))
      end

      it "returns failure result" do
        result = described_class.execute(capsule, actor: actor)

        expect(result[:success]).to be false
        expect(result[:message]).to match(/Execution failed/)
        expect(result[:message]).to include("SQL syntax error")
      end

      it "rolls back transaction" do
        expect do
          described_class.execute(capsule, actor: actor)
        end.not_to change(PgSqlTriggers::TriggerRegistry, :count)
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/ERROR/)

        described_class.execute(capsule, actor: actor)
      end

      it "includes error in result" do
        result = described_class.execute(capsule, actor: actor)

        expect(result[:error]).to be_present
        expect(result[:error]).to be_a(ActiveRecord::StatementInvalid)
      end
    end

    context "when registry update fails" do
      before do
        allow(PgSqlTriggers::TriggerRegistry).to receive(:find_or_initialize_by)
          .and_raise(StandardError.new("Registry error"))
      end

      it "still returns success for SQL execution" do
        result = described_class.execute(capsule, actor: actor)

        # SQL executed but registry update failed
        # The implementation catches registry errors and doesn't fail the execution
        expect(result[:success]).to be true
      end

      it "logs registry update failure" do
        expect(Rails.logger).to receive(:error).with(/Failed to update registry/)

        described_class.execute(capsule, actor: actor)
      end
    end

    context "with logging" do
      it "logs execution attempt" do
        expect(Rails.logger).to receive(:info).with(/EXECUTE ATTEMPT/)

        described_class.execute(capsule, actor: actor)
      end

      it "logs dry run attempt" do
        expect(Rails.logger).to receive(:info).with(/DRY_RUN ATTEMPT/)

        described_class.execute(capsule, actor: actor, dry_run: true)
      end

      it "logs successful execution" do
        expect(Rails.logger).to receive(:info).with(/SUCCESS/)

        described_class.execute(capsule, actor: actor)
      end

      it "includes actor information in logs" do
        expect(Rails.logger).to receive(:info).with(/actor=User:1/)

        described_class.execute(capsule, actor: actor)
      end

      it "handles nil actor in logs" do
        expect(Rails.logger).to receive(:error).with(/actor=unknown/)

        # Permission check will fail with nil actor, so stub it
        allow(PgSqlTriggers::Permissions).to receive(:check!)
          .and_raise(StandardError.new("error"))

        described_class.execute(capsule, actor: nil)
      end

      it "handles non-hash actor in logs" do
        expect(Rails.logger).to receive(:error).with(/actor=some_string/)

        # Permission check will fail with string actor, so stub it
        allow(PgSqlTriggers::Permissions).to receive(:check!)
          .and_raise(StandardError.new("error"))

        described_class.execute(capsule, actor: "some_string")
      end
    end
  end

  describe ".execute_capsule" do
    before do
      # Create a capsule in the registry
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "sql_capsule_existing",
        table_name: "manual_sql_execution",
        version: Time.current.to_i,
        checksum: "abc123",
        source: "manual_sql",
        function_body: "SELECT 42;",
        condition: "Test capsule purpose",
        environment: "production",
        enabled: true
      )
    end

    context "when capsule exists in registry" do
      it "loads and executes capsule by name" do
        result = described_class.execute_capsule("existing", actor: actor)

        expect(result[:success]).to be true
        expect(result[:message]).to match(/executed successfully/)
      end

      it "loads capsule attributes from registry" do
        result = described_class.execute_capsule("existing", actor: actor, dry_run: true)

        # Verify the capsule was loaded with correct attributes
        expect(result[:success]).to be true
      end

      it "passes confirmation to execute" do
        expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
          hash_including(confirmation: "CONFIRM EXECUTE")
        )

        described_class.execute_capsule("existing", actor: actor, confirmation: "CONFIRM EXECUTE")
      end
    end

    context "when capsule does not exist" do
      it "returns failure result" do
        result = described_class.execute_capsule("nonexistent", actor: actor)

        expect(result[:success]).to be false
        expect(result[:message]).to match(/not found in registry/)
      end

      it "does not attempt execution" do
        expect(ActiveRecord::Base.connection).not_to receive(:execute)

        described_class.execute_capsule("nonexistent", actor: actor)
      end
    end

    context "with dry_run mode" do
      it "validates without executing" do
        expect(ActiveRecord::Base.connection).not_to receive(:execute)

        result = described_class.execute_capsule("existing", actor: actor, dry_run: true)

        expect(result[:success]).to be true
        expect(result[:message]).to match(/Dry run successful/)
      end
    end
  end

  describe "logger fallback" do
    context "when PgSqlTriggers.logger is available" do
      it "uses PgSqlTriggers.logger" do
        pg_logger = double("PgLogger", info: nil, error: nil)
        allow(PgSqlTriggers).to receive(:respond_to?).with(:logger).and_return(true)
        allow(PgSqlTriggers).to receive(:logger).and_return(pg_logger)

        expect(pg_logger).to receive(:info).at_least(:once)

        described_class.execute(capsule, actor: actor)
      end
    end

    context "when only Rails.logger is available" do
      it "falls back to Rails.logger" do
        allow(PgSqlTriggers).to receive(:respond_to?).with(:logger).and_return(false)

        expect(Rails.logger).to receive(:info).at_least(:once)

        described_class.execute(capsule, actor: actor)
      end
    end

    context "when no logger is available" do
      it "does not raise error" do
        allow(PgSqlTriggers).to receive(:respond_to?).with(:logger).and_return(false)
        allow(Rails).to receive(:respond_to?).with(:logger).and_return(false)

        expect do
          described_class.execute(capsule, actor: actor)
        end.not_to raise_error
      end
    end
  end

  describe "registry storage" do
    it "stores capsule with manual_sql source" do
      described_class.execute(capsule, actor: actor)

      entry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "sql_capsule_test_capsule")
      expect(entry).to be_present
      expect(entry.source).to eq("manual_sql")
    end

    it "stores capsule with manual_sql_execution table_name" do
      described_class.execute(capsule, actor: actor)

      entry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "sql_capsule_test_capsule")
      expect(entry).to be_present
      expect(entry.table_name).to eq("manual_sql_execution")
    end

    it "stores capsule SQL in function_body" do
      described_class.execute(capsule, actor: actor)

      entry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "sql_capsule_test_capsule")
      expect(entry).to be_present
      expect(entry.function_body).to eq(capsule.sql)
    end

    it "stores capsule purpose in condition" do
      described_class.execute(capsule, actor: actor)

      entry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "sql_capsule_test_capsule")
      expect(entry).to be_present
      expect(entry.condition).to eq(capsule.purpose)
    end

    it "stores capsule environment" do
      described_class.execute(capsule, actor: actor)

      entry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "sql_capsule_test_capsule")
      expect(entry).to be_present
      expect(entry.environment).to eq("production")
    end

    it "marks capsule as enabled" do
      described_class.execute(capsule, actor: actor)

      entry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "sql_capsule_test_capsule")
      expect(entry).to be_present
      expect(entry.enabled).to be true
    end

    it "sets last_executed_at timestamp" do
      freeze_time do
        described_class.execute(capsule, actor: actor)

        entry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "sql_capsule_test_capsule")
        expect(entry).to be_present
        expect(entry.last_executed_at).to be_within(1.second).of(Time.current)
      end
    end

    it "updates existing registry entry on re-execution" do
      # First execution
      described_class.execute(capsule, actor: actor)
      entry1 = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "sql_capsule_test_capsule")
      expect(entry1).to be_present
      original_id = entry1.id

      # Second execution
      described_class.execute(capsule, actor: actor)
      entry2 = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "sql_capsule_test_capsule")

      expect(entry2.id).to eq(original_id)
      expect(PgSqlTriggers::TriggerRegistry.where(trigger_name: "sql_capsule_test_capsule").count).to eq(1)
    end
  end
end
