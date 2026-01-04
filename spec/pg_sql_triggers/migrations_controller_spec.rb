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

    context "when redoing a specific version that is current" do
      before do
        migration_content = <<~RUBY
          class TestMigration < PgSqlTriggers::Migration
            def up; execute "SELECT 1"; end
            def down; execute "SELECT 2"; end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "rolls back and reapplies the target version" do
        with_kill_switch_disabled do
          post :redo, params: { version: "20231215120001" }
          expect(flash[:success]).to eq("Migration 20231215120001 redone successfully.")
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
        end
      end
    end

    context "when redoing a specific version that is not current" do
      before do
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

      it "rolls back to before target and reapplies" do
        with_kill_switch_disabled do
          post :redo, params: { version: "20231215120001" }
          expect(flash[:success]).to eq("Migration 20231215120001 redone successfully.")
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
        end
      end
    end

    context "when target version is not applied yet" do
      before do
        migration_content = <<~RUBY
          class TestMigration < PgSqlTriggers::Migration
            def up; execute "SELECT 1"; end
            def down; execute "SELECT 2"; end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
      end

      it "just applies the target version" do
        with_kill_switch_disabled do
          post :redo, params: { version: "20231215120001" }
          expect(flash[:success]).to eq("Migration 20231215120001 redone successfully.")
          expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
        end
      end
    end
  end

  describe "kill switch protection" do
    describe "POST #up" do
      it "checks kill switch before running migration" do
        with_kill_switch_protecting(Rails.env, confirmation_required: true) do
          expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_raise(
            PgSqlTriggers::KillSwitchError.new("Kill switch active")
          )
          post :up
          expect(flash[:error]).to match(/kill switch|Kill switch/)
        end
      end

      it "allows migration with confirmation" do
        with_kill_switch_protecting(Rails.env, confirmation_required: true) do
          allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
          post :up, params: { confirmation_text: "EXECUTE UI_MIGRATION_UP" }
          expect(flash[:success] || flash[:info]).to be_present
        end
      end
    end

    describe "POST #down" do
      before do
        migration_content = <<~RUBY
          class TestMigration < PgSqlTriggers::Migration
            def up; execute "SELECT 1"; end
            def down; execute "SELECT 2"; end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "checks kill switch before rolling back" do
        with_kill_switch_protecting(Rails.env, confirmation_required: true) do
          expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_raise(
            PgSqlTriggers::KillSwitchError.new("Kill switch active")
          )
          post :down
          expect(flash[:error]).to match(/kill switch|Kill switch/)
        end
      end

      it "allows rollback with confirmation" do
        with_kill_switch_protecting(Rails.env, confirmation_required: true) do
          allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
          post :down, params: { confirmation_text: "EXECUTE UI_MIGRATION_DOWN" }
          expect(flash[:success] || flash[:warning]).to be_present
        end
      end
    end

    describe "POST #redo" do
      before do
        migration_content = <<~RUBY
          class TestMigration < PgSqlTriggers::Migration
            def up; execute "SELECT 1"; end
            def down; execute "SELECT 2"; end
          end
        RUBY
        File.write(migrations_path.join("20231215120001_test_migration.rb"), migration_content)
        with_kill_switch_disabled do
          PgSqlTriggers::Migrator.run_up
        end
      end

      it "checks kill switch before redoing" do
        with_kill_switch_protecting(Rails.env, confirmation_required: true) do
          expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_raise(
            PgSqlTriggers::KillSwitchError.new("Kill switch active")
          )
          post :redo
          expect(flash[:error]).to match(/kill switch|Kill switch/)
        end
      end

      it "allows redo with confirmation" do
        with_kill_switch_protecting(Rails.env, confirmation_required: true) do
          allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
          post :redo, params: { confirmation_text: "EXECUTE UI_MIGRATION_REDO" }
          expect(flash[:success]).to be_present
        end
      end
    end
  end

  describe "permission checks" do
    describe "before_action :check_operator_permission" do
      it "allows action when user has operator permission" do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
        post :up
        expect(response).not_to redirect_to(root_path)
      end

      it "redirects when user lacks operator permission" do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)
        post :up
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("Operator role required")
      end
    end
  end

  describe "private methods" do
    describe "#redo_target_migration" do
      before do
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
      end

      context "when target version is current version" do
        before do
          with_kill_switch_disabled do
            PgSqlTriggers::Migrator.run_up
          end
        end

        it "rolls back last migration and reapplies" do
          with_kill_switch_disabled do
            controller.send(:redo_target_migration, 20_231_215_120_002, 20_231_215_120_002)
            expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_002)
          end
        end
      end

      context "when target version is less than current" do
        before do
          with_kill_switch_disabled do
            PgSqlTriggers::Migrator.run_up
          end
        end

        it "rolls back to before target and reapplies" do
          with_kill_switch_disabled do
            controller.send(:redo_target_migration, 20_231_215_120_001, 20_231_215_120_002)
            expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
          end
        end
      end

      context "when target version is greater than current" do
        it "just applies the target version" do
          with_kill_switch_disabled do
            controller.send(:redo_target_migration, 20_231_215_120_002, 20_231_215_120_001)
            expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_002)
          end
        end
      end
    end

    describe "#rollback_to_before_target" do
      before do
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

      context "when previous migration exists" do
        it "rolls back to previous migration" do
          with_kill_switch_disabled do
            controller.send(:rollback_to_before_target, 20_231_215_120_002)
            expect(PgSqlTriggers::Migrator.current_version).to eq(20_231_215_120_001)
          end
        end
      end

      context "when no previous migration exists" do
        it "rolls back until below target" do
          with_kill_switch_disabled do
            controller.send(:rollback_to_before_target, 20_231_215_120_001)
            expect(PgSqlTriggers::Migrator.current_version).to eq(0)
          end
        end
      end
    end

    describe "#rollback_until_below_target" do
      before do
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

      it "rolls back until version is below target" do
        with_kill_switch_disabled do
          controller.send(:rollback_until_below_target, 20_231_215_120_001)
          expect(PgSqlTriggers::Migrator.current_version).to be < 20_231_215_120_001
        end
      end

      it "stops at version 0 if needed" do
        with_kill_switch_disabled do
          controller.send(:rollback_until_below_target, 20_231_215_120_001)
          expect(PgSqlTriggers::Migrator.current_version).to eq(0)
        end
      end
    end
  end
end
