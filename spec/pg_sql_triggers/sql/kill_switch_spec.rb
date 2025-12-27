# frozen_string_literal: true

require "rails_helper"

RSpec.describe PgSqlTriggers::SQL::KillSwitch do
  let(:logger) { instance_double(Logger) }

  before do
    # Reset thread-local state
    Thread.current[described_class::OVERRIDE_KEY] = nil

    # Clear ENV overrides
    ENV.delete("KILL_SWITCH_OVERRIDE")
    ENV.delete("CONFIRMATION_TEXT")

    # Setup default configuration
    allow(PgSqlTriggers).to receive_messages(kill_switch_enabled: true, kill_switch_environments: %i[production staging], kill_switch_confirmation_required: true, kill_switch_logger: logger, kill_switch_confirmation_pattern: ->(op) { "EXECUTE #{op.to_s.upcase}" })

    # Stub logger methods
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe ".active?" do
    context "when kill switch is globally disabled" do
      before do
        allow(PgSqlTriggers).to receive(:kill_switch_enabled).and_return(false)
      end

      it "returns false for production environment" do
        expect(described_class.active?(environment: "production")).to be false
      end

      it "returns false for development environment" do
        expect(described_class.active?(environment: "development")).to be false
      end
    end

    context "when kill switch is globally enabled" do
      it "returns true for production environment" do
        expect(described_class.active?(environment: "production")).to be true
      end

      it "returns true for staging environment" do
        expect(described_class.active?(environment: "staging")).to be true
      end

      it "returns false for development environment" do
        expect(described_class.active?(environment: "development")).to be false
      end

      it "returns false for test environment" do
        expect(described_class.active?(environment: "test")).to be false
      end

      it "handles symbol environments" do
        expect(described_class.active?(environment: :production)).to be true
      end

      it "logs the check" do
        expect(logger).to receive(:debug).with(/KILL_SWITCH.*Check.*production.*true/)
        described_class.active?(environment: "production", operation: :test_op)
      end
    end

    context "when custom protected environments are configured" do
      before do
        allow(PgSqlTriggers).to receive(:kill_switch_environments).and_return(%i[production qa])
      end

      it "returns true for custom protected environment" do
        expect(described_class.active?(environment: "qa")).to be true
      end

      it "returns false for staging if not in protected list" do
        expect(described_class.active?(environment: "staging")).to be false
      end
    end

    context "when environment is not provided" do
      it "detects Rails environment" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        expect(described_class.active?).to be true
      end
    end
  end

  describe ".check!" do
    let(:operation) { :migrate_up }
    let(:environment) { "production" }
    let(:actor) { { type: "CLI", id: "user@example.com" } }

    context "when in non-protected environment" do
      let(:environment) { "development" }

      it "does not raise error" do
        expect do
          described_class.check!(operation: operation, environment: environment)
        end.not_to raise_error
      end

      it "logs the allowed operation" do
        expect(logger).to receive(:info).with(/ALLOWED.*not_protected_environment/)
        described_class.check!(operation: operation, environment: environment)
      end
    end

    context "when in protected environment without override" do
      it "raises KillSwitchError" do
        expect do
          described_class.check!(operation: operation, environment: environment)
        end.to raise_error(PgSqlTriggers::KillSwitchError, /Kill switch is active/)
      end

      it "logs the blocked operation" do
        expect(logger).to receive(:error).with(/BLOCKED/)
        begin
          described_class.check!(operation: operation, environment: environment)
        rescue PgSqlTriggers::KillSwitchError
          # Expected
        end
      end

      it "includes override instructions in error message" do
        expect do
          described_class.check!(operation: operation, environment: environment)
        end.to raise_error(PgSqlTriggers::KillSwitchError, /KILL_SWITCH_OVERRIDE=true/)
      end

      it "includes confirmation text in error message" do
        expect do
          described_class.check!(operation: operation, environment: environment)
        end.to raise_error(PgSqlTriggers::KillSwitchError, /EXECUTE MIGRATE_UP/)
      end
    end

    context "with thread-local override" do
      before do
        Thread.current[described_class::OVERRIDE_KEY] = true
      end

      it "does not raise error" do
        expect do
          described_class.check!(operation: operation, environment: environment)
        end.not_to raise_error
      end

      it "logs the override" do
        expect(logger).to receive(:warn).with(/OVERRIDDEN.*thread_local/)
        described_class.check!(operation: operation, environment: environment)
      end
    end

    context "with ENV override" do
      before do
        ENV["KILL_SWITCH_OVERRIDE"] = "true"
      end

      # rubocop:disable RSpec/NestedGroups
      context "when confirmation is required" do
        before do
          ENV["CONFIRMATION_TEXT"] = "EXECUTE MIGRATE_UP"
        end

        it "does not raise error with correct confirmation" do
          expect do
            described_class.check!(
              operation: operation,
              environment: environment,
              confirmation: "EXECUTE MIGRATE_UP"
            )
          end.not_to raise_error
        end

        it "raises error with incorrect confirmation" do
          expect do
            described_class.check!(
              operation: operation,
              environment: environment,
              confirmation: "WRONG TEXT"
            )
          end.to raise_error(PgSqlTriggers::KillSwitchError, /Invalid confirmation text/)
        end

        it "logs the override with confirmation" do
          expect(logger).to receive(:warn).with(/OVERRIDDEN.*env_with_confirmation/)
          described_class.check!(
            operation: operation,
            environment: environment,
            confirmation: "EXECUTE MIGRATE_UP"
          )
        end
      end
      # rubocop:enable RSpec/NestedGroups

      # rubocop:disable RSpec/NestedGroups
      context "when confirmation is not required" do
        before do
          allow(PgSqlTriggers).to receive(:kill_switch_confirmation_required).and_return(false)
        end

        it "does not raise error without confirmation" do
          expect do
            described_class.check!(operation: operation, environment: environment)
          end.not_to raise_error
        end

        it "logs the override without confirmation" do
          expect(logger).to receive(:warn).with(/OVERRIDDEN.*env_without_confirmation/)
          described_class.check!(operation: operation, environment: environment)
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end

    context "with explicit confirmation" do
      it "does not raise error with correct confirmation" do
        expect do
          described_class.check!(
            operation: operation,
            environment: environment,
            confirmation: "EXECUTE MIGRATE_UP"
          )
        end.not_to raise_error
      end

      it "raises error with incorrect confirmation" do
        expect do
          described_class.check!(
            operation: operation,
            environment: environment,
            confirmation: "WRONG TEXT"
          )
        end.to raise_error(PgSqlTriggers::KillSwitchError, /Invalid confirmation text/)
      end

      it "raises error with empty confirmation" do
        expect do
          described_class.check!(
            operation: operation,
            environment: environment,
            confirmation: ""
          )
        end.to raise_error(PgSqlTriggers::KillSwitchError, /Confirmation text required/)
      end

      it "logs the override with explicit confirmation" do
        expect(logger).to receive(:warn).with(/OVERRIDDEN.*explicit_confirmation/)
        described_class.check!(
          operation: operation,
          environment: environment,
          confirmation: "EXECUTE MIGRATE_UP"
        )
      end
    end

    context "with actor information" do
      it "includes actor in log messages" do
        expect(logger).to receive(:error).with(/actor=CLI:user@example.com/)
        begin
          described_class.check!(
            operation: operation,
            environment: environment,
            actor: actor
          )
        rescue PgSqlTriggers::KillSwitchError
          # Expected
        end
      end
    end
  end

  describe ".override" do
    it "requires a block" do
      expect do
        described_class.override
      end.to raise_error(ArgumentError, /Block required/)
    end

    it "executes the block" do
      executed = false
      described_class.override do
        executed = true
      end
      expect(executed).to be true
    end

    it "returns the block result" do
      result = described_class.override { 42 }
      expect(result).to eq(42)
    end

    it "sets thread-local override during block execution" do
      described_class.override do
        expect(Thread.current[described_class::OVERRIDE_KEY]).to be true
      end
    end

    it "clears thread-local override after block execution" do
      described_class.override { :noop }
      expect(Thread.current[described_class::OVERRIDE_KEY]).to be_nil
    end

    it "clears override even if block raises error" do
      expect do
        described_class.override { raise "test error" }
      end.to raise_error("test error")

      expect(Thread.current[described_class::OVERRIDE_KEY]).to be_nil
    end

    it "allows nested overrides" do
      outer_executed = false
      inner_executed = false

      described_class.override do
        outer_executed = true
        described_class.override do
          inner_executed = true
          expect(Thread.current[described_class::OVERRIDE_KEY]).to be true
        end
        expect(Thread.current[described_class::OVERRIDE_KEY]).to be true
      end

      expect(outer_executed).to be true
      expect(inner_executed).to be true
      expect(Thread.current[described_class::OVERRIDE_KEY]).to be_nil
    end

    it "allows dangerous operations within override block" do
      expect do
        described_class.override do
          described_class.check!(
            operation: :migrate_up,
            environment: "production"
          )
        end
      end.not_to raise_error
    end

    context "with confirmation parameter" do
      it "logs the confirmation when provided" do
        expect(logger).to receive(:info).with(/Override block initiated.*EXECUTE TEST/)
        described_class.override(confirmation: "EXECUTE TEST") { :noop }
      end
    end
  end

  describe ".validate_confirmation!" do
    let(:operation) { :migrate_up }
    let(:expected) { "EXECUTE MIGRATE_UP" }

    it "does not raise error for correct confirmation" do
      expect do
        described_class.validate_confirmation!(expected, operation)
      end.not_to raise_error
    end

    it "raises error for incorrect confirmation" do
      expect do
        described_class.validate_confirmation!("WRONG TEXT", operation)
      end.to raise_error(PgSqlTriggers::KillSwitchError, /Invalid confirmation text/)
    end

    it "raises error for nil confirmation" do
      expect do
        described_class.validate_confirmation!(nil, operation)
      end.to raise_error(PgSqlTriggers::KillSwitchError, /Confirmation text required/)
    end

    it "raises error for empty confirmation" do
      expect do
        described_class.validate_confirmation!("", operation)
      end.to raise_error(PgSqlTriggers::KillSwitchError, /Confirmation text required/)
    end

    it "strips whitespace from confirmation" do
      expect do
        described_class.validate_confirmation!("  #{expected}  ", operation)
      end.not_to raise_error
    end

    it "includes expected confirmation in error message" do
      expect do
        described_class.validate_confirmation!("WRONG", operation)
      end.to raise_error(PgSqlTriggers::KillSwitchError, /Expected: 'EXECUTE MIGRATE_UP'/)
    end

    it "includes actual confirmation in error message" do
      expect do
        described_class.validate_confirmation!("WRONG", operation)
      end.to raise_error(PgSqlTriggers::KillSwitchError, /got: 'WRONG'/)
    end
  end

  describe "thread safety" do
    it "maintains separate override state per thread" do
      thread1_override = false
      thread2_override = false

      thread1 = Thread.new do
        described_class.override do
          thread1_override = Thread.current[described_class::OVERRIDE_KEY]
          sleep 0.1 # Allow thread2 to execute
        end
      end

      thread2 = Thread.new do
        sleep 0.05 # Allow thread1 to set override
        thread2_override = Thread.current[described_class::OVERRIDE_KEY]
      end

      thread1.join
      thread2.join

      expect(thread1_override).to be true
      expect(thread2_override).to be_nil
    end
  end

  describe "custom confirmation patterns" do
    before do
      allow(PgSqlTriggers).to receive(:kill_switch_confirmation_pattern).and_return(
        ->(op) { "CONFIRM-#{op.to_s.upcase}-NOW" }
      )
    end

    it "uses custom pattern for validation" do
      expect do
        described_class.check!(
          operation: :test_op,
          environment: "production",
          confirmation: "CONFIRM-TEST_OP-NOW"
        )
      end.not_to raise_error
    end

    it "rejects confirmation with default pattern" do
      expect do
        described_class.check!(
          operation: :test_op,
          environment: "production",
          confirmation: "EXECUTE TEST_OP"
        )
      end.to raise_error(PgSqlTriggers::KillSwitchError)
    end
  end

  describe "configuration defaults" do
    before do
      allow(PgSqlTriggers).to receive_messages(kill_switch_enabled: nil, kill_switch_environments: nil, kill_switch_confirmation_required: nil)
    end

    it "defaults to enabled when not configured" do
      expect(described_class.active?(environment: "production")).to be true
    end

    it "defaults to protecting production and staging" do
      expect(described_class.active?(environment: "production")).to be true
      expect(described_class.active?(environment: "staging")).to be true
    end

    it "defaults to requiring confirmation" do
      ENV["KILL_SWITCH_OVERRIDE"] = "true"
      expect do
        described_class.check!(operation: :test, environment: "production")
      end.to raise_error(PgSqlTriggers::KillSwitchError)
    end
  end

  describe "environment detection" do
    it "uses provided environment" do
      expect(described_class.active?(environment: "production")).to be true
    end

    it "falls back to Rails.env when not provided" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      expect(described_class.active?).to be true
    end

    it "falls back to RAILS_ENV when Rails is not available" do
      hide_const("Rails")
      ENV["RAILS_ENV"] = "production"
      expect(described_class.active?).to be true
    end

    it "falls back to RACK_ENV when RAILS_ENV is not available" do
      hide_const("Rails")
      ENV.delete("RAILS_ENV")
      ENV["RACK_ENV"] = "production"
      expect(described_class.active?).to be true
    end

    it "defaults to development when no environment is detectable" do
      hide_const("Rails")
      ENV.delete("RAILS_ENV")
      ENV.delete("RACK_ENV")
      expect(described_class.active?).to be false
    end
  end
end
