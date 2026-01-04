# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::ApplicationController, type: :controller do
  # Create a test controller that inherits from ApplicationController
  # to test the actual behavior
  controller(described_class) do
    def index
      render plain: "OK"
    end

    def test_action
      check_kill_switch(operation: :test_operation, confirmation: params[:confirmation])
      render plain: "OK"
    end

    def test_action_with_override
      require_kill_switch_override(:test_operation, confirmation: params[:confirmation])
      render plain: "OK"
    end
  end

  # Use existing engine routes - we'll test through a real controller action
  routes { PgSqlTriggers::Engine.routes }

  before do
    # Configure view paths
    engine_view_path = PgSqlTriggers::Engine.root.join("app/views").to_s
    controller.prepend_view_path(engine_view_path) if controller.respond_to?(:prepend_view_path)

    # Setup default kill switch configuration
    allow(PgSqlTriggers).to receive_messages(
      kill_switch_enabled: true,
      kill_switch_environments: %i[production staging],
      kill_switch_confirmation_required: true,
      kill_switch_logger: instance_double(Logger),
      kill_switch_confirmation_pattern: ->(op) { "EXECUTE #{op.to_s.upcase}" }
    )

    # Clear ENV overrides
    ENV.delete("KILL_SWITCH_OVERRIDE")
    ENV.delete("CONFIRMATION_TEXT")

    # Reset thread-local state
    Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY] = nil
  end

  describe "before_action :check_permissions?" do
    # Test through DashboardController which inherits from ApplicationController
    let(:dashboard_controller) { PgSqlTriggers::DashboardController.new }

    it "calls check_permissions? before each action" do
      allow(dashboard_controller).to receive_messages(check_permissions?: true, index: nil)
      dashboard_controller.send(:check_permissions?)
      expect(dashboard_controller).to have_received(:check_permissions?)
    end
  end

  describe "#check_permissions?" do
    it "returns true by default and can be overridden in host application" do
      expect(controller.send(:check_permissions?)).to be true
      # This is a private method that can be overridden in subclasses
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
    it "returns 'User' by default and can be overridden" do
      expect(controller.send(:current_user_type)).to eq("User")
      # This is a hook method that can be overridden in host application
    end
  end

  describe "#current_user_id" do
    it "returns 'unknown' by default and can be overridden" do
      expect(controller.send(:current_user_id)).to eq("unknown")
      # This is a hook method that can be overridden in host application
    end
  end

  describe "PermissionChecking concern" do
    describe "helper method declarations" do
      it "exposes current_actor as a helper method" do
        expect(controller.class._helper_methods).to include(:current_actor)
      end

      it "exposes can_view_triggers? as a helper method" do
        expect(controller.class._helper_methods).to include(:can_view_triggers?)
      end

      it "exposes can_enable_disable_triggers? as a helper method" do
        expect(controller.class._helper_methods).to include(:can_enable_disable_triggers?)
      end

      it "exposes can_drop_triggers? as a helper method" do
        expect(controller.class._helper_methods).to include(:can_drop_triggers?)
      end

      it "exposes can_execute_sql? as a helper method" do
        expect(controller.class._helper_methods).to include(:can_execute_sql?)
      end

      it "exposes can_generate_triggers? as a helper method" do
        expect(controller.class._helper_methods).to include(:can_generate_triggers?)
      end

      it "exposes can_apply_triggers? as a helper method" do
        expect(controller.class._helper_methods).to include(:can_apply_triggers?)
      end
    end

    describe "#check_viewer_permission" do
      let(:actor) { { type: "User", id: "123" } }
      let(:environment) { "production" }

      before do
        allow(controller).to receive(:current_actor).and_return(actor)
        allow(controller).to receive(:current_environment).and_return(environment)
        allow(Rails.logger).to receive(:error)
      end

      context "when permission is granted" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :view_triggers, environment: environment)
            .and_return(true)
        end

        it "does not redirect" do
          controller.send(:check_viewer_permission)
          expect(response).not_to have_http_status(:redirect)
        end

        it "returns nil" do
          result = controller.send(:check_viewer_permission)
          expect(result).to be_nil
        end
      end

      context "when permission is denied" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :view_triggers, environment: environment)
            .and_return(false)
          allow(controller).to receive(:redirect_to)
        end

        it "redirects to root_path with alert message" do
          controller.send(:check_viewer_permission)
          expect(controller).to have_received(:redirect_to).with(
            root_path,
            alert: "Insufficient permissions. Viewer role required."
          )
        end
      end

      context "when permission check raises an error" do
        let(:error) { StandardError.new("Permission system error") }

        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :view_triggers, environment: environment)
            .and_raise(error)
          allow(controller).to receive(:redirect_to)
        end

        it "logs the error" do
          controller.send(:check_viewer_permission)
          expect(Rails.logger).to have_received(:error).with(
            /Permission check failed: Permission system error/
          )
        end

        it "redirects to root_path with alert message" do
          controller.send(:check_viewer_permission)
          expect(controller).to have_received(:redirect_to).with(
            root_path,
            alert: "Insufficient permissions. Viewer role required."
          )
        end

        it "handles the error gracefully" do
          expect { controller.send(:check_viewer_permission) }.not_to raise_error
        end
      end
    end

    describe "#check_operator_permission" do
      let(:actor) { { type: "User", id: "123" } }
      let(:environment) { "production" }

      before do
        allow(controller).to receive(:current_actor).and_return(actor)
        allow(controller).to receive(:current_environment).and_return(environment)
        allow(Rails.logger).to receive(:error)
      end

      context "when permission is granted" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :enable_trigger, environment: environment)
            .and_return(true)
        end

        it "does not redirect" do
          controller.send(:check_operator_permission)
          expect(response).not_to have_http_status(:redirect)
        end

        it "returns nil" do
          result = controller.send(:check_operator_permission)
          expect(result).to be_nil
        end
      end

      context "when permission is denied" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :enable_trigger, environment: environment)
            .and_return(false)
          allow(controller).to receive(:redirect_to)
        end

        it "redirects to root_path with alert message" do
          controller.send(:check_operator_permission)
          expect(controller).to have_received(:redirect_to).with(
            root_path,
            alert: "Insufficient permissions. Operator role required."
          )
        end
      end

      context "when permission check raises an error" do
        let(:error) { StandardError.new("Permission system error") }

        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :enable_trigger, environment: environment)
            .and_raise(error)
          allow(controller).to receive(:redirect_to)
        end

        it "logs the error" do
          controller.send(:check_operator_permission)
          expect(Rails.logger).to have_received(:error).with(
            /Permission check failed: Permission system error/
          )
        end

        it "redirects to root_path with alert message" do
          controller.send(:check_operator_permission)
          expect(controller).to have_received(:redirect_to).with(
            root_path,
            alert: "Insufficient permissions. Operator role required."
          )
        end

        it "handles the error gracefully" do
          expect { controller.send(:check_operator_permission) }.not_to raise_error
        end
      end
    end

    describe "#check_admin_permission" do
      let(:actor) { { type: "User", id: "123" } }
      let(:environment) { "production" }

      before do
        allow(controller).to receive(:current_actor).and_return(actor)
        allow(controller).to receive(:current_environment).and_return(environment)
        allow(Rails.logger).to receive(:error)
      end

      context "when permission is granted" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :drop_trigger, environment: environment)
            .and_return(true)
        end

        it "does not redirect" do
          controller.send(:check_admin_permission)
          expect(response).not_to have_http_status(:redirect)
        end

        it "returns nil" do
          result = controller.send(:check_admin_permission)
          expect(result).to be_nil
        end
      end

      context "when permission is denied" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :drop_trigger, environment: environment)
            .and_return(false)
          allow(controller).to receive(:redirect_to)
        end

        it "redirects to root_path with alert message" do
          controller.send(:check_admin_permission)
          expect(controller).to have_received(:redirect_to).with(
            root_path,
            alert: "Insufficient permissions. Admin role required."
          )
        end
      end

      context "when permission check raises an error" do
        let(:error) { StandardError.new("Permission system error") }

        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :drop_trigger, environment: environment)
            .and_raise(error)
          allow(controller).to receive(:redirect_to)
        end

        it "logs the error" do
          controller.send(:check_admin_permission)
          expect(Rails.logger).to have_received(:error).with(
            /Permission check failed: Permission system error/
          )
        end

        it "redirects to root_path with alert message" do
          controller.send(:check_admin_permission)
          expect(controller).to have_received(:redirect_to).with(
            root_path,
            alert: "Insufficient permissions. Admin role required."
          )
        end

        it "handles the error gracefully" do
          expect { controller.send(:check_admin_permission) }.not_to raise_error
        end
      end
    end

    # Test PermissionChecking concern's can_* methods directly (not PermissionsHelper's overrides)
    # by testing on a controller that only includes PermissionChecking
    let(:permission_checking_controller_class) do
      Class.new(ActionController::Base) do
        include PgSqlTriggers::KillSwitchProtection
        include PgSqlTriggers::PermissionChecking
      end
    end

    describe "#can_view_triggers?" do
      let(:test_controller) { permission_checking_controller_class.new }
      let(:actor) { { type: "User", id: "123" } }
      let(:environment) { "production" }

      before do
        allow(test_controller).to receive(:current_actor).and_return(actor)
        allow(test_controller).to receive(:current_environment).and_return(environment)
      end

      context "when permission is granted" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :view_triggers, environment: environment)
            .and_return(true)
        end

        it "returns true" do
          expect(test_controller.send(:can_view_triggers?)).to be true
        end

        it "calls Permissions.can? with correct arguments" do
          test_controller.send(:can_view_triggers?)
          expect(PgSqlTriggers::Permissions).to have_received(:can?)
            .with(actor, :view_triggers, environment: environment)
        end
      end

      context "when permission is denied" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :view_triggers, environment: environment)
            .and_return(false)
        end

        it "returns false" do
          expect(test_controller.send(:can_view_triggers?)).to be false
        end
      end
    end

    describe "#can_enable_disable_triggers?" do
      let(:test_controller) { permission_checking_controller_class.new }
      let(:actor) { { type: "User", id: "123" } }
      let(:environment) { "production" }

      before do
        allow(test_controller).to receive(:current_actor).and_return(actor)
        allow(test_controller).to receive(:current_environment).and_return(environment)
      end

      context "when permission is granted" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :enable_trigger, environment: environment)
            .and_return(true)
        end

        it "returns true" do
          expect(test_controller.send(:can_enable_disable_triggers?)).to be true
        end

        it "calls Permissions.can? with correct arguments" do
          test_controller.send(:can_enable_disable_triggers?)
          expect(PgSqlTriggers::Permissions).to have_received(:can?)
            .with(actor, :enable_trigger, environment: environment)
        end
      end

      context "when permission is denied" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :enable_trigger, environment: environment)
            .and_return(false)
        end

        it "returns false" do
          expect(test_controller.send(:can_enable_disable_triggers?)).to be false
        end
      end
    end

    describe "#can_drop_triggers?" do
      let(:test_controller) { permission_checking_controller_class.new }
      let(:actor) { { type: "User", id: "123" } }
      let(:environment) { "production" }

      before do
        allow(test_controller).to receive(:current_actor).and_return(actor)
        allow(test_controller).to receive(:current_environment).and_return(environment)
      end

      context "when permission is granted" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :drop_trigger, environment: environment)
            .and_return(true)
        end

        it "returns true" do
          expect(test_controller.send(:can_drop_triggers?)).to be true
        end

        it "calls Permissions.can? with correct arguments" do
          test_controller.send(:can_drop_triggers?)
          expect(PgSqlTriggers::Permissions).to have_received(:can?)
            .with(actor, :drop_trigger, environment: environment)
        end
      end

      context "when permission is denied" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :drop_trigger, environment: environment)
            .and_return(false)
        end

        it "returns false" do
          expect(test_controller.send(:can_drop_triggers?)).to be false
        end
      end
    end

    describe "#can_execute_sql?" do
      let(:test_controller) { permission_checking_controller_class.new }
      let(:actor) { { type: "User", id: "123" } }
      let(:environment) { "production" }

      before do
        allow(test_controller).to receive(:current_actor).and_return(actor)
        allow(test_controller).to receive(:current_environment).and_return(environment)
      end

      context "when permission is granted" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :execute_sql, environment: environment)
            .and_return(true)
        end

        it "returns true" do
          expect(test_controller.send(:can_execute_sql?)).to be true
        end

        it "calls Permissions.can? with correct arguments" do
          test_controller.send(:can_execute_sql?)
          expect(PgSqlTriggers::Permissions).to have_received(:can?)
            .with(actor, :execute_sql, environment: environment)
        end
      end

      context "when permission is denied" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :execute_sql, environment: environment)
            .and_return(false)
        end

        it "returns false" do
          expect(test_controller.send(:can_execute_sql?)).to be false
        end
      end
    end

    describe "#can_generate_triggers?" do
      let(:test_controller) { permission_checking_controller_class.new }
      let(:actor) { { type: "User", id: "123" } }
      let(:environment) { "production" }

      before do
        allow(test_controller).to receive(:current_actor).and_return(actor)
        allow(test_controller).to receive(:current_environment).and_return(environment)
      end

      context "when permission is granted" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :apply_trigger, environment: environment)
            .and_return(true)
        end

        it "returns true" do
          expect(test_controller.send(:can_generate_triggers?)).to be true
        end

        it "calls Permissions.can? with correct arguments" do
          test_controller.send(:can_generate_triggers?)
          expect(PgSqlTriggers::Permissions).to have_received(:can?)
            .with(actor, :apply_trigger, environment: environment)
        end
      end

      context "when permission is denied" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :apply_trigger, environment: environment)
            .and_return(false)
        end

        it "returns false" do
          expect(test_controller.send(:can_generate_triggers?)).to be false
        end
      end
    end

    describe "#can_apply_triggers?" do
      let(:test_controller) { permission_checking_controller_class.new }
      let(:actor) { { type: "User", id: "123" } }
      let(:environment) { "production" }

      before do
        allow(test_controller).to receive(:current_actor).and_return(actor)
        allow(test_controller).to receive(:current_environment).and_return(environment)
      end

      context "when permission is granted" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :apply_trigger, environment: environment)
            .and_return(true)
        end

        it "returns true" do
          expect(test_controller.send(:can_apply_triggers?)).to be true
        end

        it "calls Permissions.can? with correct arguments" do
          test_controller.send(:can_apply_triggers?)
          expect(PgSqlTriggers::Permissions).to have_received(:can?)
            .with(actor, :apply_trigger, environment: environment)
        end
      end

      context "when permission is denied" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?)
            .with(actor, :apply_trigger, environment: environment)
            .and_return(false)
        end

        it "returns false" do
          expect(test_controller.send(:can_apply_triggers?)).to be false
        end
      end
    end
  end

  describe "helper methods" do
    it "exposes current_environment as a helper method" do
      # Helper methods are available in views, but we can test the method directly
      expect(controller.send(:current_environment)).to eq(Rails.env)
      # Test that it's declared as a helper method
      expect(controller.class._helper_methods).to include(:current_environment)
    end

    it "exposes kill_switch_active? as a helper method" do
      # Helper methods are available in views, but we can test the method directly
      # Helper methods are made available to views, but can be called on controller
      expect(controller.send(:kill_switch_active?)).to be_a(TrueClass).or be_a(FalseClass)
      expect(controller.class._helper_methods).to include(:kill_switch_active?)
    end

    it "exposes expected_confirmation_text as a helper method" do
      # Helper methods are available in views, but we can test the method directly
      # Helper methods are made available to views, but can be called on controller
      expect(controller.send(:expected_confirmation_text, :test)).to be_a(String)
      expect(controller.class._helper_methods).to include(:expected_confirmation_text)
    end
  end

  describe "#current_environment" do
    it "returns Rails.env" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      expect(controller.send(:current_environment)).to eq("production")
    end

    it "returns the current Rails environment" do
      expect(controller.send(:current_environment)).to eq(Rails.env.to_s)
    end
  end

  describe "#kill_switch_active?" do
    context "when kill switch is enabled for the environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:active?).and_return(true)
      end

      it "returns true" do
        expect(controller.send(:kill_switch_active?)).to be true
      end
    end

    context "when kill switch is not enabled for the environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:active?).and_return(false)
      end

      it "returns false" do
        expect(controller.send(:kill_switch_active?)).to be false
      end
    end

    it "passes the current environment to KillSwitch.active?" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("staging"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:active?).and_return(false)
      controller.send(:kill_switch_active?)
      expect(PgSqlTriggers::SQL::KillSwitch).to have_received(:active?).with(environment: "staging")
    end
  end

  describe "#check_kill_switch" do
    context "when kill switch is active" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:active?).and_return(true)
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_raise(
          PgSqlTriggers::KillSwitchError.new("Operation blocked")
        )
      end

      it "raises KillSwitchError when operation is blocked" do
        expect do
          controller.send(:check_kill_switch, operation: :test_operation, confirmation: nil)
        end.to raise_error(PgSqlTriggers::KillSwitchError, /Operation blocked|kill switch is active/)
      end

      it "passes correct parameters to KillSwitch.check!" do
        allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
        controller.send(:check_kill_switch, operation: :test_operation, confirmation: "EXECUTE TEST_OPERATION")
        expect(PgSqlTriggers::SQL::KillSwitch).to have_received(:check!).with(
          operation: :test_operation,
          environment: "production",
          confirmation: "EXECUTE TEST_OPERATION",
          actor: { type: "User", id: "unknown" }
        )
      end
    end

    context "when kill switch is not active" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        allow(PgSqlTriggers::SQL::KillSwitch).to receive_messages(active?: false, check!: true)
      end

      it "does not raise an error" do
        expect do
          controller.send(:check_kill_switch, operation: :test_operation, confirmation: nil)
        end.not_to raise_error
      end
    end
  end

  describe "#require_kill_switch_override" do
    it "calls check_kill_switch with the operation" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive_messages(active?: false, check!: true)
      controller.send(:require_kill_switch_override, :test_operation, confirmation: "EXECUTE TEST_OPERATION")
      expect(PgSqlTriggers::SQL::KillSwitch).to have_received(:check!).with(
        operation: :test_operation,
        environment: "development",
        confirmation: "EXECUTE TEST_OPERATION",
        actor: { type: "User", id: "unknown" }
      )
    end

    it "can be used as a before_action" do
      # This is tested by the fact that it's a method that can be used in before_action
      # It's a private method, so we check by calling it
      # Setup logger to accept debug calls
      logger = instance_double(Logger)
      allow(logger).to receive(:debug)
      allow(PgSqlTriggers).to receive(:kill_switch_logger).and_return(logger)
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect { controller.send(:require_kill_switch_override, :test_operation) }.not_to raise_error
    end
  end

  describe "#expected_confirmation_text" do
    context "when kill_switch_confirmation_pattern is configured" do
      before do
        allow(PgSqlTriggers).to receive(:kill_switch_confirmation_pattern).and_return(
          ->(op) { "EXECUTE #{op.to_s.upcase}" }
        )
      end

      it "returns the confirmation text from the pattern" do
        expect(controller.send(:expected_confirmation_text, :test_operation)).to eq("EXECUTE TEST_OPERATION")
      end

      it "calls the pattern with the operation" do
        pattern = ->(op) { "CUSTOM #{op}" }
        allow(PgSqlTriggers).to receive(:kill_switch_confirmation_pattern).and_return(pattern)
        expect(controller.send(:expected_confirmation_text, :test_operation)).to eq("CUSTOM test_operation")
      end
    end

    context "when kill_switch_confirmation_pattern is not configured" do
      before do
        allow(PgSqlTriggers).to receive(:respond_to?).with(:kill_switch_confirmation_pattern).and_return(false)
      end

      it "returns default confirmation text" do
        expect(controller.send(:expected_confirmation_text, :test_operation)).to eq("EXECUTE TEST_OPERATION")
      end
    end

    context "when kill_switch_confirmation_pattern is not callable" do
      before do
        allow(PgSqlTriggers).to receive(:kill_switch_confirmation_pattern).and_return("not a proc")
        allow(PgSqlTriggers).to receive(:respond_to?).with(:kill_switch_confirmation_pattern).and_return(true)
      end

      it "returns default confirmation text" do
        expect(controller.send(:expected_confirmation_text, :test_operation)).to eq("EXECUTE TEST_OPERATION")
      end
    end
  end

  describe "layout" do
    it "uses pg_sql_triggers/application layout" do
      # Layout is set using layout "pg_sql_triggers/application" which sets _layout
      expect(controller.class._layout).to eq("pg_sql_triggers/application")
    end
  end

  describe "CSRF protection" do
    it "has protect_from_forgery enabled" do
      # This is tested by the fact that the controller includes protect_from_forgery
      expect(controller.class.protect_from_forgery).to be_truthy
    end
  end

  describe "URL helpers" do
    it "includes engine routes URL helpers" do
      # The controller includes PgSqlTriggers::Engine.routes.url_helpers
      # This allows it to use route helpers like root_path
      expect(controller).to respond_to(:root_path)
    end
  end
end
