# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::MigrationsController, type: :controller do
  routes { PgSqlTriggers::Engine.routes }

  before do
    # Mock Rails.root
    allow(Rails).to receive(:root).and_return(Pathname.new(Dir.mktmpdir))
    allow(Rails.logger).to receive(:error)

    # Ensure migrations table exists
    allow(PgSqlTriggers::Migrator).to receive(:ensure_migrations_table!).and_return(true)
  end

  describe "POST #up" do
    context "when applying all pending migrations" do
      let(:pending_migrations) do
        [
          Struct.new(:version, :name, :filename, keyword_init: true).new(version: 20_231_215_120_001, name: "test_migration", filename: "20231215120001_test_migration.rb")
        ]
      end

      before do
        allow(PgSqlTriggers::Migrator).to receive_messages(pending_migrations: pending_migrations, run_up: true)
      end

      it "applies all pending migrations" do
        post :up
        expect(PgSqlTriggers::Migrator).to have_received(:run_up).with(no_args)
        expect(flash[:success]).to match(/Applied \d+ pending migration\(s\) successfully/)
      end

      it "redirects to root path" do
        post :up
        expect(response).to redirect_to(root_path)
      end
    end

    context "when applying a specific version" do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:run_up).with(20_231_215_120_001).and_return(true)
      end

      it "applies the specified migration version" do
        post :up, params: { version: "20231215120001" }
        expect(PgSqlTriggers::Migrator).to have_received(:run_up).with(20_231_215_120_001)
        expect(flash[:success]).to eq("Migration 20231215120001 applied successfully.")
      end
    end

    context "when no pending migrations exist" do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:pending_migrations).and_return([])
      end

      it "shows info message" do
        post :up
        expect(flash[:info]).to eq("No pending migrations to apply.")
      end
    end

    context "when migration fails" do
      let(:error_message) { "Migration failed" }

      before do
        allow(PgSqlTriggers::Migrator).to receive(:pending_migrations).and_raise(StandardError.new(error_message))
      end

      it "handles errors gracefully" do
        post :up
        expect(flash[:error]).to eq("Failed to apply migration: #{error_message}")
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe "POST #down" do
    context "when rolling back last migration" do
      before do
        allow(PgSqlTriggers::Migrator).to receive_messages(current_version: 20_231_215_120_001, run_down: true)
      end

      it "rolls back the last migration" do
        post :down
        expect(PgSqlTriggers::Migrator).to have_received(:run_down).with(no_args)
        expect(flash[:success]).to eq("Rolled back last migration successfully.")
      end

      it "redirects to root path" do
        post :down
        expect(response).to redirect_to(root_path)
      end
    end

    context "when rolling back to a specific version" do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(20_231_215_120_002)
        allow(PgSqlTriggers::Migrator).to receive(:run_down).with(20_231_215_120_001).and_return(true)
      end

      it "rolls back to the specified version" do
        post :down, params: { version: "20231215120001" }
        expect(PgSqlTriggers::Migrator).to have_received(:run_down).with(20_231_215_120_001)
        expect(flash[:success]).to eq("Migration version 20231215120001 rolled back successfully.")
      end
    end

    context "when no migrations exist" do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(0)
      end

      it "shows warning message" do
        post :down
        expect(flash[:warning]).to eq("No migrations to rollback.")
      end
    end

    context "when rollback fails" do
      let(:error_message) { "Rollback failed" }

      before do
        allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(20_231_215_120_001)
        allow(PgSqlTriggers::Migrator).to receive(:run_down).and_raise(StandardError.new(error_message))
      end

      it "handles errors gracefully" do
        post :down
        expect(flash[:error]).to eq("Failed to rollback migration: #{error_message}")
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe "POST #redo" do
    context "when redoing last migration" do
      before do
        allow(PgSqlTriggers::Migrator).to receive_messages(current_version: 20_231_215_120_001, run_down: true, run_up: true)
      end

      it "redoes the last migration" do
        post :redo
        expect(PgSqlTriggers::Migrator).to have_received(:run_down).with(no_args)
        expect(PgSqlTriggers::Migrator).to have_received(:run_up).with(no_args)
        expect(flash[:success]).to eq("Last migration redone successfully.")
      end

      it "redirects to root path" do
        post :redo
        expect(response).to redirect_to(root_path)
      end
    end

    context "when redoing a specific version" do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:run_down).with(20_231_215_120_001).and_return(true)
        allow(PgSqlTriggers::Migrator).to receive(:run_up).with(20_231_215_120_001).and_return(true)
      end

      it "redoes the specified migration version" do
        post :redo, params: { version: "20231215120001" }
        expect(PgSqlTriggers::Migrator).to have_received(:run_down).with(20_231_215_120_001)
        expect(PgSqlTriggers::Migrator).to have_received(:run_up).with(20_231_215_120_001)
        expect(flash[:success]).to eq("Migration 20231215120001 redone successfully.")
      end
    end

    context "when no migrations exist" do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(0)
      end

      it "shows warning message" do
        post :redo
        expect(flash[:warning]).to eq("No migrations to redo.")
      end
    end

    context "when redo fails" do
      let(:error_message) { "Redo failed" }

      before do
        allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(20_231_215_120_001)
        allow(PgSqlTriggers::Migrator).to receive(:run_down).and_raise(StandardError.new(error_message))
      end

      it "handles errors gracefully" do
        post :redo
        expect(flash[:error]).to eq("Failed to redo migration: #{error_message}")
        expect(Rails.logger).to have_received(:error)
      end
    end
  end
end
