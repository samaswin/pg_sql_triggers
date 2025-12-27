# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Registry do
  describe ".register" do
    let(:definition) do
      definition = PgSqlTriggers::DSL::TriggerDefinition.new("test_trigger")
      definition.table(:users)
      definition.on(:insert)
      definition.function(:test_function)
      definition.version(1)
      definition.enabled(false)
      definition
    end

    it "delegates to Manager.register" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:register).with(definition)
      described_class.register(definition)
    end
  end

  describe ".list" do
    it "delegates to Manager.list" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:list)
      described_class.list
    end
  end

  describe ".enabled" do
    it "delegates to Manager.enabled" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:enabled)
      described_class.enabled
    end
  end

  describe ".disabled" do
    it "delegates to Manager.disabled" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:disabled)
      described_class.disabled
    end
  end

  describe ".for_table" do
    it "delegates to Manager.for_table" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:for_table).with("users")
      described_class.for_table("users")
    end
  end

  describe ".diff" do
    it "delegates to Manager.diff" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:diff)
      described_class.diff
    end
  end

  describe ".validate!" do
    it "delegates to Validator.validate!" do
      allow(PgSqlTriggers::Registry::Validator).to receive(:validate!).and_return(true)
      result = described_class.validate!
      expect(PgSqlTriggers::Registry::Validator).to have_received(:validate!)
      expect(result).to be true
    end
  end
end

RSpec.describe PgSqlTriggers::Registry::Manager do
  describe ".register" do
    let(:definition) do
      definition = PgSqlTriggers::DSL::TriggerDefinition.new("test_trigger")
      definition.table(:users)
      definition.on(:insert)
      definition.function(:test_function)
      definition.version(1)
      definition.enabled(false)
      definition.when_env(:production)
      definition
    end

    context "when trigger doesn't exist" do
      it "creates a new registry entry" do
        registry = described_class.register(definition)
        expect(registry).to be_persisted
        expect(registry.trigger_name).to eq("test_trigger")
        expect(registry.table_name).to eq("users")
        expect(registry.version).to eq(1)
        expect(registry.enabled).to be(false)
        expect(registry.source).to eq("dsl")
        expect(registry.environment).to eq("production")
      end

      it "stores definition as JSON" do
        registry = described_class.register(definition)
        expect(registry.definition).to be_present
        parsed = JSON.parse(registry.definition)
        expect(parsed["name"]).to eq("test_trigger")
      end

      it "sets a placeholder checksum" do
        registry = described_class.register(definition)
        expect(registry.checksum).to eq("placeholder")
      end
    end

    context "when trigger already exists" do
      before do
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: "test_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "old",
          source: "generated"
        )
      end

      it "updates the existing registry entry" do
        registry = described_class.register(definition)
        expect(registry.enabled).to be(false)
        expect(registry.source).to eq("dsl")
      end
    end
  end

  describe ".list" do
    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger1",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger2",
        table_name: "posts",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "generated"
      )
    end

    it "returns all triggers" do
      result = described_class.list
      expect(result.count).to eq(2)
      expect(result.map(&:trigger_name)).to contain_exactly("trigger1", "trigger2")
    end
  end

  describe ".enabled" do
    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "enabled_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "disabled_trigger",
        table_name: "posts",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "dsl"
      )
    end

    it "returns only enabled triggers" do
      result = described_class.enabled
      expect(result.count).to eq(1)
      expect(result.first.trigger_name).to eq("enabled_trigger")
    end
  end

  describe ".disabled" do
    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "enabled_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "disabled_trigger",
        table_name: "posts",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "dsl"
      )
    end

    it "returns only disabled triggers" do
      result = described_class.disabled
      expect(result.count).to eq(1)
      expect(result.first.trigger_name).to eq("disabled_trigger")
    end
  end

  describe ".for_table" do
    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger1",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger2",
        table_name: "users",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger3",
        table_name: "posts",
        version: 1,
        enabled: true,
        checksum: "ghi",
        source: "dsl"
      )
    end

    it "returns triggers for the specified table" do
      result = described_class.for_table("users")
      expect(result.count).to eq(2)
      expect(result.map(&:trigger_name)).to contain_exactly("trigger1", "trigger2")
    end
  end

  describe ".diff" do
    it "delegates to Drift.detect" do
      expect(PgSqlTriggers::Drift).to receive(:detect)
      described_class.diff
    end
  end
end
