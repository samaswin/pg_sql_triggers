# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::PermissionChecking, type: :controller do
  permission_checking_module = described_class

  controller(ActionController::Base) do
    include permission_checking_module

    def index
      head :ok
    end

    def viewer_gate
      check_viewer_permission
      return if performed?

      head :ok
    end

    def operator_gate
      check_operator_permission
      return if performed?

      head :ok
    end

    def admin_gate
      check_admin_permission
      return if performed?

      head :ok
    end

    def root_path
      "/"
    end

    def current_environment
      "test"
    end
  end

  before do
    routes.draw do
      get "index" => "anonymous#index"
      get "viewer_gate" => "anonymous#viewer_gate"
      get "operator_gate" => "anonymous#operator_gate"
      get "admin_gate" => "anonymous#admin_gate"
    end
    allow(Rails.logger).to receive(:error)
  end

  describe "#current_actor" do
    it "returns the default actor shape" do
      get :index
      expect(controller.current_actor).to eq({ type: "User", id: "unknown" })
    end

    it "allows nil type/id from host overrides" do
      allow(controller).to receive_messages(current_user_type: nil, current_user_id: nil)

      get :index

      expect(controller.current_actor).to eq({ type: nil, id: nil })
    end
  end

  describe "permission helper methods" do
    it "passes actor and environment to the permission checker" do
      allow(controller).to receive_messages(current_user_type: "AdminUser", current_user_id: "42")
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)

      get :index
      controller.can_view_triggers?

      expect(PgSqlTriggers::Permissions).to have_received(:can?).with(
        { type: "AdminUser", id: "42" },
        :view_triggers,
        environment: "test"
      )
    end

    it "delegates each helper method to the matching permission action" do
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)

      get :index

      controller.can_view_triggers?
      controller.can_enable_disable_triggers?
      controller.can_drop_triggers?
      controller.can_execute_sql_operations?
      controller.can_generate_triggers?
      controller.can_apply_triggers?

      expect(PgSqlTriggers::Permissions).to have_received(:can?).with(anything, :view_triggers, environment: "test")
      expect(PgSqlTriggers::Permissions).to have_received(:can?).with(anything, :enable_trigger, environment: "test")
      expect(PgSqlTriggers::Permissions).to have_received(:can?).with(anything, :drop_trigger, environment: "test")
      expect(PgSqlTriggers::Permissions).to have_received(:can?).with(anything, :execute_sql, environment: "test")
      expect(PgSqlTriggers::Permissions).to have_received(:can?).with(anything, :generate_trigger, environment: "test")
      expect(PgSqlTriggers::Permissions).to have_received(:can?).with(anything, :apply_trigger, environment: "test")
    end
  end

  describe "permission check before-actions" do
    it "redirects when viewer permission is denied" do
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)

      get :viewer_gate

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq("Insufficient permissions. Viewer role required.")
    end

    it "fails closed (redirects) when the permission checker raises" do
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_raise(StandardError, "Permission system error")

      get :viewer_gate

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq("Insufficient permissions. Viewer role required.")
      expect(Rails.logger).to have_received(:error).with(match(/Permission check failed/))
    end

    it "fails closed when the permission checker raises on operator gate" do
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_raise(StandardError, "boom")

      get :operator_gate

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq("Insufficient permissions. Operator role required.")
      expect(Rails.logger).to have_received(:error).with(match(/Permission check failed/))
    end

    it "fails closed when the permission checker raises on admin gate" do
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_raise(StandardError, "boom")

      get :admin_gate

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq("Insufficient permissions. Admin role required.")
      expect(Rails.logger).to have_received(:error).with(match(/Permission check failed/))
    end

    it "redirects when operator permission is denied" do
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)

      get :operator_gate

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq("Insufficient permissions. Operator role required.")
    end

    it "redirects when admin permission is denied" do
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)

      get :admin_gate

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq("Insufficient permissions. Admin role required.")
    end
  end
end
