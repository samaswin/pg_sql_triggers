# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers::TablesController, type: :controller do
  routes { PgTriggers::Engine.routes }

  before do
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR)")
    
    PgTriggers::TriggerRegistry.create!(
      trigger_name: "user_trigger",
      table_name: "users",
      version: 1,
      enabled: true,
      checksum: "abc",
      source: "dsl"
    )
  end

  after do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS users CASCADE")
  end

  describe "GET #index" do
    it "loads tables with triggers" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :tables_with_triggers).and_return([
        { table_name: "users", trigger_count: 1, registry_triggers: [], database_triggers: [] }
      ])

      get :index
      expect(assigns(:tables_with_triggers)).to be_an(Array)
      expect(assigns(:total_tables)).to be >= 0
    end

    it "only shows tables with triggers" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :tables_with_triggers).and_return([
        { table_name: "users", trigger_count: 1, registry_triggers: [], database_triggers: [] },
        { table_name: "posts", trigger_count: 0, registry_triggers: [], database_triggers: [] }
      ])

      get :index
      expect(assigns(:tables_with_triggers).map { |t| t[:table_name] }).not_to include("posts")
    end
  end

  describe "GET #show" do
    it "loads table triggers and columns" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :table_triggers).and_return({
        table_name: "users",
        registry_triggers: [],
        database_triggers: []
      })
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :table_columns).and_return([
        { name: "id", type: "integer", nullable: false }
      ])

      get :show, params: { id: "users" }
      expect(assigns(:table_info)).to be_present
      expect(assigns(:columns)).to be_an(Array)
    end

    it "responds with JSON format" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :table_triggers).and_return({
        table_name: "users",
        registry_triggers: [
          double(id: 1, trigger_name: "user_trigger", definition: { function_name: "user_func" }.to_json, enabled: true, version: 1, source: "dsl")
        ],
        database_triggers: []
      })
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :table_columns).and_return([])

      get :show, params: { id: "users" }, format: :json
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["table_name"]).to eq("users")
      expect(json).to have_key("registry_triggers")
      expect(json).to have_key("database_triggers")
    end
  end
end

