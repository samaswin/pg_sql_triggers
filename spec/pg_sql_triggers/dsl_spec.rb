# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::DSL do
  describe ".pg_sql_trigger" do
    it "creates a trigger definition and registers it" do
      definition = described_class.pg_sql_trigger "test_trigger" do
        table :users
        on :insert, :update
        function :test_function
        self.version = 1
        self.enabled = true
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
    it "sets default values" do # rubocop:disable RSpec/MultipleExpectations
      expect(definition.name).to eq("test_trigger")
      expect(definition.events).to eq([])
      expect(definition.version).to eq(1)
      expect(definition.enabled).to be(true)
      expect(definition.environments).to eq([])
      expect(definition.condition).to be_nil
      expect(definition.timing).to eq("before")
      expect(definition.for_each).to eq("row")
      expect(definition.columns).to be_nil
      expect(definition.constraint_trigger).to be(false)
      expect(definition.deferrable).to be_nil
      expect(definition.initially).to be_nil
      expect(definition.depends_on_names).to eq([])
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

    it "clears column list when replacing events" do
      definition.on_update_of(:email, :name)
      definition.on(:insert, :update)
      expect(definition.columns).to be_nil
    end
  end

  describe "#on_update_of" do
    it "sets update event and column names as strings" do
      definition.on_update_of(:email, "name")
      expect(definition.events).to eq(["update"])
      expect(definition.columns).to eq(%w[email name])
    end
  end

  describe "#function" do
    it "sets the function name" do
      definition.function(:my_function)
      expect(definition.function_name).to eq(:my_function)
    end
  end

  describe "#version=" do
    it "sets the version" do
      definition.version = 5
      expect(definition.version).to eq(5)
    end
  end

  describe "#enabled=" do
    it "sets enabled status to true" do
      definition.enabled = true
      expect(definition.enabled).to be(true)
    end

    it "sets enabled status to false" do
      definition.enabled = false
      expect(definition.enabled).to be(false)
    end
  end

  describe "#when_env" do
    it "sets environments as strings" do
      expect { definition.when_env(:production, :staging) }.to output(/DEPRECATION/).to_stderr
      expect(definition.environments).to eq(%w[production staging])
    end

    it "handles single environment" do
      expect { definition.when_env(:production) }.to output(/DEPRECATION/).to_stderr
      expect(definition.environments).to eq(["production"])
    end
  end

  describe "#when_condition" do
    it "sets the condition SQL" do
      definition.when_condition("NEW.status = 'active'")
      expect(definition.condition).to eq("NEW.status = 'active'")
    end
  end

  describe "#timing=" do
    it "sets the timing" do
      definition.timing = "before"
      expect(definition.timing).to eq("before")
    end

    it "converts timing to string" do
      definition.timing = :after
      expect(definition.timing).to eq("after")
    end
  end

  describe "#for_each_row" do
    it "sets for_each to row" do
      definition.for_each_statement # change away from default first
      definition.for_each_row
      expect(definition.for_each).to eq("row")
    end
  end

  describe "#for_each_statement" do
    it "sets for_each to statement" do
      definition.for_each_statement
      expect(definition.for_each).to eq("statement")
    end
  end

  describe "constraint deferral" do
    it "records constraint_trigger and deferral options in to_h" do
      definition.constraint_trigger!
      definition.deferrable = :deferrable
      definition.initially = :deferred

      expect(definition.to_h).to include(
        constraint_trigger: true,
        deferrable: "deferrable",
        initially: "deferred"
      )
    end

    it "clears deferrable and initially when constraint_trigger is set to false" do
      definition.constraint_trigger!
      definition.deferrable = :not_deferrable
      definition.constraint_trigger = false

      expect(definition.deferrable).to be_nil
      expect(definition.initially).to be_nil
    end
  end

  describe "#depends_on" do
    it "records prerequisite trigger names in order" do
      definition.depends_on("validate_user_email", :normalize_user_name)
      expect(definition.depends_on_names).to eq(%w[validate_user_email normalize_user_name])
    end

    it "ignores blanks and deduplicates" do
      definition.depends_on("a", "", "a", nil)
      expect(definition.depends_on_names).to eq(["a"])
    end
  end

  describe "#to_h" do
    it "converts definition to hash" do
      definition.table(:users)
      definition.on(:insert)
      definition.function(:test_func)
      definition.version = 2
      definition.enabled = true
      expect { definition.when_env(:production) }.to output(/DEPRECATION/).to_stderr
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
                           condition: "NEW.id > 0",
                           timing: "before",
                           for_each: "row",
                           columns: nil,
                           constraint_trigger: false,
                           deferrable: nil,
                           initially: nil,
                           depends_on: []
                         })
    end

    it "includes columns when set via on_update_of" do
      definition.table(:users)
      definition.on_update_of(:status)
      definition.function(:audit_fn)

      expect(definition.to_h).to include(
        events: ["update"],
        columns: ["status"]
      )
    end
  end
end
