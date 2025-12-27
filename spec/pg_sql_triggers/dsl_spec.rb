# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::DSL do
  describe ".pg_sql_trigger" do
    it "creates a trigger definition and registers it" do
      definition = described_class.pg_sql_trigger "test_trigger" do
        table :users
        on :insert, :update
        function :test_function
        version 1
        enabled true
      end

      expect(definition).to be_a(PgSqlTriggers::DSL::TriggerDefinition)
      expect(definition.name).to eq("test_trigger")
      expect(definition.table_name).to eq(:users)
      expect(definition.events).to eq(%w[insert update])
      expect(definition.function_name).to eq(:test_function)
      expect(definition.version).to eq(1)
      expect(definition.enabled).to be(true)
    end

    it "registers the trigger in the registry" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:register).and_call_original
      described_class.pg_sql_trigger "test_trigger" do
        table :users
        on :insert
        function :test_function
      end
    end
  end
end

RSpec.describe PgSqlTriggers::DSL::TriggerDefinition do
  let(:definition) { described_class.new("test_trigger") }

  describe "#initialize" do
    it "sets default values" do
      expect(definition.name).to eq("test_trigger")
      expect(definition.events).to eq([])
      expect(definition.version).to eq(1)
      expect(definition.enabled).to be(false)
      expect(definition.environments).to eq([])
      expect(definition.condition).to be_nil
    end
  end

  describe "#table" do
    it "sets the table name" do
      definition.table(:users)
      expect(definition.table_name).to eq(:users)
    end
  end

  describe "#on" do
    it "sets events as strings" do
      definition.on(:insert, :update, :delete)
      expect(definition.events).to eq(%w[insert update delete])
    end

    it "handles single event" do
      definition.on(:insert)
      expect(definition.events).to eq(["insert"])
    end
  end

  describe "#function" do
    it "sets the function name" do
      definition.function(:my_function)
      expect(definition.function_name).to eq(:my_function)
    end
  end

  describe "#version" do
    it "sets the version" do
      definition.version(5)
      expect(definition.version).to eq(5)
    end
  end

  describe "#enabled" do
    it "sets enabled status" do
      definition.enabled(true)
      expect(definition.enabled).to be(true)

      definition.enabled(false)
      expect(definition.enabled).to be(false)
    end
  end

  describe "#when_env" do
    it "sets environments as strings" do
      definition.when_env(:production, :staging)
      expect(definition.environments).to eq(%w[production staging])
    end

    it "handles single environment" do
      definition.when_env(:production)
      expect(definition.environments).to eq(["production"])
    end
  end

  describe "#when_condition" do
    it "sets the condition SQL" do
      definition.when_condition("NEW.status = 'active'")
      expect(definition.condition).to eq("NEW.status = 'active'")
    end
  end

  describe "#to_h" do
    it "converts definition to hash" do
      definition.table(:users)
      definition.on(:insert)
      definition.function(:test_func)
      definition.version(2)
      definition.enabled(true)
      definition.when_env(:production)
      definition.when_condition("NEW.id > 0")

      hash = definition.to_h
      expect(hash).to eq({
                           name: "test_trigger",
                           table_name: :users,
                           events: ["insert"],
                           function_name: :test_func,
                           version: 2,
                           enabled: true,
                           environments: ["production"],
                           condition: "NEW.id > 0"
                         })
    end
  end
end
