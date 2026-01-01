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
  end
end
