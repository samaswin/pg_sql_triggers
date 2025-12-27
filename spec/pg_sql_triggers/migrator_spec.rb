# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe PgSqlTriggers::Migrator do
  let(:migrations_path) { Rails.root.join("db/triggers") }

  before do
    FileUtils.mkdir_p(migrations_path)
  end

  after do
    # Clean up test migrations
    Dir.glob(migrations_path.join("*.rb")).each { |f| File.delete(f) } if Dir.exist?(migrations_path)
    described_class.ensure_migrations_table!
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE trigger_migrations")
  end

  describe ".migrations_path" do
    it "returns the correct path" do
      expect(described_class.migrations_path).to eq(Rails.root.join("db/triggers"))
    end
  end

  describe ".migrations_table_exists?" do
    it "returns true when table exists" do
      described_class.ensure_migrations_table!
      expect(described_class.migrations_table_exists?).to be true
    end

    it "returns false when table doesn't exist" do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS trigger_migrations")
      expect(described_class.migrations_table_exists?).to be false
      described_class.ensure_migrations_table!
    end
  end

  describe ".ensure_migrations_table!" do
    it "creates migrations table if it doesn't exist" do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS trigger_migrations")
      expect(described_class.migrations_table_exists?).to be false

      described_class.ensure_migrations_table!
      expect(described_class.migrations_table_exists?).to be true
    end

    it "does nothing if table already exists" do
      described_class.ensure_migrations_table!
      expect { described_class.ensure_migrations_table! }.not_to raise_error
    end
  end

  describe ".current_version" do
    it "returns 0 when no migrations have been run" do
      described_class.ensure_migrations_table!
      expect(described_class.current_version).to eq(0)
    end

    it "returns the latest migration version" do
      described_class.ensure_migrations_table!
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120002')")
      expect(described_class.current_version).to eq(20_231_215_120_002)
    end
  end

  describe ".migrations" do
    it "returns empty array when migrations directory doesn't exist" do
      FileUtils.rm_rf(migrations_path)
      expect(described_class.migrations).to eq([])
    end

    it "parses migration files correctly" do
      migration_content = <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up
            execute "SELECT 1"
          end

          def down
            execute "SELECT 2"
          end
        end
      RUBY

      File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
      File.write(migrations_path.join("20231215120002_another_migration.rb"), migration_content)

      migrations = described_class.migrations
      expect(migrations.count).to eq(2)
      expect(migrations.map(&:version)).to contain_exactly(20_231_215_120_001, 20_231_215_120_002)
      expect(migrations.map(&:name)).to contain_exactly("test_migration", "another_migration")
    end

    it "sorts migrations by version" do
      migration_content = <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up; end
          def down; end
        end
      RUBY

      File.write(migrations_path.join("20231215120003_third.rb"), migration_content)
      File.write(migrations_path.join("20231215120001_first.rb"), migration_content)
      File.write(migrations_path.join("20231215120002_second.rb"), migration_content)

      migrations = described_class.migrations
      expect(migrations.map(&:version)).to eq([20_231_215_120_001, 20_231_215_120_002, 20_231_215_120_003])
    end
  end

  describe ".pending_migrations" do
    before do
      migration_content = <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up; end
          def down; end
        end
      RUBY

      File.write(migrations_path.join("20231215120001_first.rb"), migration_content)
      File.write(migrations_path.join("20231215120002_second.rb"), migration_content)
      File.write(migrations_path.join("20231215120003_third.rb"), migration_content)
    end

    it "returns migrations with version greater than current" do
      described_class.ensure_migrations_table!
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")

      pending = described_class.pending_migrations
      expect(pending.map(&:version)).to eq([20_231_215_120_002, 20_231_215_120_003])
    end

    it "returns all migrations when none have been run" do
      described_class.ensure_migrations_table!
      pending = described_class.pending_migrations
      expect(pending.map(&:version)).to eq([20_231_215_120_001, 20_231_215_120_002, 20_231_215_120_003])
    end

    it "returns empty array when all migrations are run" do
      described_class.ensure_migrations_table!
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120002')")
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120003')")

      pending = described_class.pending_migrations
      expect(pending).to be_empty
    end
  end

  describe ".run_up" do
    context "when applying all pending migrations" do
      let(:migration_content) do
        <<~RUBY
          class TestMigration < PgSqlTriggers::Migration
            def up
              execute "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY)"
            end

            def down
              execute "DROP TABLE IF EXISTS test_table"
            end
          end
        RUBY
      end

      before do
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
      end

      after do
        ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_table")
      end

      it "applies all pending migrations" do
        described_class.ensure_migrations_table!
        described_class.run_up

        expect(described_class.current_version).to eq(20_231_215_120_001)
        expect(ActiveRecord::Base.connection.table_exists?("test_table")).to be true
      end
    end

    context "when applying specific version" do
      let(:first_migration_content) do
        <<~RUBY
          class First < PgSqlTriggers::Migration
            def up
              execute "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY)"
            end

            def down
              execute "DROP TABLE IF EXISTS test_table"
            end
          end
        RUBY
      end

      let(:second_migration_content) do
        <<~RUBY
          class Second < PgSqlTriggers::Migration
            def up
              execute "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY)"
            end

            def down
              execute "DROP TABLE IF EXISTS test_table"
            end
          end
        RUBY
      end

      before do
        File.write(migrations_path.join("20231215120001_first.rb"), first_migration_content)
        File.write(migrations_path.join("20231215120002_second.rb"), second_migration_content)
      end

      after do
        ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_table")
      end

      it "applies only the specified migration" do
        described_class.ensure_migrations_table!
        described_class.run_up(20_231_215_120_002)

        version_exists = ActiveRecord::Base.connection.select_value(
          "SELECT 1 FROM trigger_migrations WHERE version = '20231215120002' LIMIT 1"
        )
        expect(version_exists).to be_present

        first_exists = ActiveRecord::Base.connection.select_value(
          "SELECT 1 FROM trigger_migrations WHERE version = '20231215120001' LIMIT 1"
        )
        expect(first_exists).to be_nil
      end

      it "raises error if migration doesn't exist" do
        expect do
          described_class.run_up(99_999_999_999_999)
        end.to raise_error(StandardError, /Migration version 99999999999999 not found/)
      end

      it "raises error if migration already applied" do
        described_class.ensure_migrations_table!
        ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")

        expect do
          described_class.run_up(20_231_215_120_001)
        end.to raise_error(StandardError, /already applied/)
      end
    end
  end

  describe ".run_down" do
    let(:migration_content) do
      <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up
            execute "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY)"
          end

          def down
            execute "DROP TABLE IF EXISTS test_table"
          end
        end
      RUBY
    end

    before do
      File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
      described_class.ensure_migrations_table!
      described_class.run_up
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_table")
    end

    it "rolls back the last migration" do
      expect(ActiveRecord::Base.connection.table_exists?("test_table")).to be true
      described_class.run_down
      expect(described_class.current_version).to eq(0)
    end

    it "returns early when no migrations exist" do
      described_class.run_down
      expect(described_class.current_version).to eq(0)
      expect { described_class.run_down }.not_to raise_error
    end

    context "when rolling back to specific version" do
      let(:second_migration_content) do
        <<~RUBY
          class Second < PgSqlTriggers::Migration
            def up
              execute "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY)"
            end

            def down
              execute "DROP TABLE IF EXISTS test_table"
            end
          end
        RUBY
      end

      let(:third_migration_content) do
        <<~RUBY
          class Third < PgSqlTriggers::Migration
            def up
              execute "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY)"
            end

            def down
              execute "DROP TABLE IF EXISTS test_table"
            end
          end
        RUBY
      end

      before do
        File.write(migrations_path.join("20231215120002_second.rb"), second_migration_content)
        File.write(migrations_path.join("20231215120003_third.rb"), third_migration_content)
        described_class.run_up
      end

      it "rolls back to the specified version" do
        expect(described_class.current_version).to eq(20_231_215_120_003)
        described_class.run_down(20_231_215_120_002)
        expect(described_class.current_version).to eq(20_231_215_120_002)
      end

      it "raises error if version not found or not applied" do
        expect do
          described_class.run_down(99_999_999_999_999)
        end.to raise_error(StandardError, /not found or not applied/)
      end
    end
  end

  describe ".status" do
    let(:migration_content) do
      <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up; end
          def down; end
        end
      RUBY
    end

    before do
      File.write(migrations_path.join("20231215120001_first.rb"), migration_content)
      File.write(migrations_path.join("20231215120002_second.rb"), migration_content)
      described_class.ensure_migrations_table!
    end

    it "returns status for all migrations" do
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")

      status = described_class.status
      expect(status.count).to eq(2)
      expect(status.find { |s| s[:version] == 20_231_215_120_001 }[:status]).to eq("up")
      expect(status.find { |s| s[:version] == 20_231_215_120_002 }[:status]).to eq("down")
    end
  end

  describe ".cleanup_orphaned_registry_entries" do
    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "existing_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )

      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "orphaned_trigger",
        table_name: "posts",
        version: 1,
        enabled: true,
        checksum: "def",
        source: "dsl"
      )

      # Create a trigger in database for existing_trigger
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY)")
      begin
        ActiveRecord::Base.connection.execute("CREATE FUNCTION existing_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
        ActiveRecord::Base.connection.execute("CREATE TRIGGER existing_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION existing_function();")
      rescue StandardError => _e
        # Ignore errors - function/trigger may already exist
      end
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS existing_trigger ON users")
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS existing_function()")
    rescue StandardError => _e
      # Ignore errors during cleanup - trigger/function may not exist
    end

    it "removes registry entries for triggers that don't exist in database" do
      expect(PgSqlTriggers::TriggerRegistry.count).to eq(2)
      described_class.cleanup_orphaned_registry_entries
      expect(PgSqlTriggers::TriggerRegistry.count).to eq(1)
      expect(PgSqlTriggers::TriggerRegistry.first.trigger_name).to eq("existing_trigger")
    end
  end
end
