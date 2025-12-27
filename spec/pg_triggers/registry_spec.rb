# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers::Registry do
  describe ".register" do
    let(:definition) do
      definition = PgTriggers::DSL::TriggerDefinition.new("test_trigger")
      definition.table(:users)
      definition.on(:insert)
      definition.function(:test_function)
      definition.version(1)
      definition.enabled(false)
      definition
    end

    it "delegates to Manager.register" do
      expect(PgTriggers::Registry::Manager).to receive(:register).with(definition)
      PgTriggers::Registry.register(definition)
    end
  end

  describe ".list" do
    it "delegates to Manager.list" do
      expect(PgTriggers::Registry::Manager).to receive(:list)
      PgTriggers::Registry.list
    end
  end

  describe ".enabled" do
    it "delegates to Manager.enabled" do
      expect(PgTriggers::Registry::Manager).to receive(:enabled)
      PgTriggers::Registry.enabled
    end
  end

  describe ".disabled" do
    it "delegates to Manager.disabled" do
      expect(PgTriggers::Registry::Manager).to receive(:disabled)
      PgTriggers::Registry.disabled
    end
  end

  describe ".for_table" do
    it "delegates to Manager.for_table" do
      expect(PgTriggers::Registry::Manager).to receive(:for_table).with("users")
      PgTriggers::Registry.for_table("users")
    end
  end

  describe ".diff" do
    it "delegates to Manager.diff" do
      expect(PgTriggers::Registry::Manager).to receive(:diff)
      PgTriggers::Registry.diff
    end
  end

  describe ".validate!" do
    it "delegates to Validator.validate!" do
      expect(PgTriggers::Registry::Validator).to receive(:validate!).and_return(true)
      result = PgTriggers::Registry.validate!
      expect(result).to be true
    end
  end
end

RSpec.describe PgTriggers::Registry::Manager do
  describe ".register" do
    let(:definition) do
      definition = PgTriggers::DSL::TriggerDefinition.new("test_trigger")
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
        registry = PgTriggers::Registry::Manager.register(definition)
        expect(registry).to be_persisted
        expect(registry.trigger_name).to eq("test_trigger")
        expect(registry.table_name).to eq("users")
        expect(registry.version).to eq(1)
        expect(registry.enabled).to eq(false)
        expect(registry.source).to eq("dsl")
        expect(registry.environment).to eq("production")
      end

      it "stores definition as JSON" do
        registry = PgTriggers::Registry::Manager.register(definition)
        expect(registry.definition).to be_present
        parsed = JSON.parse(registry.definition)
        expect(parsed["name"]).to eq("test_trigger")
      end

      it "sets a placeholder checksum" do
        registry = PgTriggers::Registry::Manager.register(definition)
        expect(registry.checksum).to eq("placeholder")
      end
    end

    context "when trigger already exists" do
      before do
        PgTriggers::TriggerRegistry.create!(
          trigger_name: "test_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "old",
          source: "generated"
        )
      end

      it "updates the existing registry entry" do
        registry = PgTriggers::Registry::Manager.register(definition)
        expect(registry.enabled).to eq(false)
        expect(registry.source).to eq("dsl")
      end
    end
  end

  describe ".list" do
    before do
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "trigger1",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "trigger2",
        table_name: "posts",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "generated"
      )
    end

    it "returns all triggers" do
      result = PgTriggers::Registry::Manager.list
      expect(result.count).to eq(2)
      expect(result.map(&:trigger_name)).to contain_exactly("trigger1", "trigger2")
    end
  end

  describe ".enabled" do
    before do
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "enabled_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "disabled_trigger",
        table_name: "posts",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "dsl"
      )
    end

    it "returns only enabled triggers" do
      result = PgTriggers::Registry::Manager.enabled
      expect(result.count).to eq(1)
      expect(result.first.trigger_name).to eq("enabled_trigger")
    end
  end

  describe ".disabled" do
    before do
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "enabled_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "disabled_trigger",
        table_name: "posts",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "dsl"
      )
    end

    it "returns only disabled triggers" do
      result = PgTriggers::Registry::Manager.disabled
      expect(result.count).to eq(1)
      expect(result.first.trigger_name).to eq("disabled_trigger")
    end
  end

  describe ".for_table" do
    before do
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "trigger1",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "trigger2",
        table_name: "users",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "dsl"
      )
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "trigger3",
        table_name: "posts",
        version: 1,
        enabled: true,
        checksum: "ghi",
        source: "dsl"
      )
    end

    it "returns triggers for the specified table" do
      result = PgTriggers::Registry::Manager.for_table("users")
      expect(result.count).to eq(2)
      expect(result.map(&:trigger_name)).to contain_exactly("trigger1", "trigger2")
    end
  end

  describe ".diff" do
    it "delegates to Drift.detect" do
      expect(PgTriggers::Drift).to receive(:detect)
      PgTriggers::Registry::Manager.diff
    end
  end
end

