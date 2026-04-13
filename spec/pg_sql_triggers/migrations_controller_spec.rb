# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe PgSqlTriggers::MigrationsController, type: :controller do
  routes { PgSqlTriggers::Engine.routes }

  let(:tmp_dir) { Dir.mktmpdir }
  let(:migrations_path) { Pathname.new(tmp_dir).join("db/triggers") }

  before do
    # Set up temporary directory for migrations
    FileUtils.mkdir_p(migrations_path)
    allow(Rails).to receive(:root).and_return(Pathname.new(tmp_dir))

    # Ensure migrations table exists
    PgSqlTriggers::Migrator.ensure_migrations_table!

    # Capture log output
    @log_output = []
    allow(Rails.logger).to receive(:error) do |message|
      @log_output << message
    end
  end

  after do
    # Clean up test migrations
    FileUtils.rm_rf(tmp_dir)
    PgSqlTriggers::Migrator.ensure_migrations_table!
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE trigger_migrations")
  end

  describe "operator permission" do
    it "redirects with alert when apply_trigger is denied" do
      with_permission_denied(:apply_trigger) do
        post :up
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Insufficient permissions. Operator role required.")
      end
    end
  end

  describe "kill switch blocking (controller rescue)" do
    around do |example|
      with_kill_switch(
        enabled: true,
        environments: [Rails.env.to_sym],
        confirmation_required: true
      ) { example.run }
    end

    it "rescues KillSwitchError on up" do
      post :up
      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to match(/Kill switch is active/)
    end

    it "rescues KillSwitchError on down" do
      post :down
      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to match(/Kill switch is active/)
    end

    it "rescues KillSwitchError on redo" do
      post :redo
      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to match(/Kill switch is active/)
    end
  end

  describe "POST #up" do
    context "when applying all pending migrations" do
      before do
        # Create a test migration file
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
      end

      it "applies all pending migrations" do
        with_kill_switch_disabled do
          post :up
          expect(flash[:success]).to match(/Applied \d+ pending migration\(s\) successfully/)
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
        end
      end

      it "redirects to root path" do
        with_kill_switch_disabled do
          post :up
          expect(response).to redirect_to(root_path)
        end
      end
    end

    context "when applying a specific version" do
      before do
        # Create a test migration file
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
      end

      it "applies the specified migration version" do
        with_kill_switch_disabled do
          post :up, params: { version: "20231215120001" }
          expect(flash[:success]).to eq("Migration 20231215120001 applied successfully.")
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
        end
      end
    end

    context "when no pending migrations exist" do
      it "shows info message" do
        with_kill_switch_disabled do
          post :up
          expect(flash[:info]).to eq("No pending migrations to apply.")
        end
      end
    end

    context "when migration fails" do
      before do
        # Create a migration file that will fail
        migration_content = <<~RUBY
          class TestMigration < PgSqlTriggers::Migration
            def up
              execute "INVALID SQL SYNTAX THAT WILL FAIL"
            end

            def down
              execute "SELECT 2"
            end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
      end

      it "handles errors gracefully" do
        with_kill_switch_disabled do
          post :up
          expect(flash[:error]).to match(/Failed to apply migration/)
          expect(@log_output).to include(match(/Migration up failed/))
        end
      end
    end

    context "when the requested migration version does not exist" do
      it "shows a failure flash message" do
        with_kill_switch_disabled do
          post :up, params: { version: "20990101120000" }
          expect(flash[:error]).to match(/Failed to apply migration: Migration version 20990101120000 not found/)
        end
      end
    end

    context "when the requested migration version is already applied" do
      before do
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
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up(20_231_215_120_001)
        end
      end

      it "shows a failure flash message" do
        with_kill_switch_disabled do
          post :up, params: { version: "20231215120001" }
          expect(flash[:error]).to match(/Failed to apply migration: Migration version 20231215120001 is already applied/)
        end
      end
    end

    context "when the migration file cannot be loaded" do
      before do
        File.write(
          migrations_path.join("20231215120001_broken_require.rb"),
          <<~RUBY
            require "pg_sql_triggers_nonexistent_migration_require_#{Process.pid}"

            class BrokenRequire < PgSqlTriggers::Migration
              def up
                execute "SELECT 1"
              end

              def down
                execute "SELECT 2"
              end
            end
          RUBY
        )
      end

      it "surfaces a load error as a failed migration" do
        with_kill_switch_disabled do
          post :up, params: { version: "20231215120001" }
          expect(flash[:error]).to match(/Failed to apply migration: Error loading trigger migration/)
        end
      end
    end

    context "when safety validation blocks an unsafe migration" do
      before do
        ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_users (id SERIAL PRIMARY KEY)")
        ActiveRecord::Base.connection.execute(
          "CREATE OR REPLACE FUNCTION unsafe_trigger_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
        )
        ActiveRecord::Base.connection.execute(
          "CREATE TRIGGER unsafe_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION unsafe_trigger_func();"
        )
        unsafe_migration = <<~RUBY
          class UnsafeTriggerMigration < PgSqlTriggers::Migration
            def up
              execute "DROP TRIGGER unsafe_trigger ON test_users;"
              execute "CREATE TRIGGER unsafe_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION unsafe_trigger_func();"
            end

            def down
              execute "SELECT 1"
            end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_unsafe_trigger_migration.rb"), unsafe_migration)
      end

      after do
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS unsafe_trigger ON test_users")
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS unsafe_trigger_func()")
        ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users")
      rescue StandardError
        nil
      end

      it "rescues as a standard failure with an unsafe-migration message" do
        with_kill_switch_disabled do
          post :up, params: { version: "20231215120001" }
          expect(flash[:error]).to include("Migration blocked due to unsafe DROP + CREATE operations")
        end
      end
    end
  end

  describe "POST #down" do
    context "when rolling back last migration" do
      before do
        # Create and apply a migration first
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
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "rolls back the last migration" do
        with_kill_switch_disabled do
          post :down
          expect(flash[:success]).to eq("Rolled back last migration successfully.")
          expect(PgSqlTriggers::Migrator.current_version).to eq(0)
        end
      end

      it "redirects to root path" do
        with_kill_switch_disabled do
          post :down
          expect(response).to redirect_to(root_path)
        end
      end
    end

    context "when rolling back to a specific version" do
      before do
        # Create and apply two migrations
        migration1_content = <<~RUBY
          class TestMigration1 < PgSqlTriggers::Migration
            def up; execute "SELECT 1"; end
            def down; execute "SELECT 2"; end
          end
        RUBY
        migration2_content = <<~RUBY
          class TestMigration2 < PgSqlTriggers::Migration
            def up; execute "SELECT 3"; end
            def down; execute "SELECT 4"; end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration1.rb"), migration1_content)
        File.write(migrations_path.join("20231215120002_test_migration2.rb"), migration2_content)
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "rolls back to the specified version" do
        with_kill_switch_disabled do
          post :down, params: { version: "20231215120001" }
          expect(flash[:success]).to eq("Migration version 20231215120001 rolled back successfully.")
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
        end
      end
    end

    context "when no migrations exist" do
      it "shows warning message" do
        with_kill_switch_disabled do
          post :down
          expect(flash[:warning]).to eq("No migrations to rollback.")
        end
      end
    end

    context "when the requested rollback version does not exist" do
      before do
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
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "shows a failure flash message" do
        with_kill_switch_disabled do
          post :down, params: { version: "20990101120000" }
          expect(flash[:error]).to match(
            /Failed to rollback migration: Migration version 20990101120000 not found or not applied/
          )
        end
      end
    end

    context "when rollback fails" do
      before do
        # Create and apply a migration that will fail on rollback
        migration_content = <<~RUBY
          class TestMigration < PgSqlTriggers::Migration
            def up
              execute "SELECT 1"
            end

            def down
              execute "INVALID SQL SYNTAX THAT WILL FAIL"
            end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "handles errors gracefully" do
        with_kill_switch_disabled do
          post :down
          expect(flash[:error]).to match(/Failed to rollback migration/)
          expect(@log_output).to include(match(/Migration down failed/))
        end
      end
    end
  end

  describe "POST #redo" do
    context "when redoing last migration" do
      before do
        # Create and apply a migration first
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
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "redoes the last migration" do
        with_kill_switch_disabled do
          post :redo
          expect(flash[:success]).to eq("Last migration redone successfully.")
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
        end
      end

      it "redirects to root path" do
        with_kill_switch_disabled do
          post :redo
          expect(response).to redirect_to(root_path)
        end
      end
    end

    context "when redoing a specific version" do
      before do
        # Create and apply a migration first
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
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "redoes the specified migration version" do
        with_kill_switch_disabled do
          post :redo, params: { version: "20231215120001" }
          expect(flash[:success]).to eq("Migration 20231215120001 redone successfully.")
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
        end
      end
    end

    context "when no migrations exist" do
      it "shows warning message" do
        with_kill_switch_disabled do
          post :redo
          expect(flash[:warning]).to eq("No migrations to redo.")
        end
      end
    end

    context "when redo fails" do
      before do
        # Create and apply a migration that will fail on rollback
        migration_content = <<~RUBY
          class TestMigration < PgSqlTriggers::Migration
            def up
              execute "SELECT 1"
            end

            def down
              execute "INVALID SQL SYNTAX THAT WILL FAIL"
            end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "handles errors gracefully" do
        with_kill_switch_disabled do
          post :redo
          expect(flash[:error]).to match(/Failed to redo migration/)
          expect(@log_output).to include(match(/Migration redo failed/))
        end
      end
    end

    context "when redoing a newer version while an older version is current (run up only)" do
      before do
        migration1 = <<~RUBY
          class TestMigration1 < PgSqlTriggers::Migration
            def up
              execute "SELECT 1"
            end

            def down
              execute "SELECT 2"
            end
          end
        RUBY
        migration2 = <<~RUBY
          class TestMigration2 < PgSqlTriggers::Migration
            def up
              execute "SELECT 3"
            end

            def down
              execute "SELECT 4"
            end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration1.rb"), migration1)
        File.write(migrations_path.join("20231215120002_test_migration2.rb"), migration2)
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up(20_231_215_120_001)
        end
      end

      it "applies the target version and reports success" do
        with_kill_switch_disabled do
          post :redo, params: { version: "20231215120002" }
          expect(response).to redirect_to(root_path)
          expect(flash[:success]).to eq("Migration 20231215120002 redone successfully.")
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_002)
        end
      end
    end

    context "when redoing an older version with a newer migration applied" do
      before do
        migration1 = <<~RUBY
          class TestMigration1 < PgSqlTriggers::Migration
            def up
              execute "SELECT 1"
            end

            def down
              execute "SELECT 2"
            end
          end
        RUBY
        migration2 = <<~RUBY
          class TestMigration2 < PgSqlTriggers::Migration
            def up
              execute "SELECT 3"
            end

            def down
              execute "SELECT 4"
            end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration1.rb"), migration1)
        File.write(migrations_path.join("20231215120002_test_migration2.rb"), migration2)
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "rolls back through the target and reapplies it" do
        with_kill_switch_disabled do
          post :redo, params: { version: "20231215120001" }
          expect(response).to redirect_to(root_path)
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
        end
      end
    end
  end
end
