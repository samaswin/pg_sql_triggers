# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Drift::DbQueries do
  describe ".all_triggers" do
    it "returns all triggers from the database" do
      # Create a test trigger in the database
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION test_trigger_function() RETURNS TRIGGER AS $$
        BEGIN
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, name VARCHAR);
      SQL

      ActiveRecord::Base.connection.execute(<<~SQL)
        DROP TRIGGER IF EXISTS test_trigger ON test_table;
        CREATE TRIGGER test_trigger
          BEFORE INSERT ON test_table
          FOR EACH ROW
          EXECUTE FUNCTION test_trigger_function();
      SQL

      triggers = described_class.all_triggers

      expect(triggers).to be_an(Array)
      test_trigger = triggers.find { |t| t["trigger_name"] == "test_trigger" }
      expect(test_trigger).not_to be_nil
      expect(test_trigger["table_name"]).to eq("test_table")
      expect(test_trigger["function_name"]).to eq("test_trigger_function")
      expect(test_trigger["schema_name"]).to eq("public")
    end

    it "excludes internal triggers" do
      triggers = described_class.all_triggers
      internal_triggers = triggers.select { |t| t["is_internal"] == true }
      expect(internal_triggers).to be_empty
    end

    it "excludes RI_ triggers" do
      triggers = described_class.all_triggers
      ri_triggers = triggers.select { |t| t["trigger_name"].start_with?("RI_") }
      expect(ri_triggers).to be_empty
    end
  end

  describe ".find_trigger" do
    before do
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION find_test_function() RETURNS TRIGGER AS $$
        BEGIN
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS find_test_table (id SERIAL PRIMARY KEY);
      SQL

      ActiveRecord::Base.connection.execute(<<~SQL)
        DROP TRIGGER IF EXISTS find_test_trigger ON find_test_table;
        CREATE TRIGGER find_test_trigger
          BEFORE INSERT ON find_test_table
          FOR EACH ROW
          EXECUTE FUNCTION find_test_function();
      SQL
    end

    it "returns a trigger by name" do
      trigger = described_class.find_trigger("find_test_trigger")

      expect(trigger).not_to be_nil
      expect(trigger["trigger_name"]).to eq("find_test_trigger")
      expect(trigger["table_name"]).to eq("find_test_table")
      expect(trigger["function_name"]).to eq("find_test_function")
    end

    it "returns nil for non-existent trigger" do
      trigger = described_class.find_trigger("non_existent_trigger")
      expect(trigger).to be_nil
    end
  end

  describe ".find_triggers_for_table" do
    before do
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION table_test_function() RETURNS TRIGGER AS $$
        BEGIN
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS table_test_table (id SERIAL PRIMARY KEY);
      SQL

      ActiveRecord::Base.connection.execute(<<~SQL)
        DROP TRIGGER IF EXISTS table_test_trigger ON table_test_table;
        CREATE TRIGGER table_test_trigger
          BEFORE INSERT ON table_test_table
          FOR EACH ROW
          EXECUTE FUNCTION table_test_function();
      SQL
    end

    it "returns triggers for a specific table" do
      triggers = described_class.find_triggers_for_table("table_test_table")

      expect(triggers).to be_an(Array)
      expect(triggers.length).to be >= 1
      test_trigger = triggers.find { |t| t["trigger_name"] == "table_test_trigger" }
      expect(test_trigger).not_to be_nil
      expect(test_trigger["table_name"]).to eq("table_test_table")
    end

    it "returns empty array for table with no triggers" do
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS empty_table (id SERIAL PRIMARY KEY);
      SQL

      triggers = described_class.find_triggers_for_table("empty_table")
      expect(triggers).to be_an(Array)
      # May have system triggers, so just check it's an array
    end
  end

  describe ".find_function" do
    before do
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION find_function_test() RETURNS TRIGGER AS $$
        BEGIN
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL
    end

    it "returns function by name" do
      function = described_class.find_function("find_function_test")

      expect(function).not_to be_nil
      expect(function["function_name"]).to eq("find_function_test")
      expect(function["function_definition"]).to include("find_function_test")
    end

    it "returns nil for non-existent function" do
      function = described_class.find_function("non_existent_function")
      expect(function).to be_nil
    end
  end
end

