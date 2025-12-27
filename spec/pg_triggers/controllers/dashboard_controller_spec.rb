# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers::DashboardController, type: :controller do
  routes { PgTriggers::Engine.routes }

  before do
    # Create test triggers
    PgTriggers::TriggerRegistry.create!(
      trigger_name: "enabled_trigger",
      table_name: "users",
      version: 1,
      enabled: true,
      checksum: "abc",
      source: "dsl"
    )
    PgTriggers::TriggerRegistry.create!(
      trigger_name: "disabled_trigger",
      table_name: "posts",
      version: 1,
      enabled: false,
      checksum: "def",
      source: "dsl"
    )
  end

  describe "GET #index" do
    it "loads all triggers" do
      get :index
      expect(assigns(:triggers).count).to eq(2)
    end

    it "calculates statistics" do
      get :index
      expect(assigns(:stats)[:total]).to eq(2)
      expect(assigns(:stats)[:enabled]).to eq(1)
      expect(assigns(:stats)[:disabled]).to eq(1)
    end

    it "loads migration status" do
      allow(PgTriggers::Migrator).to receive(:status).and_return([])
      allow(PgTriggers::Migrator).to receive(:pending_migrations).and_return([])
      allow(PgTriggers::Migrator).to receive(:current_version).and_return(0)

      get :index
      expect(assigns(:migration_status)).to be_an(Array)
      expect(assigns(:pending_migrations)).to be_an(Array)
      expect(assigns(:current_migration_version)).to eq(0)
    end

    it "handles pagination" do
      allow(PgTriggers::Migrator).to receive(:status).and_return(
        (1..25).map { |i| { version: i, name: "migration_#{i}", status: "up", filename: "#{i}_migration.rb" } }
      )
      allow(PgTriggers::Migrator).to receive(:pending_migrations).and_return([])
      allow(PgTriggers::Migrator).to receive(:current_version).and_return(0)

      get :index, params: { page: 1, per_page: 10 }
      expect(assigns(:migration_status).count).to eq(10)
      expect(assigns(:per_page)).to eq(10)
    end

    it "caps per_page at 100" do
      allow(PgTriggers::Migrator).to receive(:status).and_return([])
      allow(PgTriggers::Migrator).to receive(:pending_migrations).and_return([])
      allow(PgTriggers::Migrator).to receive(:current_version).and_return(0)

      get :index, params: { per_page: 200 }
      expect(assigns(:per_page)).to eq(100)
    end

    it "handles errors gracefully" do
      allow(PgTriggers::Migrator).to receive(:status).and_raise(StandardError.new("Error"))
      allow(Rails.logger).to receive(:error)

      get :index
      expect(assigns(:migration_status)).to eq([])
      expect(assigns(:pending_migrations)).to eq([])
    end
  end
end

