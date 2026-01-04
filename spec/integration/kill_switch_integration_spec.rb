# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Kill Switch Integration", type: :integration do
  # rubocop:enable RSpec/DescribeClass
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }

  before do
    # Use real configuration
    PgSqlTriggers.kill_switch_enabled = true
    PgSqlTriggers.kill_switch_environments = %i[production staging]
    PgSqlTriggers.kill_switch_confirmation_required = true
    PgSqlTriggers.kill_switch_logger = logger
    PgSqlTriggers.kill_switch_confirmation_pattern = ->(op) { "EXECUTE #{op.to_s.upcase}" }

    # Clear ENV overrides
    ENV.delete("KILL_SWITCH_OVERRIDE")
    ENV.delete("CONFIRMATION_TEXT")

    # Reset thread-local state
    Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY] = nil
  end

  after do
    # Reset configuration to defaults
    PgSqlTriggers.kill_switch_enabled = true
    PgSqlTriggers.kill_switch_environments = %i[production staging]
    PgSqlTriggers.kill_switch_confirmation_required = true
    PgSqlTriggers.kill_switch_logger = nil
    PgSqlTriggers.kill_switch_confirmation_pattern = ->(operation) { "EXECUTE #{operation.to_s.upcase}" }
  end

  describe "Console Integration" do
    describe "TriggerRegistry" do
      let(:trigger) { create(:trigger_registry, :production, enabled: false) }

      before do
        create_users_table
      end

      after do
        drop_test_table(:users)
      end

      context "when in production environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        end

        it "blocks enable! without confirmation" do
          expect do
            trigger.enable!
          end.to raise_error(PgSqlTriggers::KillSwitchError, /Kill switch is active/)
        end

        it "blocks disable! without confirmation" do
          expect do
            trigger.disable!
          end.to raise_error(PgSqlTriggers::KillSwitchError, /Kill switch is active/)
        end

        it "allows enable! with correct confirmation" do
          expect do
            trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
          end.not_to raise_error

          # Verify the trigger was actually enabled in the database
          trigger.reload
          expect(trigger.enabled).to be true
        end

        it "allows disable! with correct confirmation" do
          trigger.update!(enabled: true)

          expect do
            trigger.disable!(confirmation: "EXECUTE TRIGGER_DISABLE")
          end.not_to raise_error

          # Verify the trigger was actually disabled in the database
          trigger.reload
          expect(trigger.enabled).to be false
        end

        it "logs override when confirmation provided" do
          trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")

          log_content = log_output.string
          expect(log_content).to match(/OVERRIDDEN.*trigger_enable/i)
        end
      end
      # rubocop:enable RSpec/NestedGroups

      # rubocop:disable RSpec/NestedGroups
      context "when in development environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        end

        it "allows enable! without confirmation" do
          expect do
            trigger.enable!
          end.not_to raise_error

          # Verify the trigger was actually enabled
          trigger.reload
          expect(trigger.enabled).to be true
        end

        it "allows disable! without confirmation" do
          trigger.update!(enabled: true)

          expect do
            trigger.disable!
          end.not_to raise_error

          # Verify the trigger was actually disabled
          trigger.reload
          expect(trigger.enabled).to be false
        end
      end
      # rubocop:enable RSpec/NestedGroups

      # rubocop:disable RSpec/NestedGroups
      context "with override block" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        end

        it "allows operations within override block" do
          expect do
            PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE TRIGGER_ENABLE") do
              trigger.enable!
            end
          end.not_to raise_error

          # Verify the trigger was actually enabled
          trigger.reload
          expect(trigger.enabled).to be true
        end

        it "maintains thread-local override state" do
          PgSqlTriggers::SQL::KillSwitch.override do
            expect(Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY]).to be true
          end
          expect(Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY]).to be_nil
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end

    describe "Migrator" do
      let(:migrations_dir) { Pathname.new(Dir.mktmpdir) }

      before do
        # Create a real migrations directory structure
        FileUtils.mkdir_p(migrations_dir)

        # Create a sample migration file
        File.write(migrations_dir.join("001_test_migration.rb"), <<~RUBY)
          # frozen_string_literal: true

          class TestMigration < PgSqlTriggers::Migration
            def up
              # Migration up code
            end

            def down
              # Migration down code
            end
          end
        RUBY

        # Stub the migrations directory
        allow(PgSqlTriggers::Migrator).to receive(:migrations_dir).and_return(migrations_dir)
      end

      after do
        FileUtils.rm_rf(migrations_dir)
        # Clean up migration records
        PgSqlTriggers::Migrator.ensure_migrations_table!
        ActiveRecord::Base.connection.execute("TRUNCATE TABLE trigger_migrations")
      end

      # rubocop:disable RSpec/NestedGroups
      context "when in production environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        end

        it "blocks run_up without confirmation" do
          expect do
            PgSqlTriggers::Migrator.run_up
          end.to raise_error(PgSqlTriggers::KillSwitchError, /Kill switch is active/)
        end

        it "blocks run_down without confirmation" do
          # Record a migration as having been run
          ActiveRecord::Base.connection.execute(
            "INSERT INTO trigger_migrations (version) VALUES ('001') ON CONFLICT (version) DO NOTHING"
          )

          expect do
            PgSqlTriggers::Migrator.run_down
          end.to raise_error(PgSqlTriggers::KillSwitchError, /Kill switch is active/)
        end

        it "allows run_up with correct confirmation" do
          expect do
            PgSqlTriggers::Migrator.run_up(nil, confirmation: "EXECUTE MIGRATOR_RUN_UP")
          end.not_to raise_error
        end

        it "allows run_down with correct confirmation" do
          # Record a migration as having been run
          ActiveRecord::Base.connection.execute(
            "INSERT INTO trigger_migrations (version) VALUES ('001') ON CONFLICT (version) DO NOTHING"
          )

          expect do
            PgSqlTriggers::Migrator.run_down(nil, confirmation: "EXECUTE MIGRATOR_RUN_DOWN")
          end.not_to raise_error
        end
      end

      context "when in development environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        end

        it "allows run_up without confirmation" do
          expect do
            PgSqlTriggers::Migrator.run_up
          end.not_to raise_error
        end

        it "allows run_down without confirmation" do
          # Record a migration as having been run
          ActiveRecord::Base.connection.execute(
            "INSERT INTO trigger_migrations (version) VALUES ('001') ON CONFLICT (version) DO NOTHING"
          )

          expect do
            PgSqlTriggers::Migrator.run_down
          end.not_to raise_error
        end
      end
      # rubocop:enable RSpec/NestedGroups

      # rubocop:disable RSpec/NestedGroups
      context "with ENV override" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
          ENV["KILL_SWITCH_OVERRIDE"] = "true"
        end

        it "allows run_up with confirmation via ENV" do
          expect do
            # Simulate what happens in rake task - confirmation comes from ENV
            PgSqlTriggers::SQL::KillSwitch.check!(
              operation: :migrator_run_up,
              environment: "production",
              confirmation: "EXECUTE MIGRATOR_RUN_UP",
              actor: { type: "CLI", id: "test" }
            )
          end.not_to raise_error
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end
  end

  describe "End-to-End Scenarios" do
    # rubocop:disable RSpec/ContextWording
    context "production deployment workflow" do
      let(:trigger) { create(:trigger_registry, :production, enabled: false) }

      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        create_users_table
      end

      after do
        drop_test_table(:users)
      end

      it "blocks all dangerous operations by default" do
        expect { trigger.enable! }.to raise_error(PgSqlTriggers::KillSwitchError)
        expect { PgSqlTriggers::Migrator.run_up }.to raise_error(PgSqlTriggers::KillSwitchError)
      end

      it "allows operations with proper confirmation workflow" do
        # Enable trigger with confirmation
        expect do
          trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
        end.not_to raise_error

        # Verify enabled
        trigger.reload
        expect(trigger.enabled).to be true

        # Run migration with override block
        expect do
          PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE MIGRATOR_RUN_UP") do
            PgSqlTriggers::Migrator.run_up
          end
        end.not_to raise_error
      end
    end
    # rubocop:enable RSpec/ContextWording

    context "when logging and audit trail" do
      let(:trigger) { create(:trigger_registry, :production, enabled: false) }

      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        create_users_table
      end

      after do
        drop_test_table(:users)
      end

      it "logs all kill switch events" do
        # Blocked operation
        begin
          trigger.enable!
        rescue PgSqlTriggers::KillSwitchError
          # Expected
        end

        log_content = log_output.string
        expect(log_content).to match(/BLOCKED.*trigger_enable/i)

        # Clear log for next test
        log_output.truncate(0)
        log_output.rewind

        # Overridden operation
        trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")

        log_content = log_output.string
        expect(log_content).to match(/OVERRIDDEN.*trigger_enable.*explicit_confirmation/i)
      end
    end

    context "when using custom confirmation patterns" do
      let(:trigger) { create(:trigger_registry, :production, enabled: false) }

      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        PgSqlTriggers.kill_switch_confirmation_pattern = ->(op) { "CONFIRM-#{op.to_s.upcase}-NOW" }
        create_users_table
      end

      after do
        drop_test_table(:users)
      end

      it "uses custom confirmation pattern" do
        expect do
          trigger.enable!(confirmation: "CONFIRM-TRIGGER_ENABLE-NOW")
        end.not_to raise_error

        # Verify enabled
        trigger.reload
        expect(trigger.enabled).to be true

        # Create a new trigger for the second test
        trigger2 = create(:trigger_registry, :production, enabled: false)

        expect do
          trigger2.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
        end.to raise_error(PgSqlTriggers::KillSwitchError, /Invalid confirmation text/)
      end
    end
  end

  describe "Thread Safety" do
    it "maintains separate override state per thread" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      thread1_result = nil
      thread2_result = nil

      thread1 = Thread.new do
        PgSqlTriggers::SQL::KillSwitch.override do
          sleep 0.05
          thread1_result = Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY]
        end
      end

      thread2 = Thread.new do
        sleep 0.02
        thread2_result = Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY]
      end

      thread1.join
      thread2.join

      expect(thread1_result).to be true
      expect(thread2_result).to be_nil
    end
  end

  describe "Configuration Flexibility" do
    context "with kill switch disabled globally" do
      let(:trigger) { create(:trigger_registry, :production, enabled: false) }

      before do
        PgSqlTriggers.kill_switch_enabled = false
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        create_users_table
      end

      after do
        drop_test_table(:users)
      end

      it "allows all operations without confirmation" do
        expect { trigger.enable! }.not_to raise_error
        expect { trigger.disable! }.not_to raise_error

        # Verify operations were executed
        trigger.reload
        expect(trigger.enabled).to be false # Last operation was disable
      end
    end

    context "with custom protected environments" do
      before do
        PgSqlTriggers.kill_switch_environments = %i[production qa]
      end

      it "protects custom environments" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("qa"))
        create_users_table

        trigger = create(:trigger_registry, environment: "qa", enabled: false)
        expect { trigger.enable! }.to raise_error(PgSqlTriggers::KillSwitchError)

        drop_test_table(:users)
      end

      it "does not protect staging if not in list" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("staging"))
        create_users_table

        trigger = create(:trigger_registry, :staging, enabled: false)
        expect { trigger.enable! }.not_to raise_error

        # Verify operation executed
        trigger.reload
        expect(trigger.enabled).to be true

        drop_test_table(:users)
      end
    end
  end
end
