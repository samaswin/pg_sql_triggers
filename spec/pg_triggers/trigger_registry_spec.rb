# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers::TriggerRegistry do
  describe "validations" do
    it "requires trigger_name" do
      registry = PgTriggers::TriggerRegistry.new(
        table_name: "users",
        version: 1,
        checksum: "abc",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:trigger_name]).to include("can't be blank")
    end

    it "requires unique trigger_name" do
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "unique_trigger",
        table_name: "users",
        version: 1,
        checksum: "abc",
        source: "dsl"
      )

      registry = PgTriggers::TriggerRegistry.new(
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
      registry = PgTriggers::TriggerRegistry.new(
        trigger_name: "test_trigger",
        version: 1,
        checksum: "abc",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:table_name]).to include("can't be blank")
    end

    it "requires version to be present and positive integer" do
      registry = PgTriggers::TriggerRegistry.new(
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
      registry = PgTriggers::TriggerRegistry.new(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:checksum]).to include("can't be blank")
    end

    it "requires source to be one of valid values" do
      registry = PgTriggers::TriggerRegistry.new(
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
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "enabled1",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "enabled2",
        table_name: "posts",
        version: 1,
        enabled: true,
        checksum: "def",
        source: "dsl"
      )
      PgTriggers::TriggerRegistry.create!(
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
        result = PgTriggers::TriggerRegistry.enabled
        expect(result.count).to eq(2)
        expect(result.map(&:trigger_name)).to contain_exactly("enabled1", "enabled2")
      end
    end

    describe ".disabled" do
      it "returns only disabled triggers" do
        result = PgTriggers::TriggerRegistry.disabled
        expect(result.count).to eq(1)
        expect(result.first.trigger_name).to eq("disabled1")
      end
    end

    describe ".for_table" do
      it "returns triggers for specific table" do
        result = PgTriggers::TriggerRegistry.for_table("users")
        expect(result.count).to eq(1)
        expect(result.first.trigger_name).to eq("enabled1")
      end
    end

    describe ".for_environment" do
      before do
        PgTriggers::TriggerRegistry.create!(
          trigger_name: "prod_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "jkl",
          source: "dsl",
          environment: "production"
        )
        PgTriggers::TriggerRegistry.create!(
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
        result = PgTriggers::TriggerRegistry.for_environment("production")
        expect(result.map(&:trigger_name)).to include("prod_trigger", "no_env_trigger")
      end
    end

    describe ".by_source" do
      before do
        PgTriggers::TriggerRegistry.create!(
          trigger_name: "generated_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "pqr",
          source: "generated"
        )
      end

      it "returns triggers by source" do
        dsl_triggers = PgTriggers::TriggerRegistry.by_source("dsl")
        expect(dsl_triggers.count).to eq(3)

        generated_triggers = PgTriggers::TriggerRegistry.by_source("generated")
        expect(generated_triggers.count).to eq(1)
        expect(generated_triggers.first.trigger_name).to eq("generated_trigger")
      end
    end
  end

  describe "#drift_state" do
    let(:registry) do
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "delegates to Drift.detect" do
      expect(PgTriggers::Drift).to receive(:detect).with("test_trigger")
      registry.drift_state
    end
  end

  describe "#enable!" do
    let(:registry) do
      PgTriggers::TriggerRegistry.create!(
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
        rescue => e
          # Trigger might already exist
        end
      end

      after do
        begin
          ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON users")
          ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
        rescue
        end
      end

      it "enables the trigger in database" do
        registry.enable!
        expect(registry.enabled).to eq(true)
        expect(registry.reload.enabled).to eq(true)
      end
    end

    context "when trigger doesn't exist in database" do
      it "updates registry even if trigger doesn't exist" do
        expect { registry.enable! }.not_to raise_error
        expect(registry.reload.enabled).to eq(true)
      end
    end
  end

  describe "#disable!" do
    let(:registry) do
      PgTriggers::TriggerRegistry.create!(
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
        rescue => e
          # Trigger might already exist
        end
      end

      after do
        begin
          ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON users")
          ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
        rescue
        end
      end

      it "disables the trigger in database" do
        registry.disable!
        expect(registry.enabled).to eq(false)
        expect(registry.reload.enabled).to eq(false)
      end
    end

    context "when trigger doesn't exist in database" do
      it "updates registry even if trigger doesn't exist" do
        expect { registry.disable! }.not_to raise_error
        expect(registry.reload.enabled).to eq(false)
      end
    end
  end
end

