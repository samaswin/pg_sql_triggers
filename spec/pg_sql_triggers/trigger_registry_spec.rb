# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::TriggerRegistry do
  describe "validations" do
    it "requires trigger_name" do
      registry = described_class.new(
        table_name: "users",
        version: 1,
        checksum: "abc",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:trigger_name]).to include("can't be blank")
    end

    it "requires unique trigger_name" do
      described_class.create!(
        trigger_name: "unique_trigger",
        table_name: "users",
        version: 1,
        checksum: "abc",
        source: "dsl"
      )

      registry = described_class.new(
        trigger_name: "unique_trigger",
        table_name: "posts",
        version: 1,
        checksum: "def",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:trigger_name]).to include("has already been taken")
    end

    it "requires table_name" do
      registry = described_class.new(
        trigger_name: "test_trigger",
        version: 1,
        checksum: "abc",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:table_name]).to include("can't be blank")
    end

    it "requires version to be present and positive integer" do
      registry = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        version: nil,
        checksum: "abc",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:version]).to include("can't be blank")

      registry.version = 0
      expect(registry).not_to be_valid
      expect(registry.errors[:version]).to include("must be greater than 0")

      registry.version = -1
      expect(registry).not_to be_valid

      registry.version = 1
      expect(registry).to be_valid
    end

    it "requires checksum" do
      registry = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:checksum]).to include("can't be blank")
    end

    it "requires source to be one of valid values" do
      registry = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        checksum: "abc",
        source: "invalid"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:source]).to include("is not included in the list")

      %w[dsl generated manual_sql].each do |source|
        registry.source = source
        expect(registry).to be_valid
      end
    end
  end

  describe "scopes" do
    before do
      described_class.create!(
        trigger_name: "enabled1",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      described_class.create!(
        trigger_name: "enabled2",
        table_name: "posts",
        version: 1,
        enabled: true,
        checksum: "def",
        source: "dsl"
      )
      described_class.create!(
        trigger_name: "disabled1",
        table_name: "comments",
        version: 1,
        enabled: false,
        checksum: "ghi",
        source: "dsl"
      )
    end

    describe ".enabled" do
      it "returns only enabled triggers" do
        result = described_class.enabled
        expect(result.count).to eq(2)
        expect(result.map(&:trigger_name)).to contain_exactly("enabled1", "enabled2")
      end
    end

    describe ".disabled" do
      it "returns only disabled triggers" do
        result = described_class.disabled
        expect(result.count).to eq(1)
        expect(result.first.trigger_name).to eq("disabled1")
      end
    end

    describe ".for_table" do
      it "returns triggers for specific table" do
        result = described_class.for_table("users")
        expect(result.count).to eq(1)
        expect(result.first.trigger_name).to eq("enabled1")
      end
    end

    describe ".for_environment" do
      before do
        described_class.create!(
          trigger_name: "prod_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "jkl",
          source: "dsl",
          environment: "production"
        )
        described_class.create!(
          trigger_name: "no_env_trigger",
          table_name: "posts",
          version: 1,
          enabled: true,
          checksum: "mno",
          source: "dsl",
          environment: nil
        )
      end

      it "returns triggers for specific environment or nil" do
        result = described_class.for_environment("production")
        expect(result.map(&:trigger_name)).to include("prod_trigger", "no_env_trigger")
      end
    end

    describe ".by_source" do
      before do
        described_class.create!(
          trigger_name: "generated_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "pqr",
          source: "generated"
        )
      end

      it "returns triggers by source" do
        dsl_triggers = described_class.by_source("dsl")
        expect(dsl_triggers.count).to eq(3)

        generated_triggers = described_class.by_source("generated")
        expect(generated_triggers.count).to eq(1)
        expect(generated_triggers.first.trigger_name).to eq("generated_trigger")
      end
    end
  end

  describe "#drift_state" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "delegates to Drift.detect" do
      allow(PgSqlTriggers::Drift).to receive(:detect).with("test_trigger").and_return({ state: :in_sync })
      expect(registry.drift_state).to eq(:in_sync)
    end
  end

  describe "#enable!" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: false,
        checksum: "abc",
        source: "dsl"
      )
    end

    context "when trigger exists in database" do
      before do
        # Create a test table and trigger
        ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR)")
        begin
          ActiveRecord::Base.connection.execute("CREATE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
          ActiveRecord::Base.connection.execute("CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_function();")
        rescue StandardError
          # Trigger might already exist
        end
      end

      after do
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON users")
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
      rescue StandardError => _e
        # Ignore errors during cleanup - trigger/function may not exist
      end

      it "enables the trigger in database" do
        registry.enable!
        expect(registry.enabled).to be(true)
        expect(registry.reload.enabled).to be(true)
      end
    end

    context "when trigger doesn't exist in database" do
      it "updates registry even if trigger doesn't exist" do
        expect { registry.enable! }.not_to raise_error
        expect(registry.reload.enabled).to be(true)
      end
    end
  end

  describe "#disable!" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    context "when trigger exists in database" do
      before do
        ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR)")
        begin
          ActiveRecord::Base.connection.execute("CREATE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
          ActiveRecord::Base.connection.execute("CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_function();")
        rescue StandardError
          # Trigger might already exist
        end
      end

      after do
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON users")
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
      rescue StandardError => _e
        # Ignore errors during cleanup - trigger/function may not exist
      end

      it "disables the trigger in database" do
        registry.disable!
        expect(registry.enabled).to be(false)
        expect(registry.reload.enabled).to be(false)
      end
    end

    context "when trigger doesn't exist in database" do
      it "updates registry even if trigger doesn't exist" do
        expect { registry.disable! }.not_to raise_error
        expect(registry.reload.enabled).to be(false)
      end
    end

    it "checks kill switch before disabling" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :trigger_disable,
        environment: Rails.env,
        confirmation: nil,
        actor: { type: "Console", id: "TriggerRegistry#disable!" }
      )
      registry.disable!
    end

    it "uses explicit confirmation when provided" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :trigger_disable,
        environment: Rails.env,
        confirmation: "custom_confirmation",
        actor: { type: "Console", id: "TriggerRegistry#disable!" }
      )
      registry.disable!(confirmation: "custom_confirmation")
    end

    it "handles errors when checking trigger existence" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_raise(StandardError.new("DB error"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect { registry.disable! }.not_to raise_error
      expect(registry.reload.enabled).to be(false)
    end

    it "handles errors when disabling trigger in database" do
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY)")
      # Ensure registry is created before setting up the mock
      registry # Force evaluation of let(:registry) before mock is set up
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::StatementInvalid.new("Error"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(PgSqlTriggers::DatabaseIntrospection).to receive(:trigger_exists?).and_return(true)
      # rubocop:enable RSpec/AnyInstance
      expect { registry.disable! }.not_to raise_error
      expect(registry.reload.enabled).to be(false)
    end
  end

  describe "#drift_result" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "delegates to Drift::Detector.detect" do
      allow(PgSqlTriggers::Drift::Detector).to receive(:detect).with("test_trigger").and_return({ state: :in_sync })
      expect(registry.drift_result).to eq({ state: :in_sync })
    end
  end

  describe "#drifted?" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "returns true when drift_state is drifted" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_DRIFTED)
      expect(registry.drifted?).to be true
    end

    it "returns false when drift_state is not drifted" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_IN_SYNC)
      expect(registry.drifted?).to be false
    end
  end

  describe "#in_sync?" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "returns true when drift_state is in_sync" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_IN_SYNC)
      expect(registry.in_sync?).to be true
    end

    it "returns false when drift_state is not in_sync" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_DRIFTED)
      expect(registry.in_sync?).to be false
    end
  end

  describe "#dropped?" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "returns true when drift_state is dropped" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_DROPPED)
      expect(registry.dropped?).to be true
    end

    it "returns false when drift_state is not dropped" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_IN_SYNC)
      expect(registry.dropped?).to be false
    end
  end

  describe "#enable! edge cases" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: false,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "checks kill switch before enabling" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :trigger_enable,
        environment: Rails.env,
        confirmation: nil,
        actor: { type: "Console", id: "TriggerRegistry#enable!" }
      )
      registry.enable!
    end

    it "uses explicit confirmation when provided" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :trigger_enable,
        environment: Rails.env,
        confirmation: "custom_confirmation",
        actor: { type: "Console", id: "TriggerRegistry#enable!" }
      )
      registry.enable!(confirmation: "custom_confirmation")
    end

    it "handles errors when checking trigger existence" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_raise(StandardError.new("DB error"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect { registry.enable! }.not_to raise_error
      expect(registry.reload.enabled).to be(true)
    end

    it "handles errors when enabling trigger in database" do
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY)")
      # Ensure registry is created before setting up the mock
      registry # Force evaluation of let(:registry) before mock is set up
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::StatementInvalid.new("Error"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(PgSqlTriggers::DatabaseIntrospection).to receive(:trigger_exists?).and_return(true)
      # rubocop:enable RSpec/AnyInstance
      expect { registry.enable! }.not_to raise_error
      expect(registry.reload.enabled).to be(true)
    end
  end

  describe "#drop!" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "test_table",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl",
        function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      )
    end

    let(:actor) { { type: "User", id: 1 } }

    before do
      # Create test table
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, name VARCHAR)")
      # Create test trigger function and trigger in database
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        CREATE OR REPLACE FUNCTION test_function()
        RETURNS TRIGGER AS $$
        BEGIN
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        CREATE TRIGGER test_trigger
        BEFORE INSERT ON test_table
        FOR EACH ROW
        EXECUTE FUNCTION test_function();
      SQL
      # Stub kill switch by default
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # Stub logger
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_table CASCADE")
    end

    context "with valid reason and confirmation" do
      it "drops the trigger from database" do
        # Verify trigger exists before drop
        introspection = PgSqlTriggers::DatabaseIntrospection.new
        expect(introspection.trigger_exists?("test_trigger")).to be true

        registry.drop!(reason: "No longer needed", actor: actor)

        # Verify trigger was actually dropped from database
        expect(introspection.trigger_exists?("test_trigger")).to be false
      end

      it "removes registry entry" do
        # Ensure registry exists before drop
        registry.reload

        expect do
          registry.drop!(reason: "Cleanup", actor: actor)
        end.to change(described_class, :count).by(-1)
      end

      it "executes in transaction" do
        expect(ActiveRecord::Base).to receive(:transaction).and_call_original
        registry.drop!(reason: "Testing", actor: actor)
      end

      it "logs drop attempt" do
        expect(Rails.logger).to receive(:info).with(/TRIGGER_DROP.*Dropping/)
        expect(Rails.logger).to receive(:info).with(/TRIGGER_DROP.*Reason/)
        registry.drop!(reason: "Test reason", actor: actor)
      end

      it "logs successful drop" do
        expect(Rails.logger).to receive(:info).with(/Successfully removed from registry/)
        registry.drop!(reason: "Test", actor: actor)
      end

      it "accepts confirmation parameter" do
        expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
          hash_including(confirmation: "DROP TRIGGER")
        )
        registry.drop!(reason: "Test", confirmation: "DROP TRIGGER", actor: actor)
      end
    end

    context "when reason is missing" do
      it "raises ArgumentError when reason is nil" do
        expect do
          registry.drop!(reason: nil, actor: actor)
        end.to raise_error(ArgumentError, /Reason is required/)
      end

      it "raises ArgumentError when reason is empty string" do
        expect do
          registry.drop!(reason: "", actor: actor)
        end.to raise_error(ArgumentError, /Reason is required/)
      end

      it "raises ArgumentError when reason is whitespace only" do
        expect do
          registry.drop!(reason: "   ", actor: actor)
        end.to raise_error(ArgumentError, /Reason is required/)
      end
    end

    context "when kill switch blocks operation" do
      before do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!)
          .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch active"))
      end

      it "raises KillSwitchError" do
        expect do
          registry.drop!(reason: "Test", actor: actor)
        end.to raise_error(PgSqlTriggers::KillSwitchError)
      end

      it "does not drop trigger" do
        expect do
          registry.drop!(reason: "Test", actor: actor)
        end.to raise_error(PgSqlTriggers::KillSwitchError)

        expect(registry.reload).to be_present
      end
    end

    context "when trigger does not exist in database" do
      before do
        # Drop the trigger that was created in the outer before block
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON test_table")
      end

      it "still removes registry entry" do
        # Ensure registry exists
        registry.reload

        # Verify trigger doesn't exist
        introspection = PgSqlTriggers::DatabaseIntrospection.new
        expect(introspection.trigger_exists?("test_trigger")).to be false

        expect do
          registry.drop!(reason: "Cleanup", actor: actor)
        end.to change(described_class, :count).by(-1)
      end

      it "does not attempt to drop trigger from database" do
        # Verify trigger doesn't exist before and after
        introspection = PgSqlTriggers::DatabaseIntrospection.new
        expect(introspection.trigger_exists?("test_trigger")).to be false

        registry.drop!(reason: "Cleanup", actor: actor)

        expect(introspection.trigger_exists?("test_trigger")).to be false
      end
    end

    context "when DROP TRIGGER fails" do
      before do
        # Ensure registry exists
        registry.reload

        # Stub connection execute to fail for DROP TRIGGER but delegate everything else
        # This simulates database errors like permissions, locks, etc.
        allow(ActiveRecord::Base.connection).to receive(:execute).and_wrap_original do |original_method, sql, *args|
          if sql.to_s.match?(/DROP TRIGGER/i)
            raise ActiveRecord::StatementInvalid, "PG::Error: simulated database error"
          end

          original_method.call(sql, *args)
        end
      end

      it "raises error and rolls back transaction" do
        expect do
          registry.drop!(reason: "Test", actor: actor)
        end.to raise_error(ActiveRecord::StatementInvalid)

        # Verify registry was not deleted (transaction rolled back)
        expect(described_class.exists?(registry.id)).to be true
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/TRIGGER_DROP.*Failed/)

        expect do
          registry.drop!(reason: "Test", actor: actor)
        end.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    context "with kill switch check" do
      it "checks kill switch before dropping" do
        expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
          operation: :trigger_drop,
          environment: Rails.env,
          confirmation: nil,
          actor: actor
        )
        registry.drop!(reason: "Test", actor: actor)
      end

      it "uses default actor if not provided" do
        expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
          hash_including(actor: { type: "Console", id: "TriggerRegistry#drop!" })
        )
        registry.drop!(reason: "Test")
      end
    end
  end

  describe "#re_execute!" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "test_table",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl",
        function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql; CREATE TRIGGER test_trigger BEFORE INSERT ON test_table FOR EACH ROW EXECUTE FUNCTION test_function();"
      )
    end

    let(:actor) { { type: "User", id: 1 } }

    before do
      # Create test table
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, name VARCHAR)")
      # Create test trigger function and trigger in database
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        CREATE OR REPLACE FUNCTION test_function()
        RETURNS TRIGGER AS $$
        BEGIN
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        CREATE TRIGGER test_trigger
        BEFORE INSERT ON test_table
        FOR EACH ROW
        EXECUTE FUNCTION test_function();
      SQL
      # Stub kill switch by default
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # Stub logger
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
      # Stub drift detection
      allow(registry).to receive(:drift_result).and_return({ state: :drifted })
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_table CASCADE")
    end

    context "with valid reason and confirmation" do
      it "recreates trigger successfully" do
        # Verify trigger exists before re-execute
        introspection = PgSqlTriggers::DatabaseIntrospection.new
        expect(introspection.trigger_exists?("test_trigger")).to be true

        registry.re_execute!(reason: "Fix drift", actor: actor)

        # Verify trigger still exists after re-execute (it was dropped and recreated)
        expect(introspection.trigger_exists?("test_trigger")).to be true
      end

      it "updates registry after re-execution" do
        freeze_time do
          registry.re_execute!(reason: "Fix drift", actor: actor)

          expect(registry.reload.enabled).to be true
          expect(registry.last_executed_at).to be_within(1.second).of(Time.current)
        end
      end

      it "executes in transaction" do
        expect(ActiveRecord::Base).to receive(:transaction).and_call_original
        registry.re_execute!(reason: "Fix drift", actor: actor)
      end

      it "logs re-execute attempt" do
        expect(Rails.logger).to receive(:info).with(/TRIGGER_RE_EXECUTE.*Re-executing/)
        expect(Rails.logger).to receive(:info).with(/TRIGGER_RE_EXECUTE.*Reason/)
        registry.re_execute!(reason: "Fix drift", actor: actor)
      end

      it "logs drift state" do
        expect(Rails.logger).to receive(:info).with(/Current state/)
        registry.re_execute!(reason: "Fix drift", actor: actor)
      end

      it "accepts confirmation parameter" do
        expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
          hash_including(confirmation: "RE-EXECUTE")
        )
        registry.re_execute!(reason: "Fix drift", confirmation: "RE-EXECUTE", actor: actor)
      end
    end

    context "when reason is missing" do
      it "raises ArgumentError when reason is nil" do
        expect do
          registry.re_execute!(reason: nil, actor: actor)
        end.to raise_error(ArgumentError, /Reason is required/)
      end

      it "raises ArgumentError when reason is empty string" do
        expect do
          registry.re_execute!(reason: "", actor: actor)
        end.to raise_error(ArgumentError, /Reason is required/)
      end

      it "raises ArgumentError when reason is whitespace only" do
        expect do
          registry.re_execute!(reason: "   ", actor: actor)
        end.to raise_error(ArgumentError, /Reason is required/)
      end
    end

    context "when function_body is missing" do
      before do
        # rubocop:disable Rails/SkipsModelValidations
        registry.update_column(:function_body, nil)
        # rubocop:enable Rails/SkipsModelValidations
      end

      it "raises StandardError" do
        expect do
          registry.re_execute!(reason: "Fix", actor: actor)
        end.to raise_error(StandardError, /Cannot re-execute.*missing function_body/)
      end
    end

    context "when function_body is blank" do
      before do
        # rubocop:disable Rails/SkipsModelValidations
        registry.update_column(:function_body, "")
        # rubocop:enable Rails/SkipsModelValidations
      end

      it "raises StandardError" do
        expect do
          registry.re_execute!(reason: "Fix", actor: actor)
        end.to raise_error(StandardError, /Cannot re-execute.*missing function_body/)
      end
    end

    context "when kill switch blocks operation" do
      before do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!)
          .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch active"))
      end

      it "raises KillSwitchError" do
        expect do
          registry.re_execute!(reason: "Fix", actor: actor)
        end.to raise_error(PgSqlTriggers::KillSwitchError)
      end

      it "does not re-execute trigger" do
        # Verify trigger exists before
        introspection = PgSqlTriggers::DatabaseIntrospection.new
        expect(introspection.trigger_exists?("test_trigger")).to be true

        expect do
          registry.re_execute!(reason: "Fix", actor: actor)
        end.to raise_error(PgSqlTriggers::KillSwitchError)

        # Verify trigger still exists and wasn't modified
        expect(introspection.trigger_exists?("test_trigger")).to be true
      end
    end

    context "when trigger does not exist in database" do
      before do
        # Drop the trigger that was created in the outer before block
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON test_table")
      end

      it "creates trigger even when it doesn't exist" do
        # Verify trigger doesn't exist before re-execute
        introspection = PgSqlTriggers::DatabaseIntrospection.new
        expect(introspection.trigger_exists?("test_trigger")).to be false

        registry.re_execute!(reason: "Recreate", actor: actor)

        # Verify trigger was created
        expect(introspection.trigger_exists?("test_trigger")).to be true
      end
    end

    context "when trigger recreation fails" do
      before do
        # Stub connection execute to fail for CREATE statements but delegate everything else
        # This simulates database errors like syntax errors, permission issues, etc.
        allow(ActiveRecord::Base.connection).to receive(:execute).and_wrap_original do |original_method, sql, *args|
          if sql.to_s.include?(registry.function_body)
            raise ActiveRecord::StatementInvalid, "PG::Error: simulated SQL error"
          end

          original_method.call(sql, *args)
        end
      end

      it "raises error and rolls back transaction" do
        original_enabled = registry.enabled

        expect do
          registry.re_execute!(reason: "Fix", actor: actor)
        end.to raise_error(ActiveRecord::StatementInvalid)

        expect(registry.reload.enabled).to eq(original_enabled)
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/TRIGGER_RE_EXECUTE.*Failed/)

        expect do
          registry.re_execute!(reason: "Fix", actor: actor)
        end.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    context "with kill switch check" do
      it "checks kill switch before re-executing" do
        expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
          operation: :trigger_re_execute,
          environment: Rails.env,
          confirmation: nil,
          actor: actor
        )
        registry.re_execute!(reason: "Fix", actor: actor)
      end

      it "uses default actor if not provided" do
        expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
          hash_including(actor: { type: "Console", id: "TriggerRegistry#re_execute!" })
        )
        registry.re_execute!(reason: "Fix")
      end
    end

    context "with logging" do
      it "logs successful drop" do
        expect(Rails.logger).to receive(:info).with(/Dropped existing/)
        registry.re_execute!(reason: "Fix", actor: actor)
      end

      it "logs successful recreation" do
        expect(Rails.logger).to receive(:info).with(/Re-created trigger/)
        registry.re_execute!(reason: "Fix", actor: actor)
      end

      it "logs registry update" do
        expect(Rails.logger).to receive(:info).with(/Updated registry/)
        registry.re_execute!(reason: "Fix", actor: actor)
      end

      it "warns when drop fails but continues" do
        # Drop actual trigger so CREATE won't fail with "already exists"
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON test_table")

        # Stub DatabaseIntrospection to say trigger exists so DROP is attempted
        introspection = instance_double(PgSqlTriggers::DatabaseIntrospection)
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(introspection)
        allow(introspection).to receive(:trigger_exists?).with("test_trigger").and_return(true)

        # Stub connection execute to fail for DROP TRIGGER but allow other operations
        allow(ActiveRecord::Base.connection).to receive(:execute).and_wrap_original do |original_method, sql, *args|
          raise StandardError, "Drop failed" if sql.to_s.match?(/DROP TRIGGER/i)

          original_method.call(sql, *args)
        end

        expect(Rails.logger).to receive(:warn).with(/Drop failed/)

        # Should still attempt to recreate and succeed
        registry.re_execute!(reason: "Fix", actor: actor)
      end
    end
  end

  describe "private methods" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "test_table",
        version: 1,
        checksum: "abc123",
        source: "dsl",
        function_body: "CREATE FUNCTION test() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        condition: "NEW.status = 'active'"
      )
    end

    describe "#quote_identifier" do
      it "quotes table identifiers safely" do
        # Access private method using send
        quoted = registry.send(:quote_identifier, "users")
        expect(quoted).to be_a(String)
        expect(quoted).not_to eq("users") # Should be quoted
      end

      it "handles special characters safely" do
        quoted = registry.send(:quote_identifier, "table-with-dash")
        expect(quoted).to be_a(String)
      end
    end

    describe "#calculate_checksum" do
      it "calculates checksum from trigger attributes" do
        checksum = registry.send(:calculate_checksum)
        expect(checksum).to be_a(String)
        expect(checksum.length).to eq(64) # SHA256 produces 64 character hex string
      end

      it "includes trigger_name in checksum" do
        checksum1 = registry.send(:calculate_checksum)
        registry.trigger_name = "different_trigger"
        checksum2 = registry.send(:calculate_checksum)
        expect(checksum1).not_to eq(checksum2)
      end

      it "includes table_name in checksum" do
        checksum1 = registry.send(:calculate_checksum)
        registry.table_name = "different_table"
        checksum2 = registry.send(:calculate_checksum)
        expect(checksum1).not_to eq(checksum2)
      end

      it "includes version in checksum" do
        checksum1 = registry.send(:calculate_checksum)
        registry.version = 2
        checksum2 = registry.send(:calculate_checksum)
        expect(checksum1).not_to eq(checksum2)
      end

      it "includes function_body in checksum" do
        checksum1 = registry.send(:calculate_checksum)
        registry.function_body = "CREATE FUNCTION other() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
        checksum2 = registry.send(:calculate_checksum)
        expect(checksum1).not_to eq(checksum2)
      end

      it "includes condition in checksum" do
        checksum1 = registry.send(:calculate_checksum)
        registry.condition = "NEW.status = 'inactive'"
        checksum2 = registry.send(:calculate_checksum)
        expect(checksum1).not_to eq(checksum2)
      end

      it "handles nil function_body" do
        registry.function_body = nil
        checksum = registry.send(:calculate_checksum)
        expect(checksum).to be_a(String)
        expect(checksum.length).to eq(64)
      end

      it "handles nil condition" do
        registry.condition = nil
        checksum = registry.send(:calculate_checksum)
        expect(checksum).to be_a(String)
        expect(checksum.length).to eq(64)
      end
    end

    describe "#verify!" do
      it "updates last_verified_at timestamp" do
        freeze_time do
          expect do
            registry.send(:verify!)
          end.to change { registry.reload.last_verified_at }.to(Time.current)
        end
      end
    end
  end
end
