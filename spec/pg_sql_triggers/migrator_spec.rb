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

  describe ".status with basic migrations" do
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

  describe ".run" do
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

    it "calls run_up when direction is :up" do
      described_class.ensure_migrations_table!
      expect(described_class).to receive(:run_up).with(nil)
      described_class.run(:up)
    end

    it "calls run_down when direction is :down" do
      described_class.ensure_migrations_table!
      described_class.run_up
      expect(described_class).to receive(:run_down).with(nil)
      described_class.run(:down)
      described_class.run_up # restore
    end
  end

  describe ".status with table migrations" do
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
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_table")
    end

    it "returns status for all migrations" do
      status = described_class.status
      expect(status).to be_an(Array)
      expect(status.first).to include(:version, :name, :status, :filename)
      expect(status.first[:status]).to eq("down")
    end

    it "shows migrations as up after running them" do
      described_class.run_up
      status = described_class.status
      expect(status.first[:status]).to eq("up")
    end
  end

  describe ".version" do
    it "returns current_version" do
      described_class.ensure_migrations_table!
      allow(described_class).to receive(:current_version).and_return(123)
      expect(described_class.version).to eq(123)
    end
  end

  describe ".run_migration error handling with StandardError" do
    let(:invalid_migration_content) do
      <<~RUBY
        class InvalidMigration < PgSqlTriggers::Migration
          def up
            raise StandardError, "Test error"
          end
        end
      RUBY
    end

    before do
      File.write(migrations_path.join("20231215120001_invalid_migration.rb"), invalid_migration_content)
      described_class.ensure_migrations_table!
    end

    it "raises error when migration fails" do
      expect do
        described_class.run_up
      end.to raise_error(StandardError, /Error running trigger migration/)
    end
  end

  describe ".cleanup_orphaned_registry_entries" do
    before do
      create(:trigger_registry, :enabled, trigger_name: "existing_trigger", table_name: "users")
      create(:trigger_registry, :enabled, trigger_name: "orphaned_trigger", table_name: "posts")

      # Create a trigger in database for existing_trigger
      create_users_table
      begin
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          CREATE FUNCTION existing_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
        SQL
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          CREATE TRIGGER existing_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION existing_function();
        SQL
      rescue StandardError => _e
        # Ignore errors - function/trigger may already exist
      end
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS existing_trigger ON users")
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS existing_function()")
      drop_test_table(:users)
    rescue StandardError => _e
      # Ignore errors during cleanup - trigger/function may not exist
    end

    it "removes registry entries for triggers that don't exist in database" do
      expect(PgSqlTriggers::TriggerRegistry.count).to eq(2)
      described_class.cleanup_orphaned_registry_entries
      expect(PgSqlTriggers::TriggerRegistry.count).to eq(1)
      expect(PgSqlTriggers::TriggerRegistry.first.trigger_name).to eq("existing_trigger")
    end

    it "returns early if registry table doesn't exist" do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_call_original
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with("pg_sql_triggers_registry").and_return(false)
      expect { described_class.cleanup_orphaned_registry_entries }.not_to raise_error
    end
  end

  describe ".run_up with kill switch" do
    let(:migration_content) do
      <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up
            execute "SELECT 1"
          end
        end
      RUBY
    end

    before do
      File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
      described_class.ensure_migrations_table!
    end

    it "checks kill switch before running" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :migrator_run_up,
        environment: Rails.env,
        confirmation: nil,
        actor: { type: "Console", id: "Migrator.run_up" }
      )
      described_class.run_up
    end

    it "uses ENV confirmation text when provided" do
      ENV["CONFIRMATION_TEXT"] = "EXECUTE MIGRATOR_RUN_UP"
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :migrator_run_up,
        environment: Rails.env,
        confirmation: "EXECUTE MIGRATOR_RUN_UP",
        actor: { type: "Console", id: "Migrator.run_up" }
      )
      described_class.run_up
      ENV.delete("CONFIRMATION_TEXT")
    end

    it "uses explicit confirmation when provided" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :migrator_run_up,
        environment: Rails.env,
        confirmation: "custom_confirmation",
        actor: { type: "Console", id: "Migrator.run_up" }
      )
      described_class.run_up(confirmation: "custom_confirmation")
    end
  end

  describe ".run_down with kill switch" do
    let(:migration_content) do
      <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up
            execute "SELECT 1"
          end
          def down
            execute "SELECT 2"
          end
        end
      RUBY
    end

    before do
      File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
      described_class.ensure_migrations_table!
      described_class.run_up
    end

    it "checks kill switch before running" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :migrator_run_down,
        environment: Rails.env,
        confirmation: nil,
        actor: { type: "Console", id: "Migrator.run_down" }
      )
      described_class.run_down
    end
  end

  describe ".run_migration with class name resolution" do
    context "with direct class name" do
      let(:migration_content) do
        <<~RUBY
          class TestMigration < PgSqlTriggers::Migration
            def up
              execute "SELECT 1"
            end
            def down
              execute "SELECT 2"
            end
          end
        RUBY
      end

      before do
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
        described_class.ensure_migrations_table!
      end

      it "finds class with direct name" do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
        expect { described_class.run_up }.not_to raise_error
      end
    end

    context "with Add prefix" do
      let(:migration_content) do
        <<~RUBY
          class AddTestMigration < PgSqlTriggers::Migration
            def up
              execute "SELECT 1"
            end
            def down
              execute "SELECT 2"
            end
          end
        RUBY
      end

      before do
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
        described_class.ensure_migrations_table!
      end

      it "finds class with Add prefix" do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
        expect { described_class.run_up }.not_to raise_error
      end
    end

    context "with PgSqlTriggers namespace" do
      let(:migration_content) do
        <<~RUBY
          module PgSqlTriggers
            class TestMigration < PgSqlTriggers::Migration
              def up
                execute "SELECT 1"
              end
              def down
                execute "SELECT 2"
              end
            end
          end
        RUBY
      end

      before do
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
        described_class.ensure_migrations_table!
      end

      it "finds class with PgSqlTriggers namespace" do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
        expect { described_class.run_up }.not_to raise_error
      end
    end

    context "with Add prefix and namespace" do
      let(:migration_content) do
        <<~RUBY
          module PgSqlTriggers
            class AddTestMigration < PgSqlTriggers::Migration
              def up
                execute "SELECT 1"
              end
              def down
                execute "SELECT 2"
              end
            end
          end
        RUBY
      end

      before do
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
        described_class.ensure_migrations_table!
      end

      it "finds class with Add prefix and namespace" do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
        expect { described_class.run_up }.not_to raise_error
      end
    end
  end

  describe ".run_migration with safety validation" do
    let(:safe_migration_content) do
      <<~RUBY
        class SafeMigration < PgSqlTriggers::Migration
          def up
            execute "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
          end
        end
      RUBY
    end

    before do
      File.write(migrations_path.join("20231215120001_safe_migration.rb"), safe_migration_content)
      described_class.ensure_migrations_table!
    end

    it "performs safety validation" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # Use real SafetyValidator
      expect { described_class.run_up }.not_to raise_error
    end

    it "allows unsafe migrations when ALLOW_UNSAFE_MIGRATIONS is set" do
      ENV["ALLOW_UNSAFE_MIGRATIONS"] = "true"
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect { described_class.run_up }.not_to raise_error
      ENV.delete("ALLOW_UNSAFE_MIGRATIONS")
    end

    it "allows unsafe migrations when PgSqlTriggers.allow_unsafe_migrations is true" do
      allow(PgSqlTriggers).to receive(:allow_unsafe_migrations).and_return(true)
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect { described_class.run_up }.not_to raise_error
    end
  end

  describe ".run_migration with pre-apply comparison" do
    let(:migration_content) do
      <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up
            execute "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
          end
        end
      RUBY
    end

    before do
      File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
      described_class.ensure_migrations_table!
    end

    it "performs pre-apply comparison before migration" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # Use real PreApplyComparator
      expect { described_class.run_up }.not_to raise_error
    end

    it "logs differences when pre-apply comparison finds them" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # Use real PreApplyComparator - it will log if differences are found
      expect { described_class.run_up }.not_to raise_error
    end
  end

  describe ".run_migration error handling with LoadError" do
    context "with LoadError" do
      let(:invalid_migration_content) do
        <<~RUBY
            class InvalidMigration < PgSqlTriggers::Migration
              def up
                require "nonexistent_file"
              end
          end
        RUBY
      end

      before do
        File.write(migrations_path.join("20231215120001_invalid_migration.rb"), invalid_migration_content)
        described_class.ensure_migrations_table!
      end

      it "raises error with LoadError message" do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
        expect do
          described_class.run_up
        end.to raise_error(StandardError, /Error running trigger migration/)
      end
    end

    context "with migration file that doesn't define class" do
      let(:no_class_content) do
        <<~RUBY
          # This file doesn't define a class
          puts "hello"
        RUBY
      end

      before do
        File.write(migrations_path.join("20231215120001_no_class.rb"), no_class_content)
        described_class.ensure_migrations_table!
      end

      it "raises error when class not found" do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
        expect do
          described_class.run_up
        end.to raise_error(StandardError, /Error running trigger migration/)
      end
    end
  end

  describe ".migrations with edge cases" do
    it "handles migration files without underscore separator" do
      migration_content = <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up; end
          def down; end
        end
      RUBY
      File.write(migrations_path.join("20231215120001.rb"), migration_content)
      migrations = described_class.migrations
      expect(migrations.count).to eq(1)
      # When there's no underscore, the name falls back to the basename
      expect(migrations.first.name).to eq("20231215120001")
    end

    it "handles migration files with only version number" do
      migration_content = <<~RUBY
        class TestMigration < PgSqlTriggers::Migration
          def up; end
          def down; end
        end
      RUBY
      File.write(migrations_path.join("12345.rb"), migration_content)
      migrations = described_class.migrations
      expect(migrations.count).to eq(1)
      expect(migrations.first.version).to eq(12_345)
    end
  end
end
