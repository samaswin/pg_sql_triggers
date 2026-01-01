# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Testing::SyntaxValidator do
  let(:registry) do
    PgSqlTriggers::TriggerRegistry.create!(
      trigger_name: "test_trigger",
      table_name: "test_users",
      version: 1,
      enabled: false,
      checksum: "abc",
      source: "dsl",
      definition: {
        name: "test_trigger",
        table_name: "test_users",
        function_name: "test_function",
        events: ["insert"],
        version: 1
      }.to_json,
      function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
    )
  end

  let(:validator) { described_class.new(registry) }

  before do
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_users (id SERIAL PRIMARY KEY, name VARCHAR, status VARCHAR)")
  end

  after do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users CASCADE")
  end

  describe "#validate_dsl" do
    it "returns valid for complete DSL" do
      result = validator.validate_dsl
      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end

    it "detects missing trigger name" do
      registry.definition = { name: nil }.to_json
      result = validator.validate_dsl
      expect(result[:valid]).to be false
      expect(result[:errors]).to include("Missing trigger name")
    end

    it "detects missing table name" do
      registry.definition = { name: "test", table_name: nil }.to_json
      result = validator.validate_dsl
      expect(result[:valid]).to be false
      expect(result[:errors]).to include("Missing table name")
    end

    it "detects missing function name" do
      registry.definition = { name: "test", table_name: "users", function_name: nil }.to_json
      result = validator.validate_dsl
      expect(result[:valid]).to be false
      expect(result[:errors]).to include("Missing function name")
    end

    it "detects missing events" do
      registry.definition = { name: "test", table_name: "users", function_name: "func", events: [] }.to_json
      result = validator.validate_dsl
      expect(result[:valid]).to be false
      expect(result[:errors]).to include("Missing events")
    end

    it "detects invalid version" do
      registry.definition = { name: "test", table_name: "users", function_name: "func", events: ["insert"], version: 0 }.to_json
      result = validator.validate_dsl
      expect(result[:valid]).to be false
      expect(result[:errors]).to include("Invalid version")
    end

    it "returns error when definition is blank" do
      registry.definition = nil
      result = validator.validate_dsl
      expect(result[:valid]).to be false
      expect(result[:errors]).to include("Missing definition")
      expect(result[:definition]).to eq({})
    end

    it "handles invalid JSON gracefully" do
      registry.definition = "invalid json {"
      result = validator.validate_dsl
      expect(result[:valid]).to be false
      expect(result[:definition]).to eq({})
    end
  end

  describe "#validate_function_syntax" do
    it "returns valid for correct function syntax" do
      result = validator.validate_function_syntax
      expect(result[:valid]).to be true
      expect(result[:message]).to include("valid")
    end

    it "returns invalid for syntax errors" do
      registry.function_body = "CREATE FUNCTION invalid_syntax AS $$ BEGIN"
      result = validator.validate_function_syntax
      expect(result[:valid]).to be false
      expect(result[:error]).to be_present
    end

    it "handles missing function body" do
      registry.function_body = nil
      result = validator.validate_function_syntax
      expect(result[:valid]).to be false
      expect(result[:error]).to include("No function body defined")
    end

    it "rolls back transaction after validation" do
      validator.validate_function_syntax
      # Function should not exist in database
      result = ActiveRecord::Base.connection.execute("SELECT proname FROM pg_proc WHERE proname = 'test_function'")
      expect(result.count).to eq(0)
    end
  end

  describe "#validate_condition" do
    it "returns valid when condition is blank" do
      registry.condition = nil
      result = validator.validate_condition
      expect(result[:valid]).to be true
    end

    it "validates correct condition syntax" do
      registry.condition = "NEW.id > 0"
      result = validator.validate_condition
      expect(result[:valid]).to be true
    end

    it "detects invalid condition syntax" do
      registry.condition = "INVALID SQL SYNTAX !!!"
      result = validator.validate_condition
      expect(result[:valid]).to be false
      expect(result[:error]).to be_present
    end

    it "rolls back transaction after validation" do
      validator.validate_condition
      # No changes should be persisted - verify connection is still active by executing a query
      expect(ActiveRecord::Base.connection.execute("SELECT 1")).to be_present
    end

    it "returns error when table_name is blank" do
      registry.table_name = nil
      registry.condition = "NEW.id > 0"
      result = validator.validate_condition
      expect(result[:valid]).to be false
      expect(result[:error]).to include("Table name is required")
    end

    it "returns error when definition is blank" do
      registry.definition = nil
      registry.condition = "NEW.id > 0"
      result = validator.validate_condition
      expect(result[:valid]).to be false
      expect(result[:error]).to include("Function name is required")
    end

    it "detects invalid condition with OLD values for INSERT trigger" do
      registry.definition = {
        name: "test_trigger",
        table_name: "test_users",
        function_name: "test_function",
        events: ["insert"],
        version: 1
      }.to_json
      registry.condition = "OLD.status != NEW.status"
      result = validator.validate_condition
      expect(result[:valid]).to be false
      expect(result[:error]).to include("cannot reference OLD values for INSERT")
    end

    it "validates condition with OLD values for UPDATE trigger" do
      registry.definition = {
        name: "test_trigger",
        table_name: "test_users",
        function_name: "test_function",
        events: ["update"],
        version: 1
      }.to_json
      registry.condition = "OLD.status != NEW.status"
      result = validator.validate_condition
      expect(result[:valid]).to be true
    end

    it "validates condition with OLD values for DELETE trigger" do
      registry.definition = {
        name: "test_trigger",
        table_name: "test_users",
        function_name: "test_function",
        events: ["delete"],
        version: 1
      }.to_json
      registry.condition = "OLD.id > 0"
      result = validator.validate_condition
      expect(result[:valid]).to be true
    end

    it "uses default function name when not in definition" do
      registry.definition = {
        name: "test_trigger",
        table_name: "test_users",
        events: ["insert"],
        version: 1
      }.to_json
      registry.condition = "NEW.id > 0"
      result = validator.validate_condition
      expect(result[:valid]).to be true
    end

    it "handles invalid JSON in definition" do
      registry.definition = "invalid json"
      registry.condition = "NEW.id > 0"
      result = validator.validate_condition
      expect(result[:valid]).to be true # Should use defaults
    end
  end

  describe "#validate_all" do
    it "returns overall valid when all validations pass" do
      result = validator.validate_all
      expect(result[:overall_valid]).to be true
      expect(result[:dsl][:valid]).to be true
      expect(result[:function][:valid]).to be true
      expect(result[:condition][:valid]).to be true
    end

    it "returns overall invalid when any validation fails" do
      registry.function_body = "INVALID"
      result = validator.validate_all
      expect(result[:overall_valid]).to be false
      expect(result[:function][:valid]).to be false
    end
  end
end

RSpec.describe PgSqlTriggers::Testing::DryRun do
  let(:registry) do
    PgSqlTriggers::TriggerRegistry.create!(
      trigger_name: "test_trigger",
      table_name: "test_users",
      version: 1,
      enabled: false,
      checksum: "abc",
      source: "dsl",
      definition: {
        name: "test_trigger",
        table_name: "test_users",
        function_name: "test_function",
        events: %w[insert update],
        version: 1
      }.to_json,
      function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
      condition: "NEW.status = 'active'"
    )
  end

  let(:dry_run) { described_class.new(registry) }

  describe "#generate_sql" do
    it "generates function creation SQL" do
      result = dry_run.generate_sql
      function_sql = result[:sql_parts].find { |p| p[:type] == "CREATE FUNCTION" }
      expect(function_sql).to be_present
      expect(function_sql[:sql]).to include("CREATE OR REPLACE FUNCTION test_function()")
    end

    it "generates trigger creation SQL" do
      result = dry_run.generate_sql
      trigger_sql = result[:sql_parts].find { |p| p[:type] == "CREATE TRIGGER" }
      expect(trigger_sql).to be_present
      expect(trigger_sql[:sql]).to include("CREATE TRIGGER test_trigger")
      expect(trigger_sql[:sql]).to include("BEFORE INSERT OR UPDATE ON test_users")
      expect(trigger_sql[:sql]).to include("FOR EACH ROW")
      expect(trigger_sql[:sql]).to include("EXECUTE FUNCTION test_function()")
    end

    it "includes condition in trigger SQL when present" do
      result = dry_run.generate_sql
      trigger_sql = result[:sql_parts].find { |p| p[:type] == "CREATE TRIGGER" }
      expect(trigger_sql[:sql]).to include("WHEN (NEW.status = 'active')")
    end

    it "includes impact estimation" do
      result = dry_run.generate_sql
      expect(result[:estimated_impact]).to be_present
      expect(result[:estimated_impact][:tables_affected]).to include("test_users")
      expect(result[:estimated_impact][:functions_created]).to include("test_function")
      expect(result[:estimated_impact][:triggers_created]).to include("test_trigger")
    end
  end

  describe "#explain" do
    it "returns SQL preview" do
      result = dry_run.explain
      expect(result[:success]).to be true
      expect(result[:sql]).to be_present
      expect(result[:note]).to include("preview only")
    end
  end
end

RSpec.describe PgSqlTriggers::Testing::SafeExecutor do
  let(:registry) do
    PgSqlTriggers::TriggerRegistry.create!(
      trigger_name: "test_trigger",
      table_name: "test_users",
      version: 1,
      enabled: false,
      checksum: "abc",
      source: "dsl",
      definition: {
        name: "test_trigger",
        table_name: "test_users",
        function_name: "test_function",
        events: ["insert"],
        version: 1
      }.to_json,
      function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
    )
  end

  let(:executor) { described_class.new(registry) }

  before do
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_users (id SERIAL PRIMARY KEY, name VARCHAR, status VARCHAR)")
  end

  after do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users CASCADE")
  end

  describe "#test_execute" do
    it "creates function and trigger in transaction" do
      result = executor.test_execute
      expect(result[:function_created]).to be true
      expect(result[:trigger_created]).to be true
      expect(result[:success]).to be true
    end

    it "rolls back all changes" do
      executor.test_execute
      # Verify nothing was persisted
      result = ActiveRecord::Base.connection.execute("SELECT proname FROM pg_proc WHERE proname = 'test_function'")
      expect(result.count).to eq(0)
    end

    it "executes test insert when test_data provided" do
      test_data = { name: "Test User" }
      result = executor.test_execute(test_data: test_data)
      expect(result[:test_insert_executed]).to be true
    end

    it "handles errors gracefully" do
      registry.function_body = "INVALID SQL"
      result = executor.test_execute
      expect(result[:success]).to be false
      expect(result[:errors]).not_to be_empty
    end

    it "includes output messages" do
      result = executor.test_execute
      expect(result[:output]).to be_an(Array)
      expect(result[:output].join).to include("rolled back")
    end
  end
end

RSpec.describe PgSqlTriggers::Testing::FunctionTester do
  # Use unique trigger name to avoid conflicts with other tests
  let(:trigger_name) { "test_trigger_function_tester_#{SecureRandom.hex(4)}" }
  
  let(:registry) do
    PgSqlTriggers::TriggerRegistry.create!(
      trigger_name: trigger_name,
      table_name: "test_users",
      version: 1,
      enabled: false,
      checksum: "abc",
      source: "dsl",
      definition: {
        name: trigger_name,
        table_name: "test_users",
        function_name: "test_function",
        events: ["insert"],
        version: 1
      }.to_json,
      function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
    )
  end

  let(:tester) { described_class.new(registry) }

  describe "#test_function_only" do
    it "creates function in transaction" do
      result = tester.test_function_only
      expect(result[:function_created]).to be true
      expect(result[:success]).to be true
    end

    it "rolls back function creation" do
      tester.test_function_only
      result = ActiveRecord::Base.connection.execute("SELECT proname FROM pg_proc WHERE proname = 'test_function'")
      expect(result.count).to eq(0)
    end

    it "verifies function exists when test_context provided" do
      result = tester.test_function_only(test_context: {})
      expect(result[:function_executed]).to be true
    end

    it "handles errors gracefully" do
      registry.function_body = "INVALID SQL"
      result = tester.test_function_only
      expect(result[:success]).to be false
      expect(result[:errors]).not_to be_empty
    end
  end

  describe "#function_exists?" do
    it "returns false when function doesn't exist" do
      expect(tester.function_exists?).to be false
    end

    it "returns true when function exists" do
      ActiveRecord::Base.connection.execute(registry.function_body)
      expect(tester.function_exists?).to be true
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
    end

    it "returns false when definition is missing" do
      registry.definition = nil
      expect(tester.function_exists?).to be false
    end

    it "returns false when definition is invalid JSON" do
      registry.definition = "invalid json"
      expect(tester.function_exists?).to be false
    end

    it "returns false when function_name is missing from definition" do
      registry.definition = {}.to_json
      expect(tester.function_exists?).to be false
    end

    it "handles function_name as symbol in definition" do
      registry.definition = { function_name: "test_function" }.to_json
      ActiveRecord::Base.connection.execute(registry.function_body)
      expect(tester.function_exists?).to be true
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
    end

    it "handles name as function_name fallback" do
      registry.definition = { name: "test_function" }.to_json
      ActiveRecord::Base.connection.execute(registry.function_body)
      expect(tester.function_exists?).to be true
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
    end

    it "handles empty string function_name" do
      registry.definition = { function_name: "" }.to_json
      expect(tester.function_exists?).to be false
    end

    it "handles blank function_name with spaces" do
      registry.definition = { function_name: "   " }.to_json
      expect(tester.function_exists?).to be false
    end

    it "checks only function_name field first" do
      registry.definition = { function_name: "test_function", name: "other_name" }.to_json
      ActiveRecord::Base.connection.execute(registry.function_body)
      expect(tester.function_exists?).to be true
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
    end
  end

  describe "#test_function_only edge cases" do
    it "handles nil test_context" do
      result = tester.test_function_only(test_context: nil)
      expect(result[:function_created]).to be true
      expect(result[:function_executed]).to be true
    end

    it "extracts function name from function_body with CREATE OR REPLACE" do
      registry.function_body = "CREATE OR REPLACE FUNCTION my_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      result = tester.test_function_only(test_context: {})
      expect(result[:function_created]).to be true
    end

    it "extracts function name from function_body with CREATE" do
      registry.function_body = "CREATE FUNCTION my_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      result = tester.test_function_only(test_context: {})
      expect(result[:function_created]).to be true
    end

    it "handles function_body without function name match" do
      registry.function_body = "SELECT 1;"
      result = tester.test_function_only(test_context: {})
      expect(result[:function_created]).to be false
      expect(result[:success]).to be false
    end

    it "handles missing function_body" do
      registry.function_body = nil
      result = tester.test_function_only(test_context: {})
      expect(result[:function_created]).to be false
      expect(result[:success]).to be false
    end

    it "handles blank function_body" do
      registry.function_body = "   "
      result = tester.test_function_only(test_context: {})
      expect(result[:function_created]).to be false
      expect(result[:success]).to be false
      expect(result[:errors]).to include("Function body is missing")
    end

    it "handles errors during function creation gracefully" do
      registry.function_body = "INVALID SQL SYNTAX"
      result = tester.test_function_only
      expect(result[:success]).to be false
      expect(result[:errors]).not_to be_empty
    end

    it "handles errors during function verification gracefully" do
      # Ensure registry is created before setting up the mock
      registry # Force evaluation of let(:registry) before mock is set up
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(StandardError.new("DB error"))
      result = tester.test_function_only(test_context: {})
      expect(result[:success]).to be false
      expect(result[:errors]).not_to be_empty
    end

    it "handles function_body with blank function name" do
      registry.function_body = "CREATE FUNCTION () RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      registry.definition = {
        name: "test_trigger",
        table_name: "test_users",
        function_name: "fallback_function",
        events: ["insert"],
        version: 1
      }.to_json
      result = tester.test_function_only(test_context: {})
      expect(result[:function_created]).to be false
    end

    it "uses function name from definition when body extraction fails" do
      registry.function_body = "CREATE OR REPLACE FUNCTION valid_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      registry.definition = {
        name: "test_trigger",
        table_name: "test_users",
        function_name: "valid_func",
        events: ["insert"],
        version: 1
      }.to_json
      result = tester.test_function_only(test_context: {})
      expect(result[:function_created]).to be true
      expect(result[:function_executed]).to be true
    end

    it "handles when function count check fails" do
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql|
        if sql.include?("CREATE OR REPLACE FUNCTION")
          # Allow function creation
          nil
        elsif sql.include?("SELECT COUNT")
          # Simulate error during count check
          raise StandardError, "Query failed"
        end
      end

      result = tester.test_function_only(test_context: {})
      expect(result[:success]).to be false
      expect(result[:errors]).not_to be_empty
    end

    it "handles when function verification returns zero count" do
      # Mock successful function creation but function not found in pg_proc
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql|
        if sql.include?("SELECT COUNT")
          # Return zero count
          [{ "count" => "0" }]
        end
      end

      result = tester.test_function_only(test_context: {})
      # Function should still be created successfully, verification shows it exists or created
      expect(result[:function_created]).to be true
    end

    it "handles quote_string failure gracefully" do
      # Create a registry with a function that will be created successfully
      allow(ActiveRecord::Base.connection).to receive(:quote_string).and_raise(StandardError, "Quote failed")

      result = tester.test_function_only(test_context: {})
      # Should handle the error and continue
      expect(result).to have_key(:success)
    end

    it "handles when function_name cannot be extracted from body or definition" do
      registry.function_body = "CREATE OR REPLACE FUNCTION valid_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      registry.definition = { name: "test_trigger" }.to_json # No function_name in definition
      result = tester.test_function_only(test_context: {})
      expect(result[:function_created]).to be true
      expect(result[:function_executed]).to be true
      expect(result[:output].join).to include("Function created")
    end

    it "outputs correct message when function exists and is callable" do
      result = tester.test_function_only(test_context: {})
      expect(result[:output].join).to match(/Function (exists and is callable|created)/)
    end

    it "outputs message when function created but not verified" do
      # Make the function exist check return false (count = 0)
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql|
        if sql.include?("SELECT COUNT")
          # Simulate function not being found in pg_proc
          [{ "count" => "0" }]
        elsif sql.include?("BEGIN") || sql.include?("ROLLBACK")
          nil
        end
      end

      result = tester.test_function_only(test_context: {})
      expect(result[:function_created]).to be true
      expect(result[:output].join).to include("created")
    end
  end
end
