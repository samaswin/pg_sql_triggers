# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe PgTriggers::Migrator do
  let(:migrations_path) { Rails.root.join("db", "triggers") }

  before do
    FileUtils.mkdir_p(migrations_path) unless Dir.exist?(migrations_path)
  end

  after do
    # Clean up test migrations
    if Dir.exist?(migrations_path)
      Dir.glob(migrations_path.join("*.rb")).each { |f| File.delete(f) }
    end
    PgTriggers::Migrator.ensure_migrations_table!
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE trigger_migrations")
  end

  describe ".migrations_path" do
    it "returns the correct path" do
      expect(PgTriggers::Migrator.migrations_path).to eq(Rails.root.join("db", "triggers"))
    end
  end

  describe ".migrations_table_exists?" do
    it "returns true when table exists" do
      PgTriggers::Migrator.ensure_migrations_table!
      expect(PgTriggers::Migrator.migrations_table_exists?).to be true
    end

    it "returns false when table doesn't exist" do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS trigger_migrations")
      expect(PgTriggers::Migrator.migrations_table_exists?).to be false
      PgTriggers::Migrator.ensure_migrations_table!
    end
  end

  describe ".ensure_migrations_table!" do
    it "creates migrations table if it doesn't exist" do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS trigger_migrations")
      expect(PgTriggers::Migrator.migrations_table_exists?).to be false

      PgTriggers::Migrator.ensure_migrations_table!
      expect(PgTriggers::Migrator.migrations_table_exists?).to be true
    end

    it "does nothing if table already exists" do
      PgTriggers::Migrator.ensure_migrations_table!
      expect { PgTriggers::Migrator.ensure_migrations_table! }.not_to raise_error
    end
  end

  describe ".current_version" do
    it "returns 0 when no migrations have been run" do
      PgTriggers::Migrator.ensure_migrations_table!
      expect(PgTriggers::Migrator.current_version).to eq(0)
    end

    it "returns the latest migration version" do
      PgTriggers::Migrator.ensure_migrations_table!
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120002')")
      expect(PgTriggers::Migrator.current_version).to eq(20231215120002)
    end
  end

  describe ".migrations" do
    it "returns empty array when migrations directory doesn't exist" do
      FileUtils.rm_rf(migrations_path) if Dir.exist?(migrations_path)
      expect(PgTriggers::Migrator.migrations).to eq([])
    end

    it "parses migration files correctly" do
      migration_content = <<~RUBY
        class TestMigration < PgTriggers::Migration
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

      migrations = PgTriggers::Migrator.migrations
      expect(migrations.count).to eq(2)
      expect(migrations.map(&:version)).to contain_exactly(20231215120001, 20231215120002)
      expect(migrations.map(&:name)).to contain_exactly("test_migration", "another_migration")
    end

    it "sorts migrations by version" do
      migration_content = <<~RUBY
        class TestMigration < PgTriggers::Migration
          def up; end
          def down; end
        end
      RUBY

      File.write(migrations_path.join("20231215120003_third.rb"), migration_content)
      File.write(migrations_path.join("20231215120001_first.rb"), migration_content)
      File.write(migrations_path.join("20231215120002_second.rb"), migration_content)

      migrations = PgTriggers::Migrator.migrations
      expect(migrations.map(&:version)).to eq([20231215120001, 20231215120002, 20231215120003])
    end
  end

  describe ".pending_migrations" do
    before do
      migration_content = <<~RUBY
        class TestMigration < PgTriggers::Migration
          def up; end
          def down; end
        end
      RUBY

      File.write(migrations_path.join("20231215120001_first.rb"), migration_content)
      File.write(migrations_path.join("20231215120002_second.rb"), migration_content)
      File.write(migrations_path.join("20231215120003_third.rb"), migration_content)
    end

    it "returns migrations with version greater than current" do
      PgTriggers::Migrator.ensure_migrations_table!
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")

      pending = PgTriggers::Migrator.pending_migrations
      expect(pending.map(&:version)).to eq([20231215120002, 20231215120003])
    end

    it "returns all migrations when none have been run" do
      PgTriggers::Migrator.ensure_migrations_table!
      pending = PgTriggers::Migrator.pending_migrations
      expect(pending.map(&:version)).to eq([20231215120001, 20231215120002, 20231215120003])
    end

    it "returns empty array when all migrations are run" do
      PgTriggers::Migrator.ensure_migrations_table!
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120002')")
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120003')")

      pending = PgTriggers::Migrator.pending_migrations
      expect(pending).to be_empty
    end
  end

  describe ".run_up" do
    context "when applying all pending migrations" do
      let(:migration_content) do
        <<~RUBY
          class TestMigration < PgTriggers::Migration
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
        PgTriggers::Migrator.ensure_migrations_table!
        PgTriggers::Migrator.run_up

        expect(PgTriggers::Migrator.current_version).to eq(20231215120001)
        expect(ActiveRecord::Base.connection.table_exists?("test_table")).to be true
      end
    end

    context "when applying specific version" do
      let(:first_migration_content) do
        <<~RUBY
          class First < PgTriggers::Migration
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
          class Second < PgTriggers::Migration
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
        PgTriggers::Migrator.ensure_migrations_table!
        PgTriggers::Migrator.run_up(20231215120002)

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
        expect {
          PgTriggers::Migrator.run_up(99999999999999)
        }.to raise_error(StandardError, /Migration version 99999999999999 not found/)
      end

      it "raises error if migration already applied" do
        PgTriggers::Migrator.ensure_migrations_table!
        ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")

        expect {
          PgTriggers::Migrator.run_up(20231215120001)
        }.to raise_error(StandardError, /already applied/)
      end
    end
  end

  describe ".run_down" do
    let(:migration_content) do
      <<~RUBY
        class TestMigration < PgTriggers::Migration
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
      PgTriggers::Migrator.ensure_migrations_table!
      PgTriggers::Migrator.run_up
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_table")
    end

    it "rolls back the last migration" do
      expect(ActiveRecord::Base.connection.table_exists?("test_table")).to be true
      PgTriggers::Migrator.run_down
      expect(PgTriggers::Migrator.current_version).to eq(0)
    end

    it "returns early when no migrations exist" do
      PgTriggers::Migrator.run_down
      expect(PgTriggers::Migrator.current_version).to eq(0)
      expect { PgTriggers::Migrator.run_down }.not_to raise_error
    end

    context "when rolling back to specific version" do
      let(:second_migration_content) do
        <<~RUBY
          class Second < PgTriggers::Migration
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
          class Third < PgTriggers::Migration
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
        PgTriggers::Migrator.run_up
      end

      it "rolls back to the specified version" do
        expect(PgTriggers::Migrator.current_version).to eq(20231215120003)
        PgTriggers::Migrator.run_down(20231215120002)
        expect(PgTriggers::Migrator.current_version).to eq(20231215120002)
      end

      it "raises error if version not found or not applied" do
        expect {
          PgTriggers::Migrator.run_down(99999999999999)
        }.to raise_error(StandardError, /not found or not applied/)
      end
    end
  end

  describe ".status" do
    let(:migration_content) do
      <<~RUBY
        class TestMigration < PgTriggers::Migration
          def up; end
          def down; end
        end
      RUBY
    end

    before do
      File.write(migrations_path.join("20231215120001_first.rb"), migration_content)
      File.write(migrations_path.join("20231215120002_second.rb"), migration_content)
      PgTriggers::Migrator.ensure_migrations_table!
    end

    it "returns status for all migrations" do
      ActiveRecord::Base.connection.execute("INSERT INTO trigger_migrations (version) VALUES ('20231215120001')")

      status = PgTriggers::Migrator.status
      expect(status.count).to eq(2)
      expect(status.find { |s| s[:version] == 20231215120001 }[:status]).to eq("up")
      expect(status.find { |s| s[:version] == 20231215120002 }[:status]).to eq("down")
    end
  end

  describe ".cleanup_orphaned_registry_entries" do
    before do
      PgTriggers::TriggerRegistry.create!(
        trigger_name: "existing_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )

      PgTriggers::TriggerRegistry.create!(
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
      rescue
      end
    end

    after do
      begin
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS existing_trigger ON users")
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS existing_function()")
      rescue
      end
    end

    it "removes registry entries for triggers that don't exist in database" do
      expect(PgTriggers::TriggerRegistry.count).to eq(2)
      PgTriggers::Migrator.cleanup_orphaned_registry_entries
      expect(PgTriggers::TriggerRegistry.count).to eq(1)
      expect(PgTriggers::TriggerRegistry.first.trigger_name).to eq("existing_trigger")
    end
  end
end

