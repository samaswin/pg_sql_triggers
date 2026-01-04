# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Permission checks across controllers", type: :controller do
  let(:trigger) do
    create(:trigger_registry, :enabled, :dsl_source,
           trigger_name: "test_trigger",
           table_name: "test_table",
           checksum: "abc123")
  end

  before do
    # Configure view paths
    engine_view_path = PgSqlTriggers::Engine.root.join("app/views").to_s
    controller.prepend_view_path(engine_view_path) if controller.respond_to?(:prepend_view_path)
    allow(Rails.logger).to receive(:error)
  end

  describe PgSqlTriggers::TriggersController, type: :controller do
    routes { PgSqlTriggers::Engine.routes }

    describe "viewer permissions" do
      context "when user has viewer permission" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
          allow_any_instance_of(PgSqlTriggers::Drift::Reporter).to receive(:summary).and_return({ triggers: [] })
        end

        it "allows access to show action" do
          get :show, params: { id: trigger.id }
          expect(response).to have_http_status(:success)
          expect(flash[:alert]).to be_nil
        end
      end

      context "when user lacks viewer permission" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)
        end

        it "blocks access to show action" do
          get :show, params: { id: trigger.id }
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to match(/Insufficient permissions/)
          expect(flash[:alert]).to include("Viewer role required")
        end
      end
    end

    describe "operator permissions" do
      context "when user has operator permission" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
          allow_any_instance_of(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
          allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!).and_return(true)
          allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:disable!).and_return(true)
        end

        it "allows access to enable action" do
          post :enable, params: { id: trigger.id }
          expect(flash[:alert]).to be_nil
          expect(flash[:success]).to be_present
        end

        it "allows access to disable action" do
          post :disable, params: { id: trigger.id }
          expect(flash[:alert]).to be_nil
          expect(flash[:success]).to be_present
        end
      end

      context "when user lacks operator permission" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?) do |_actor, action, _options|
            action == :view_triggers
          end
        end

        it "blocks access to enable action" do
          post :enable, params: { id: trigger.id }
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to match(/Insufficient permissions/)
          expect(flash[:alert]).to include("Operator role required")
        end

        it "blocks access to disable action" do
          post :disable, params: { id: trigger.id }
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to match(/Insufficient permissions/)
          expect(flash[:alert]).to include("Operator role required")
        end
      end
    end

    describe "admin permissions" do
      context "when user has admin permission" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
          allow_any_instance_of(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
          allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:drop!).and_return(true)
          allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:re_execute!).and_return(true)
        end

        it "allows access to drop action" do
          post :drop, params: { id: trigger.id, reason: "Test reason" }
          expect(flash[:alert]).to be_nil
          expect(flash[:success]).to be_present
        end

        it "allows access to re_execute action" do
          post :re_execute, params: { id: trigger.id, reason: "Test reason" }
          expect(flash[:alert]).to be_nil
          expect(flash[:success]).to be_present
        end
      end

      context "when user lacks admin permission" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:can?) do |_actor, action, _options|
            action == :view_triggers
          end
        end

        it "blocks access to drop action" do
          post :drop, params: { id: trigger.id, reason: "Test reason" }
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to match(/Insufficient permissions/)
          expect(flash[:alert]).to include("Admin role required")
        end

        it "blocks access to re_execute action" do
          post :re_execute, params: { id: trigger.id, reason: "Test reason" }
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to match(/Insufficient permissions/)
          expect(flash[:alert]).to include("Admin role required")
        end
      end
    end
  end

  describe PgSqlTriggers::AuditLogsController, type: :controller do
    routes { PgSqlTriggers::Engine.routes }

    context "when user has viewer permission" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
      end

      it "allows access to index action" do
        get :index
        expect(response).to have_http_status(:success)
        expect(flash[:alert]).to be_nil
      end
    end

    context "when user lacks viewer permission" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)
      end

      it "blocks access to index action" do
        get :index
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Viewer role required")
      end
    end
  end

  describe PgSqlTriggers::DashboardController, type: :controller do
    routes { PgSqlTriggers::Engine.routes }

    context "when user has viewer permission" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
      end

      it "allows access to index action" do
        get :index
        expect(response).to have_http_status(:success)
        expect(flash[:alert]).to be_nil
      end
    end

    context "when user lacks viewer permission" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)
      end

      it "blocks access to index action" do
        get :index
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Viewer role required")
      end
    end
  end

  describe "permission checking with environment context", type: :controller do
    routes { PgSqlTriggers::Engine.routes }

    controller(PgSqlTriggers::TriggersController) do
      # Keep controller() here since we're testing environment context specifically
    end

    before do
      allow_any_instance_of(PgSqlTriggers::Drift::Reporter).to receive(:summary).and_return({ triggers: [] })
    end

    it "passes environment to permission checker" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)

      get :show, params: { id: trigger.id }

      expect(PgSqlTriggers::Permissions).to have_received(:can?).with(
        anything,
        :view_triggers,
        hash_including(environment: "production")
      )
    end

    it "passes current_actor to permission checker" do
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)

      get :show, params: { id: trigger.id }

      expect(PgSqlTriggers::Permissions).to have_received(:can?).with(
        hash_including(type: "User", id: "unknown"),
        :view_triggers,
        anything
      )
    end
  end

  describe "permission error handling", type: :controller do
    routes { PgSqlTriggers::Engine.routes }

    controller(PgSqlTriggers::TriggersController) do
      # Keep controller() here since we're testing error handling specifically
    end

    context "when permission check raises an error" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_raise(StandardError.new("Permission system error"))
        allow(Rails.logger).to receive(:error)
      end

      it "handles the error gracefully" do
        expect do
          get :show, params: { id: trigger.id }
        end.not_to raise_error
      end
    end
  end
end
