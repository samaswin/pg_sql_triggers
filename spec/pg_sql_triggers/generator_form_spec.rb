# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Generator::Form do
  describe "validations" do
    it "requires trigger_name" do
      form = described_class.new
      expect(form).not_to be_valid
      expect(form.errors[:trigger_name]).to include("can't be blank")
    end

    it "validates trigger_name format" do
      form = described_class.new(trigger_name: "Invalid-Name!")
      expect(form).not_to be_valid
      expect(form.errors[:trigger_name]).to include("must contain only lowercase letters, numbers, and underscores")

      form.trigger_name = "valid_trigger_name"
      form.valid?
      expect(form.errors[:trigger_name]).to be_empty
    end

    it "requires table_name" do
      form = described_class.new(trigger_name: "test_trigger")
      expect(form).not_to be_valid
      expect(form.errors[:table_name]).to include("can't be blank")
    end

    it "requires function_name" do
      form = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users"
      )
      expect(form).not_to be_valid
      expect(form.errors[:function_name]).to include("can't be blank")
    end

    it "validates function_name format" do
      form = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        function_name: "Invalid-Function!"
      )
      expect(form).not_to be_valid
      expect(form.errors[:function_name]).to include("must contain only lowercase letters, numbers, and underscores")
    end

    it "requires version to be positive integer" do
      form = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        function_name: "test_function",
        version: 0
      )
      expect(form).not_to be_valid
      expect(form.errors[:version]).to include("must be greater than 0")

      form.version = -1
      expect(form).not_to be_valid

      form.version = 1
      form.valid?
      expect(form.errors[:version]).to be_empty
    end

    it "requires function_body" do
      form = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        function_name: "test_function"
      )
      expect(form).not_to be_valid
      expect(form.errors[:function_body]).to include("can't be blank")
    end

    it "requires at least one event" do
      form = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        function_name: "test_function",
        function_body: "CREATE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        events: []
      )
      expect(form).not_to be_valid
      expect(form.errors[:events]).to include("must include at least one event")
    end

    it "validates that function_body contains function_name" do
      form = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        function_name: "test_function",
        function_body: "CREATE FUNCTION other_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        events: ["insert"]
      )
      expect(form).not_to be_valid
      expect(form.errors[:function_body]).to be_present
    end

    it "allows function_name with schema prefix" do
      form = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        function_name: "test_function",
        function_body: "CREATE FUNCTION public.test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        events: ["insert"]
      )
      expect(form).to be_valid
    end
  end

  describe "initialization" do
    it "sets default version to 1" do
      form = described_class.new
      expect(form.version).to eq(1)
    end

    it "converts enabled to boolean" do
      form = described_class.new(enabled: "1")
      expect(form.enabled).to be true

      form = described_class.new(enabled: "0")
      expect(form.enabled).to be false

      form = described_class.new(enabled: 1)
      expect(form.enabled).to be true

      form = described_class.new(enabled: nil)
      expect(form.enabled).to be true
    end

    it "defaults enabled to true" do
      form = described_class.new
      expect(form.enabled).to be true
    end

    it "defaults generate_function_stub to true" do
      form = described_class.new
      expect(form.generate_function_stub).to be true
    end

    it "defaults events to empty array" do
      form = described_class.new
      expect(form.events).to eq([])
    end

    it "defaults environments to empty array" do
      form = described_class.new
      expect(form.environments).to eq([])
    end
  end

  describe "#default_function_body" do
    it "generates function body with function_name" do
      form = described_class.new(function_name: "my_function")
      body = form.default_function_body

      expect(body).to include("CREATE OR REPLACE FUNCTION my_function()")
      expect(body).to include("RETURNS TRIGGER")
      expect(body).to include("LANGUAGE plpgsql")
    end

    it "uses placeholder when function_name is blank" do
      form = described_class.new
      body = form.default_function_body
      expect(body).to include("function_name")
    end
  end

  describe "valid form" do
    let(:valid_form) do
      described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        function_name: "test_function",
        function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        events: %w[insert update],
        version: 1,
        enabled: false,
        environments: ["production"],
        condition: "NEW.status = 'active'"
      )
    end

    it "is valid with all required fields" do
      expect(valid_form).to be_valid
    end

    it "rejects blank events" do
      valid_form.events = ["insert", "", "  "]
      expect(valid_form).to be_valid
      expect(valid_form.events.compact_blank).to eq(["insert"])
    end

    it "rejects blank environments" do
      valid_form.environments = ["production", "", "  "]
      expect(valid_form).to be_valid
    end
  end
end
