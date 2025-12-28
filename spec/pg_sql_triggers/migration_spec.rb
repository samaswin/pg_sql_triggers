# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Migration do
  let(:migration) { Class.new(described_class).new }

  describe "#execute" do
    it "executes SQL through connection" do
      expect(ActiveRecord::Base.connection).to receive(:execute).with("SELECT 1")
      migration.execute("SELECT 1")
    end
  end

  it "inherits from ActiveRecord::Migration" do
    expect(described_class.superclass).to eq(ActiveRecord::Migration[6.1])
  end
end

RSpec.describe PgSqlTriggers::ApplicationController, type: :controller do
  controller(described_class) do
    def index
      render plain: "OK"
    end
  end

  before do
    routes.draw do
      get "test_index", to: "pg_sql_triggers/application#index"
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

  describe "#current_user_type" do
    it "returns default user type" do
      user_type = controller.send(:current_user_type)
      expect(user_type).to eq("User")
    end
  end

  describe "#current_user_id" do
    it "returns default user id" do
      user_id = controller.send(:current_user_id)
      expect(user_id).to eq("unknown")
    end
  end

  describe "#expected_confirmation_text" do
    it "returns default confirmation text" do
      text = controller.send(:expected_confirmation_text, :test_operation)
      expect(text).to eq("EXECUTE TEST_OPERATION")
    end

    context "when custom confirmation pattern is configured" do
      before do
        allow(PgSqlTriggers).to receive(:respond_to?).with(:kill_switch_confirmation_pattern).and_return(true)
        allow(PgSqlTriggers).to receive(:kill_switch_confirmation_pattern).and_return(->(op) { "CUSTOM #{op}" })
      end

      it "uses custom confirmation pattern" do
        text = controller.send(:expected_confirmation_text, :test_operation)
        expect(text).to eq("CUSTOM test_operation")
      end
    end
  end
end
