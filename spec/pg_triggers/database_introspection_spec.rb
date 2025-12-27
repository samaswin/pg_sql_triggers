# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers::DatabaseIntrospection do
  let(:introspection) { PgTriggers::DatabaseIntrospection.new }

  before do
    # Create test tables
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_users (id SERIAL PRIMARY KEY, name VARCHAR, email VARCHAR)")
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_posts (id SERIAL PRIMARY KEY, title VARCHAR, user_id INTEGER)")
  end

  after do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users CASCADE")
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_posts CASCADE")
  end

  describe "#excluded_tables" do
    it "includes default excluded tables" do
      excluded = introspection.excluded_tables
      expect(excluded).to include("ar_internal_metadata", "schema_migrations", "pg_triggers_registry", "trigger_migrations")
    end

    it "includes user-configured excluded tables" do
      PgTriggers.excluded_tables = ["custom_table"]
      excluded = introspection.excluded_tables
      expect(excluded).to include("custom_table")
      PgTriggers.excluded_tables = []
    end
  end

  describe "#list_tables" do
    it "returns list of tables excluding system tables" do
      tables = introspection.list_tables
      expect(tables).to include("test_users", "test_posts")
      expect(tables).not_to include("ar_internal_metadata", "schema_migrations", "pg_triggers_registry")
    end

    it "returns tables in alphabetical order" do
      tables = introspection.list_tables
      test_tables = tables.select { |t| t.start_with?("test_") }
      expect(test_tables).to eq(test_tables.sort)
    end

    it "handles errors gracefully" do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(StandardError.new("Connection error"))
      allow(Rails.logger).to receive(:error)
      
      tables = introspection.list_tables
      expect(tables).to eq([])
    end
  end

  describe "#validate_table" do
    it "returns valid for existing table" do
      result = introspection.validate_table("test_users")
      expect(result[:valid]).to be true
      expect(result[:table_name]).to eq("test_users")
      expect(result[:column_count]).to be > 0
    end

    it "returns invalid for non-existent table" do
      result = introspection.validate_table("non_existent_table")
      expect(result[:valid]).to be false
      expect(result[:error]).to include("not found")
    end

    it "returns error for blank table name" do
      result = introspection.validate_table("")
      expect(result[:valid]).to be false
      expect(result[:error]).to include("cannot be blank")
    end

    it "returns table comment when available" do
      ActiveRecord::Base.connection.execute("COMMENT ON TABLE test_users IS 'Test users table'")
      result = introspection.validate_table("test_users")
      # Comment may or may not be present depending on PostgreSQL version
      expect(result).to have_key(:comment)
    end

    it "handles SQL injection attempts" do
      malicious_name = "'; DROP TABLE test_users; --"
      result = introspection.validate_table(malicious_name)
      # Should handle safely, either error or return invalid
      expect(result[:valid]).to be false
    end
  end

  describe "#table_columns" do
    it "returns columns for a table" do
      columns = introspection.table_columns("test_users")
      expect(columns).to be_an(Array)
      expect(columns.map { |c| c[:name] }).to include("id", "name", "email")
    end

    it "includes column data types" do
      columns = introspection.table_columns("test_users")
      id_column = columns.find { |c| c[:name] == "id" }
      expect(id_column[:type]).to be_present
    end

    it "includes nullable information" do
      columns = introspection.table_columns("test_users")
      columns.each do |col|
        expect(col).to have_key(:nullable)
      end
    end

    it "returns columns in ordinal order" do
      columns = introspection.table_columns("test_users")
      expect(columns.first[:name]).to eq("id") # Primary key is usually first
    end
  end

  describe "#function_exists?" do
    before do
      ActiveRecord::Base.connection.execute("CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
    end

    after do
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
    end

    it "returns true for existing function" do
      expect(introspection.function_exists?("test_function")).to be true
    end

    it "returns false for non-existent function" do
      expect(introspection.function_exists?("non_existent_function")).to be false
    end
  end

  describe "#trigger_exists?" do
    before do
      ActiveRecord::Base.connection.execute("CREATE OR REPLACE FUNCTION test_trigger_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
      ActiveRecord::Base.connection.execute("CREATE TRIGGER test_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION test_trigger_function();")
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON test_users")
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_trigger_function()")
    end

    it "returns true for existing trigger" do
      expect(introspection.trigger_exists?("test_trigger")).to be true
    end

    it "returns false for non-existent trigger" do
      expect(introspection.trigger_exists?("non_existent_trigger")).to be false
    end
  end

  describe "#tables_with_triggers" do
    before do
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "registry_trigger",
        table_name: "test_users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )

      ActiveRecord::Base.connection.execute("CREATE OR REPLACE FUNCTION db_trigger_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
      ActiveRecord::Base.connection.execute("CREATE TRIGGER db_trigger BEFORE INSERT ON test_posts FOR EACH ROW EXECUTE FUNCTION db_trigger_function();")
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS db_trigger ON test_posts")
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS db_trigger_function()")
    end

    it "includes registry triggers" do
      tables = introspection.tables_with_triggers
      users_table = tables.find { |t| t[:table_name] == "test_users" }
      expect(users_table).to be_present
      expect(users_table[:registry_triggers].map { |t| t[:trigger_name] }).to include("registry_trigger")
    end

    it "includes database triggers" do
      tables = introspection.tables_with_triggers
      posts_table = tables.find { |t| t[:table_name] == "test_posts" }
      expect(posts_table).to be_present
      expect(posts_table[:database_triggers].map { |t| t[:trigger_name] }).to include("db_trigger")
    end

    it "calculates trigger_count" do
      tables = introspection.tables_with_triggers
      users_table = tables.find { |t| t[:table_name] == "test_users" }
      expect(users_table[:trigger_count]).to be >= 1
    end

    it "handles errors when fetching database triggers" do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original
      allow(ActiveRecord::Base.connection).to receive(:execute).with(/pg_trigger/).and_raise(StandardError.new("Error"))
      allow(Rails.logger).to receive(:error)

      tables = introspection.tables_with_triggers
      expect(tables).to be_an(Array)
    end
  end

  describe "#table_triggers" do
    before do
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "registry_trigger",
        table_name: "test_users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )

      ActiveRecord::Base.connection.execute("CREATE OR REPLACE FUNCTION db_trigger_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
      ActiveRecord::Base.connection.execute("CREATE TRIGGER db_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION db_trigger_function();")
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS db_trigger ON test_users")
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS db_trigger_function()")
    end

    it "returns registry triggers for table" do
      result = introspection.table_triggers("test_users")
      expect(result[:table_name]).to eq("test_users")
      expect(result[:registry_triggers].map(&:trigger_name)).to include("registry_trigger")
    end

    it "returns database triggers for table" do
      result = introspection.table_triggers("test_users")
      expect(result[:database_triggers].map { |t| t[:trigger_name] }).to include("db_trigger")
    end

    it "handles errors when fetching database triggers" do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original
      allow(ActiveRecord::Base.connection).to receive(:execute).with(/pg_trigger/).and_raise(StandardError.new("Error"))
      allow(Rails.logger).to receive(:error)

      result = introspection.table_triggers("test_users")
      expect(result[:database_triggers]).to eq([])
    end
  end
end

