# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::PermissionChecking, type: :controller, uses_database: false do
  # Create a test controller class that includes the concern
  controller_class = Class.new(PgSqlTriggers::ApplicationController) do
    include PgSqlTriggers::KillSwitchProtection
    include PgSqlTriggers::PermissionChecking
  end

  controller(controller_class) do
    def index
      render plain: "OK"
    end
  end

  routes { PgSqlTriggers::Engine.routes }

  before do
    routes.draw do
      get "test_index", to: "anonymous#index"
    end
    allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
  end

  describe "included behavior" do
    it "includes helper methods" do
      expect(controller.class._helper_methods).to include(:current_actor)
      expect(controller.class._helper_methods).to include(:can_view_triggers?)
      expect(controller.class._helper_methods).to include(:can_enable_disable_triggers?)
      expect(controller.class._helper_methods).to include(:can_drop_triggers?)
      expect(controller.class._helper_methods).to include(:can_execute_sql?)
      expect(controller.class._helper_methods).to include(:can_generate_triggers?)
      expect(controller.class._helper_methods).to include(:can_apply_triggers?)
    end
  end

  describe "#current_actor" do
    it "returns a hash with type and id" do
      actor = controller.send(:current_actor)
      expect(actor).to be_a(Hash)
      expect(actor[:type]).to eq("User")
      expect(actor[:id]).to eq("unknown")
    end

    it "uses current_user_type and current_user_id" do
      allow(controller).to receive_messages(current_user_type: "Admin", current_user_id: "123")
      actor = controller.send(:current_actor)
      expect(actor[:type]).to eq("Admin")
      expect(actor[:id]).to eq("123")
    end
  end

  describe "#current_user_type" do
    it "returns 'User' by default" do
      expect(controller.send(:current_user_type)).to eq("User")
    end
  end

  describe "#current_user_id" do
    it "returns 'unknown' by default" do
      expect(controller.send(:current_user_id)).to eq("unknown")
    end
  end

  describe "#check_viewer_permission" do
    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
      end

      it "does not redirect" do
        expect(controller).not_to receive(:redirect_to)
        controller.send(:check_viewer_permission)
      end

      it "allows the action to proceed" do
        expect { controller.send(:check_viewer_permission) }.not_to raise_error
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)
      end

      it "redirects to root path with alert" do
        expect(controller).to receive(:redirect_to).with(root_path, alert: "Insufficient permissions. Viewer role required.")
        controller.send(:check_viewer_permission)
      end
    end

    context "when permission check raises an error" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_raise(StandardError.new("Permission check failed"))
        allow(Rails.logger).to receive(:error)
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(match(/Permission check failed/))
        controller.send(:check_viewer_permission)
      end

      it "redirects to root path" do
        expect(controller).to receive(:redirect_to).with(root_path, alert: "Insufficient permissions. Viewer role required.")
        controller.send(:check_viewer_permission)
      end
    end

    it "passes current_environment to permission check" do
      allow(controller).to receive(:current_environment).and_return("production")
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        anything,
        :view_triggers,
        environment: "production"
      ).and_return(true)
      controller.send(:check_viewer_permission)
    end
  end

  describe "#check_operator_permission" do
    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
      end

      it "does not redirect" do
        expect(controller).not_to receive(:redirect_to)
        controller.send(:check_operator_permission)
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)
      end

      it "redirects to root path with alert" do
        expect(controller).to receive(:redirect_to).with(root_path, alert: "Insufficient permissions. Operator role required.")
        controller.send(:check_operator_permission)
      end
    end

    context "when permission check raises an error" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_raise(StandardError.new("Permission check failed"))
        allow(Rails.logger).to receive(:error)
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(match(/Permission check failed/))
        controller.send(:check_operator_permission)
      end

      it "redirects to root path" do
        expect(controller).to receive(:redirect_to).with(root_path, alert: "Insufficient permissions. Operator role required.")
        controller.send(:check_operator_permission)
      end
    end

    it "checks enable_trigger permission" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        anything,
        :enable_trigger,
        environment: anything
      ).and_return(true)
      controller.send(:check_operator_permission)
    end
  end

  describe "#check_admin_permission" do
    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
      end

      it "does not redirect" do
        expect(controller).not_to receive(:redirect_to)
        controller.send(:check_admin_permission)
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)
      end

      it "redirects to root path with alert" do
        expect(controller).to receive(:redirect_to).with(root_path, alert: "Insufficient permissions. Admin role required.")
        controller.send(:check_admin_permission)
      end
    end

    context "when permission check raises an error" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_raise(StandardError.new("Permission check failed"))
        allow(Rails.logger).to receive(:error)
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(match(/Permission check failed/))
        controller.send(:check_admin_permission)
      end

      it "redirects to root path" do
        expect(controller).to receive(:redirect_to).with(root_path, alert: "Insufficient permissions. Admin role required.")
        controller.send(:check_admin_permission)
      end
    end

    it "checks drop_trigger permission" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        anything,
        :drop_trigger,
        environment: anything
      ).and_return(true)
      controller.send(:check_admin_permission)
    end
  end

  describe "permission helper methods" do
    before do
      allow(controller).to receive(:current_environment).and_return("production")
    end

    describe "#can_view_triggers?" do
      it "checks view_triggers permission" do
        expect(PgSqlTriggers::Permissions).to receive(:can?).with(
          controller.send(:current_actor),
          :view_triggers,
          environment: "production"
        ).and_return(true)
        expect(controller.send(:can_view_triggers?)).to be true
      end
    end

    describe "#can_enable_disable_triggers?" do
      it "checks enable_trigger permission" do
        expect(PgSqlTriggers::Permissions).to receive(:can?).with(
          controller.send(:current_actor),
          :enable_trigger,
          environment: "production"
        ).and_return(true)
        expect(controller.send(:can_enable_disable_triggers?)).to be true
      end
    end

    describe "#can_drop_triggers?" do
      it "checks drop_trigger permission" do
        expect(PgSqlTriggers::Permissions).to receive(:can?).with(
          controller.send(:current_actor),
          :drop_trigger,
          environment: "production"
        ).and_return(true)
        expect(controller.send(:can_drop_triggers?)).to be true
      end
    end

    describe "#can_execute_sql?" do
      it "checks execute_sql permission" do
        expect(PgSqlTriggers::Permissions).to receive(:can?).with(
          controller.send(:current_actor),
          :execute_sql,
          environment: "production"
        ).and_return(true)
        expect(controller.send(:can_execute_sql?)).to be true
      end
    end

    describe "#can_generate_triggers?" do
      it "checks apply_trigger permission" do
        expect(PgSqlTriggers::Permissions).to receive(:can?).with(
          controller.send(:current_actor),
          :apply_trigger,
          environment: "production"
        ).and_return(true)
        expect(controller.send(:can_generate_triggers?)).to be true
      end
    end

    describe "#can_apply_triggers?" do
      it "checks apply_trigger permission" do
        expect(PgSqlTriggers::Permissions).to receive(:can?).with(
          controller.send(:current_actor),
          :apply_trigger,
          environment: "production"
        ).and_return(true)
        expect(controller.send(:can_apply_triggers?)).to be true
      end
    end
  end
end

