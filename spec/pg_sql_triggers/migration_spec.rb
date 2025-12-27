# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers::Migration do
  let(:migration) { Class.new(PgTriggers::Migration).new }

  describe "#execute" do
    it "executes SQL through connection" do
      expect(ActiveRecord::Base.connection).to receive(:execute).with("SELECT 1")
      migration.execute("SELECT 1")
    end
  end

  it "inherits from ActiveRecord::Migration" do
    expect(PgTriggers::Migration.superclass).to eq(ActiveRecord::Migration[6.0])
  end
end

RSpec.describe PgTriggers::ApplicationController, type: :controller do
  controller(PgTriggers::ApplicationController) do
    def index
      render plain: "OK"
    end
  end

  before do
    routes.draw do
      get 'test_index', to: 'pg_sql_triggers/application#index'
    end
  end

  describe "#check_permissions" do
    it "allows access by default" do
      get :index
      expect(response).to have_http_status(:success)
    end
  end

  describe "#current_actor" do
    it "returns default actor hash" do
      # current_actor is private, so we need to call it through send
      actor = controller.send(:current_actor)
      expect(actor).to eq({
        type: "User",
        id: "unknown"
      })
    end
  end
end

