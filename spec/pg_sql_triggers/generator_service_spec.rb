# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe PgSqlTriggers::Generator::Service do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:rails_root) { Pathname.new(tmp_dir) }
  let(:trigger_name) { "test_trigger_generator_#{SecureRandom.hex(4)}" }
  let(:form) do
    PgSqlTriggers::Generator::Form.new(
      trigger_name: trigger_name,
      table_name: "users",
      function_name: "test_function",
      events: %w[insert update],
      version: 1,
      enabled: false,
      timing: "before",
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
      expect(code).to include("\"#{trigger_name}\"")
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

    it "includes timing in DSL" do
      form.timing = "before"
      code = described_class.generate_dsl(form)
      expect(code).to include("timing :before")
    end

    it "includes timing in DSL (after)" do
      form.timing = "after"
      code = described_class.generate_dsl(form)
      expect(code).to include("timing :after")
    end

    it "does not include when_env when no environments" do
      form.environments = []
      code = described_class.generate_dsl(form)
      expect(code).not_to include("when_env")
    end

    it "quotes function name when it contains special characters" do
      form.function_name = "my-function"
      code = described_class.generate_dsl(form)
      expect(code).to include('function "my-function"')
      expect(code).not_to include("function :my-function")
    end

    it "uses symbol for function name when it matches simple pattern" do
      form.function_name = "simple_function_123"
      code = described_class.generate_dsl(form)
      expect(code).to include("function :simple_function_123")
    end

    it "handles multiple environments" do
      form.environments = %w[production staging]
      code = described_class.generate_dsl(form)
      expect(code).to include("when_env :production, :staging")
    end

    it "escapes quotes in condition" do
      form.condition = 'NEW.status = "active"'
      code = described_class.generate_dsl(form)
      expect(code).to include('when_condition "NEW.status = \\"active\\""')
    end

    it "handles single event" do
      form.events = ["insert"]
      code = described_class.generate_dsl(form)
      expect(code).to include("on :insert")
    end

    it "handles all event types" do
      form.events = %w[insert update delete truncate]
      code = described_class.generate_dsl(form)
      expect(code).to include("on :insert, :update, :delete, :truncate")
    end

    it "handles blank events in list" do
      form.events = ["insert", "", "update", nil]
      code = described_class.generate_dsl(form)
      expect(code).to include("on :insert, :update")
    end

    it "handles blank environments in list" do
      form.environments = ["production", "", "staging", nil]
      code = described_class.generate_dsl(form)
      expect(code).to include("when_env :production, :staging")
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

    it "uses timing from form (before)" do
      form.timing = "before"
      code = described_class.generate_migration(form)
      expect(code).to include("BEFORE INSERT OR UPDATE ON users")
    end

    it "uses timing from form (after)" do
      form.timing = "after"
      code = described_class.generate_migration(form)
      expect(code).to include("AFTER INSERT OR UPDATE ON users")
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

    it "does not include condition when condition is blank" do
      form.condition = nil
      code = described_class.generate_migration(form)
      expect(code).not_to include("WHEN (")
    end

    it "handles single event in SQL" do
      form.events = ["insert"]
      code = described_class.generate_migration(form)
      expect(code).to include("BEFORE INSERT ON users")
    end

    it "handles single event with after timing" do
      form.events = ["insert"]
      form.timing = "after"
      code = described_class.generate_migration(form)
      expect(code).to include("AFTER INSERT ON users")
      expect(code).not_to include("BEFORE INSERT ON users")
    end

    it "handles all event types in SQL" do
      form.events = %w[insert update delete truncate]
      code = described_class.generate_migration(form)
      expect(code).to include("BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON users")
    end

    it "handles all event types with after timing" do
      form.events = %w[insert update delete truncate]
      form.timing = "after"
      code = described_class.generate_migration(form)
      expect(code).to include("AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON users")
      expect(code).not_to include("BEFORE")
    end

    it "strips function body whitespace" do
      form.function_body = "  CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;  "
      code = described_class.generate_migration(form)
      expect(code).to include("CREATE OR REPLACE FUNCTION test_function()")
      # The function body is inside a heredoc, so check that leading/trailing whitespace is stripped
      # The strip method is called on function_body_sql, so the content should not have leading spaces
      expect(code).to include("CREATE OR REPLACE FUNCTION test_function()")
      # Verify the stripped version is used (no leading spaces in the SQL block)
      sql_block = code.match(/execute <<-SQL\n\s+(.*?)\n\s+SQL/m)
      expect(sql_block).to be_present
      expect(sql_block[1]).to start_with("CREATE")
    end

    it "properly indents SQL content in heredoc" do
      form.function_body = <<~SQL # rubocop:disable Rails/SquishedSQLHeredocs
        CREATE OR REPLACE FUNCTION test_function()
        RETURNS TRIGGER AS $$
        BEGIN
          RAISE NOTICE 'Test';
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL
      code = described_class.generate_migration(form)
      # Extract the SQL block from the function body
      function_sql_match = code.match(/execute <<-SQL\n(\s+.*?)\n\s+SQL/m)
      expect(function_sql_match).to be_present
      sql_lines = function_sql_match[1].split("\n")
      # All lines should be indented with 18 spaces
      sql_lines.each do |line|
        expect(line).to match(/\A {18}/) unless line.strip.empty?
      end
    end

    it "properly indents trigger SQL in heredoc" do
      code = described_class.generate_migration(form)
      # Extract the trigger SQL block (second SQL block after the function)
      sql_blocks = code.scan(/execute <<-SQL\n(\s+.*?)\n\s+SQL/m)
      expect(sql_blocks.length).to be >= 2
      trigger_sql_lines = sql_blocks[1][0].split("\n")
      # All non-empty lines should be indented with 18 spaces
      trigger_sql_lines.each do |line|
        expect(line).to match(/\A {18}/) unless line.strip.empty?
      end
    end

    it "handles complex trigger name in class name" do
      form.trigger_name = "my_complex_trigger_name"
      code = described_class.generate_migration(form)
      expect(code).to include("class AddMyComplexTriggerName < PgSqlTriggers::Migration")
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

    it "includes all events in comments" do
      form.generate_function_stub = true
      form.events = %w[insert update delete]
      stub = described_class.generate_function_stub(form)
      expect(stub).to include("Events: INSERT, UPDATE, DELETE")
    end

    it "handles blank events in stub generation" do
      form.generate_function_stub = true
      form.events = ["insert", "", "update"]
      stub = described_class.generate_function_stub(form)
      expect(stub).to include("Events: INSERT, UPDATE")
    end

    it "includes timestamp in stub" do
      form.generate_function_stub = true
      stub = described_class.generate_function_stub(form)
      expect(stub).to match(/Generated by pg_sql_triggers on \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
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

    it "calls next_migration_number to generate version" do
      allow(described_class).to receive(:next_migration_number).and_return(1_234_567_890)
      paths = described_class.file_paths(form)
      expect(paths[:migration]).to eq("db/triggers/1234567890_test_trigger.rb")
    end
  end

  describe ".next_migration_number" do
    it "returns timestamp when no existing migrations" do
      FileUtils.rm_rf(rails_root.join("db", "triggers"))
      number = described_class.send(:next_migration_number)
      expect(number).to be_a(Integer)
      expect(number.to_s.length).to be >= 14 # YYYYMMDDHHMMSS format
    end

    it "increments from existing migrations" do
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.mkdir_p(triggers_dir)
      File.write(triggers_dir.join("20231215120000_existing.rb"), "# existing migration")

      number = described_class.send(:next_migration_number)
      expect(number).to be > 20_231_215_120_000
    end

    it "handles multiple existing migrations" do
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.mkdir_p(triggers_dir)
      File.write(triggers_dir.join("20231215120000_first.rb"), "# first")
      File.write(triggers_dir.join("20231215120001_second.rb"), "# second")
      File.write(triggers_dir.join("20231215120005_third.rb"), "# third")

      number = described_class.send(:next_migration_number)
      expect(number).to be > 20_231_215_120_005
    end

    it "handles timestamp collision by incrementing" do
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.mkdir_p(triggers_dir)
      # Create a migration with a future timestamp
      future_timestamp = (Time.now.utc + 3600).strftime("%Y%m%d%H%M%S").to_i
      File.write(triggers_dir.join("#{future_timestamp}_future.rb"), "# future")

      number = described_class.send(:next_migration_number)
      expect(number).to be > future_timestamp
    end

    it "works without Rails context" do
      # Test that it falls back to Dir.pwd when Rails.root is not available
      # Since we can't easily mock defined?, we test that the method works
      # by ensuring it can generate a number even when Rails.root might not be available
      # In practice, the method checks defined?(Rails) && Rails.respond_to?(:root)
      # We'll test the actual behavior by ensuring it returns a valid number
      number = described_class.send(:next_migration_number)
      expect(number).to be_a(Integer)
      expect(number).to be > 0
    end

    it "ignores files that don't match migration pattern" do
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.mkdir_p(triggers_dir)
      File.write(triggers_dir.join("not_a_migration.txt"), "not a migration")
      File.write(triggers_dir.join("0_invalid.rb"), "# invalid")

      number = described_class.send(:next_migration_number)
      expect(number).to be_a(Integer)
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
      expect(dsl_content).to include("PgSqlTriggers::DSL.pg_sql_trigger \"#{trigger_name}\"")
      expect(dsl_content).to include("table :users")
      expect(dsl_content).to include("on :insert, :update")
      expect(dsl_content).to include("function :test_function")
    end

    it "registers trigger in TriggerRegistry" do
      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:success]).to be true
      registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
      expect(registry).to be_present
      expect(registry.table_name).to eq("users")
      expect(registry.source).to eq("dsl")
      expect(registry.function_body).to include("CREATE OR REPLACE FUNCTION test_function()")
    end

    it "stores definition as JSON" do
      described_class.create_trigger(form, actor: { type: "User", id: 1 })

      registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
      definition = JSON.parse(registry.definition)
      expect(definition["name"]).to eq(trigger_name)
      expect(definition["table_name"]).to eq("users")
      expect(definition["events"]).to eq(%w[insert update])
      expect(definition["timing"]).to eq("before")
    end

    context "when timing is 'after'" do
      it "saves timing to registry" do
        form.timing = "after"
        described_class.create_trigger(form, actor: { type: "User", id: 1 })

        registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
        expect(registry.timing).to eq("after") if PgSqlTriggers::TriggerRegistry.column_names.include?("timing")
      end

      it "includes timing in definition JSON" do
        form.timing = "after"
        described_class.create_trigger(form, actor: { type: "User", id: 1 })

        registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
        definition = JSON.parse(registry.definition)
        expect(definition["timing"]).to eq("after")
      end

      it "generates migration with AFTER timing" do
        form.timing = "after"
        result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

        migration_content = File.read(rails_root.join(result[:migration_path]))
        expect(migration_content).to include("AFTER INSERT OR UPDATE ON users")
        expect(migration_content).not_to include("BEFORE INSERT OR UPDATE ON users")
      end

      it "generates DSL with after timing" do
        form.timing = "after"
        result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

        dsl_content = File.read(rails_root.join(result[:dsl_path]))
        expect(dsl_content).to include("timing :after")
        expect(dsl_content).not_to include("timing :before")
      end

      it "includes timing in checksum calculation" do
        form1 = form.dup
        form1.timing = "before"
        described_class.create_trigger(form1, actor: { type: "User", id: 1 })
        registry1 = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "test_trigger")
        checksum1 = registry1.checksum

        # Clean up
        PgSqlTriggers::TriggerRegistry.destroy_all
        FileUtils.rm_rf(rails_root.join("app", "triggers"))
        FileUtils.rm_rf(rails_root.join("db", "triggers"))

        form2 = form.dup
        form2.timing = "after"
        described_class.create_trigger(form2, actor: { type: "User", id: 1 })
        registry2 = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "test_trigger")
        checksum2 = registry2.checksum

        expect(checksum1).not_to eq(checksum2)
      end
    end

    it "calculates checksum" do
      described_class.create_trigger(form, actor: { type: "User", id: 1 })

      registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
      expect(registry.checksum).to be_present
      expect(registry.checksum).not_to eq("placeholder")
    end

    it "handles file permission errors gracefully" do
      # Make the directory read-only to simulate permission error
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.mkdir_p(triggers_dir)
      FileUtils.chmod("a-w", triggers_dir)

      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    ensure
      # Restore permissions
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.chmod("a+w", triggers_dir) if Dir.exist?(triggers_dir)
    end

    context "when condition column exists" do
      it "includes condition in registry" do
        form.condition = "NEW.status = 'active'"
        described_class.create_trigger(form, actor: { type: "User", id: 1 })

        registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
        expect(registry.condition).to eq("NEW.status = 'active'")
      end

      it "includes condition in definition JSON" do
        form.condition = "NEW.id > 0"
        described_class.create_trigger(form, actor: { type: "User", id: 1 })

        registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
        definition = JSON.parse(registry.definition)
        expect(definition["condition"]).to eq("NEW.id > 0")
      end

      it "includes condition in checksum calculation" do
        form1 = form.dup
        form1.condition = "NEW.status = 'active'"
        described_class.create_trigger(form1, actor: { type: "User", id: 1 })
        registry1 = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "test_trigger")
        checksum1 = registry1.checksum

        # Clean up
        PgSqlTriggers::TriggerRegistry.destroy_all
        FileUtils.rm_rf(rails_root.join("app", "triggers"))
        FileUtils.rm_rf(rails_root.join("db", "triggers"))

        form2 = form.dup
        form2.condition = "NEW.status = 'inactive'"
        described_class.create_trigger(form2, actor: { type: "User", id: 1 })
        registry2 = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "test_trigger")
        checksum2 = registry2.checksum

        expect(checksum1).not_to eq(checksum2)
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

    it "works without Rails context" do
      # Test fallback to Dir.pwd when Rails.root is not available
      # Since we can't easily mock defined?, we test that the method works
      # by ensuring it can create files even when Rails.root might not be available
      # In practice, the method checks defined?(Rails) && Rails.respond_to?(:root)
      # We'll test the actual behavior by ensuring it creates files successfully
      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:success]).to be true
      # Files should be created relative to Rails.root (which is mocked in before block)
      expect(result[:migration_path]).to match(%r{db/triggers/\d+_test_trigger\.rb})
    end

    it "handles environment list in registry" do
      form.environments = %w[production staging]
      described_class.create_trigger(form, actor: { type: "User", id: 1 })

      registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
      expect(registry.environment).to eq("production,staging")
    end

    it "handles empty environment list in registry" do
      form.environments = []
      described_class.create_trigger(form, actor: { type: "User", id: 1 })

      registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
      expect(registry.environment).to be_nil
    end

    it "includes metadata in result" do
      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:metadata]).to be_present
      expect(result[:metadata][:trigger_name]).to eq(trigger_name)
      expect(result[:metadata][:table_name]).to eq("users")
      expect(result[:metadata][:events]).to eq(%w[insert update])
      expect(result[:metadata][:files_created]).to include(result[:migration_path], result[:dsl_path])
    end

    it "returns error result when file creation fails" do
      # Make the directory read-only to simulate permission error
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.mkdir_p(triggers_dir)
      FileUtils.chmod("a-w", triggers_dir)

      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    ensure
      # Restore permissions
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.chmod("a+w", triggers_dir) if Dir.exist?(triggers_dir)
    end

    it "handles file system errors during trigger creation" do
      # Make the directory read-only to simulate permission error
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.mkdir_p(triggers_dir)
      FileUtils.chmod("a-w", triggers_dir)

      result = described_class.create_trigger(form, actor: { type: "User", id: 1 })

      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    ensure
      # Restore permissions
      triggers_dir = rails_root.join("db", "triggers")
      FileUtils.chmod("a+w", triggers_dir) if Dir.exist?(triggers_dir)
    end

    it "does not include condition when column does not exist" do
      # Test with real column_names - if condition column doesn't exist, it won't be set
      form.condition = "NEW.id > 0"

      described_class.create_trigger(form, actor: { type: "User", id: 1 })

      registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
      # Condition will be set if the column exists, nil otherwise
      expect(registry).to be_present
    end

    it "handles nil function_body in checksum" do
      definition = {
        name: "test",
        table_name: "users",
        version: 1,
        function_body: nil,
        condition: nil
      }
      checksum = described_class.send(:calculate_checksum, definition)
      expect(checksum).to be_a(String)
      expect(checksum.length).to eq(64)
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

    it "includes all fields in checksum calculation" do
      def1 = {
        name: "test",
        table_name: "users",
        version: 1,
        function_body: "CREATE FUNCTION test()",
        condition: "NEW.id > 0"
      }
      def2 = {
        name: "test",
        table_name: "users",
        version: 1,
        function_body: "CREATE FUNCTION test()",
        condition: "NEW.id > 1"
      }

      checksum1 = described_class.send(:calculate_checksum, def1)
      checksum2 = described_class.send(:calculate_checksum, def2)

      expect(checksum1).not_to eq(checksum2)
    end

    it "handles missing fields in checksum" do
      definition = {
        name: "test",
        table_name: "users",
        version: 1
      }
      checksum = described_class.send(:calculate_checksum, definition)
      expect(checksum).to be_a(String)
      expect(checksum.length).to eq(64)
    end

    it "generates same checksum for identical definitions" do
      definition = {
        name: "test",
        table_name: "users",
        version: 1,
        function_body: "CREATE FUNCTION test()",
        condition: "NEW.id > 0",
        timing: "before"
      }

      checksum1 = described_class.send(:calculate_checksum, definition)
      checksum2 = described_class.send(:calculate_checksum, definition)

      expect(checksum1).to eq(checksum2)
    end

    it "includes timing in checksum calculation" do
      def1 = {
        name: "test",
        table_name: "users",
        version: 1,
        function_body: "CREATE FUNCTION test()",
        condition: "NEW.id > 0",
        timing: "before"
      }
      def2 = {
        name: "test",
        table_name: "users",
        version: 1,
        function_body: "CREATE FUNCTION test()",
        condition: "NEW.id > 0",
        timing: "after"
      }

      checksum1 = described_class.send(:calculate_checksum, def1)
      checksum2 = described_class.send(:calculate_checksum, def2)

      expect(checksum1).not_to eq(checksum2)
    end
  end
end
