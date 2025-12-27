# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe PgSqlTriggers::Generator::Service do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:rails_root) { Pathname.new(tmp_dir) }
  let(:form) do
    PgSqlTriggers::Generator::Form.new(
      trigger_name: "test_trigger",
      table_name: "users",
      function_name: "test_function",
      events: %w[insert update],
      version: 1,
      enabled: false,
      function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
      environments: ["production"]
    )
  end

  before do
    allow(Rails).to receive(:root).and_return(rails_root)
    FileUtils.mkdir_p(rails_root.join("app", "triggers"))
    FileUtils.mkdir_p(rails_root.join("db", "triggers"))
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe ".generate_dsl" do
    it "generates DSL trigger definition" do
      code = described_class.generate_dsl(form)
      expect(code).to include("PgSqlTriggers::DSL.pg_sql_trigger")
      expect(code).to include('"test_trigger"')
      expect(code).to include("table :users")
      expect(code).to include("on :insert, :update")
      expect(code).to include("function :test_function")
    end

    it "includes version and enabled status" do
      code = described_class.generate_dsl(form)
      expect(code).to include("version 1")
      expect(code).to include("enabled false")
    end

    it "includes when_env when environments are present" do
      code = described_class.generate_dsl(form)
      expect(code).to include("when_env :production")
    end

    it "includes when_condition when condition is present" do
      form.condition = "NEW.status = 'active'"
      code = described_class.generate_dsl(form)
      expect(code).to include('when_condition "NEW.status = \'active\'"')
    end

    it "does not include when_env when no environments" do
      form.environments = []
      code = described_class.generate_dsl(form)
      expect(code).not_to include("when_env")
    end
  end

  describe ".generate_migration" do
    it "generates migration class code with Add prefix" do
      code = described_class.generate_migration(form)
      expect(code).to include("class AddTestTrigger < PgSqlTriggers::Migration")
      expect(code).to include("def up")
      expect(code).to include("def down")
    end

    it "includes function body in up method" do
      code = described_class.generate_migration(form)
      expect(code).to include("CREATE OR REPLACE FUNCTION test_function()")
    end

    it "includes trigger creation SQL" do
      code = described_class.generate_migration(form)
      expect(code).to include("CREATE TRIGGER test_trigger")
      expect(code).to include("BEFORE INSERT OR UPDATE ON users")
      expect(code).to include("FOR EACH ROW")
      expect(code).to include("EXECUTE FUNCTION test_function()")
    end

    it "includes condition when present" do
      form.condition = "NEW.status = 'active'"
      code = described_class.generate_migration(form)
      expect(code).to include("WHEN (NEW.status = 'active')")
    end

    it "includes DROP statements in down method" do
      code = described_class.generate_migration(form)
      expect(code).to include("DROP TRIGGER IF EXISTS test_trigger ON users")
      expect(code).to include("DROP FUNCTION IF EXISTS test_function()")
    end
  end

  describe ".generate_function_stub" do
    it "returns nil when generate_function_stub is false" do
      form.generate_function_stub = false
      expect(described_class.generate_function_stub(form)).to be_nil
    end

    it "generates function stub when generate_function_stub is true" do
      form.generate_function_stub = true
      stub = described_class.generate_function_stub(form)
      expect(stub).to include("CREATE OR REPLACE FUNCTION test_function()")
      expect(stub).to include("RETURNS TRIGGER")
      expect(stub).to include("LANGUAGE plpgsql")
    end

    it "includes trigger metadata in comments" do
      form.generate_function_stub = true
      stub = described_class.generate_function_stub(form)
      expect(stub).to include("trigger: test_trigger")
      expect(stub).to include("Table: users")
    end
  end

  describe ".file_paths" do
    it "returns both migration and DSL file paths" do
      paths = described_class.file_paths(form)
      expect(paths[:migration]).to match(%r{db/triggers/\d+_test_trigger\.rb})
      expect(paths[:dsl]).to eq("app/triggers/test_trigger.rb")
    end

    it "uses trigger name for both files" do
      form.trigger_name = "my_trigger"
      paths = described_class.file_paths(form)
      expect(paths[:migration]).to match(%r{db/triggers/\d+_my_trigger\.rb})
      expect(paths[:dsl]).to eq("app/triggers/my_trigger.rb")
    end
  end

  describe ".create_trigger" do
    it "creates both migration and DSL files" do
      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:success]).to be true
      expect(File.exist?(rails_root.join(result[:migration_path]))).to be true
      expect(File.exist?(rails_root.join(result[:dsl_path]))).to be true
      expect(result[:migration_path]).to match(%r{db/triggers/\d+_test_trigger\.rb})
      expect(result[:dsl_path]).to eq("app/triggers/test_trigger.rb")
    end

    it "creates migration file with correct content" do
      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      migration_content = File.read(rails_root.join(result[:migration_path]))
      expect(migration_content).to include("class AddTestTrigger < PgSqlTriggers::Migration")
      expect(migration_content).to include("def up")
      expect(migration_content).to include("CREATE OR REPLACE FUNCTION test_function()")
      expect(migration_content).to include("CREATE TRIGGER test_trigger")
    end

    it "creates DSL file with correct content" do
      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      dsl_content = File.read(rails_root.join(result[:dsl_path]))
      expect(dsl_content).to include('PgSqlTriggers::DSL.pg_sql_trigger "test_trigger"')
      expect(dsl_content).to include("table :users")
      expect(dsl_content).to include("on :insert, :update")
      expect(dsl_content).to include("function :test_function")
    end

    it "registers trigger in TriggerRegistry" do
      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:success]).to be true
      registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "test_trigger")
      expect(registry).to be_present
      expect(registry.table_name).to eq("users")
      expect(registry.source).to eq("dsl")
      expect(registry.function_body).to include("CREATE OR REPLACE FUNCTION test_function()")
    end

    it "stores definition as JSON" do
      described_class.create_trigger(form, actor: { type: "User", id: 1 })

      registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "test_trigger")
      definition = JSON.parse(registry.definition)
      expect(definition["name"]).to eq("test_trigger")
      expect(definition["table_name"]).to eq("users")
      expect(definition["events"]).to eq(%w[insert update])
    end

    it "calculates checksum" do
      described_class.create_trigger(form, actor: { type: "User", id: 1 })

      registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "test_trigger")
      expect(registry.checksum).to be_present
      expect(registry.checksum).not_to eq("placeholder")
    end

    it "handles errors gracefully" do
      allow(File).to receive(:write).and_raise(StandardError.new("Permission denied"))

      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:success]).to be false
      expect(result[:error]).to include("Permission denied")
    end

    context "when condition column exists" do
      it "includes condition in registry" do
        form.condition = "NEW.status = 'active'"
        described_class.create_trigger(form, actor: { type: "User", id: 1 })

        registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "test_trigger")
        expect(registry.condition).to eq("NEW.status = 'active'")
      end
    end

    it "creates necessary directories" do
      FileUtils.rm_rf(rails_root.join("app", "triggers"))
      FileUtils.rm_rf(rails_root.join("db", "triggers"))

      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:success]).to be true
      expect(Dir.exist?(rails_root.join("app", "triggers"))).to be true
      expect(Dir.exist?(rails_root.join("db", "triggers"))).to be true
    end
  end

  describe ".calculate_checksum" do
    it "generates SHA256 checksum" do
      definition = { name: "test", version: 1 }
      checksum = described_class.send(:calculate_checksum, definition)

      expect(checksum).to be_a(String)
      expect(checksum.length).to eq(64) # SHA256 hex length
    end

    it "generates different checksums for different definitions" do
      def1 = { name: "test1", version: 1 }
      def2 = { name: "test2", version: 1 }

      checksum1 = described_class.send(:calculate_checksum, def1)
      checksum2 = described_class.send(:calculate_checksum, def2)

      expect(checksum1).not_to eq(checksum2)
    end
  end
end
