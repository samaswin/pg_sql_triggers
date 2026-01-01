# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::SqlCapsulesController, type: :controller do
  routes { PgSqlTriggers::Engine.routes }

  let(:actor) { { type: "User", id: 1 } }

  before do
    # Stub current_actor
    allow(controller).to receive(:current_actor).and_return(actor)
    # Stub logger
    allow(Rails.logger).to receive(:error)
    # Allow all permissions by default
    allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
    # Stub kill switch
    allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
  end

  describe "GET #new" do
    context "with operator permissions" do
      it "renders the new template" do
        get :new
        expect(response).to have_http_status(:success)
        expect(response).to render_template(:new)
      end

      it "initializes empty form fields" do
        get :new
        expect(assigns(:capsule_name)).to eq("")
        expect(assigns(:environment)).to be_present
        expect(assigns(:purpose)).to eq("")
        expect(assigns(:sql)).to eq("")
      end

      it "accepts pre-filled parameters" do
        get :new, params: {
          name: "fix_users",
          environment: "production",
          purpose: "Fix user permissions",
          sql: "UPDATE users SET role = 'admin';"
        }

        expect(assigns(:capsule_name)).to eq("fix_users")
        expect(assigns(:environment)).to eq("production")
        expect(assigns(:purpose)).to eq("Fix user permissions")
        expect(assigns(:sql)).to eq("UPDATE users SET role = 'admin';")
      end

      it "defaults environment to current_environment" do
        allow(controller).to receive(:current_environment).and_return("staging")
        get :new

        expect(assigns(:environment)).to eq("staging")
      end
    end

    context "without operator permissions" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :generate_trigger)
          .and_return(false)
      end

      it "redirects to dashboard" do
        get :new
        expect(response).to redirect_to(dashboard_path)
      end

      it "sets permission denied alert" do
        get :new
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Operator role required")
      end
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        name: "fix_permissions",
        environment: "production",
        purpose: "Emergency fix for user permissions",
        sql: "UPDATE users SET role = 'admin' WHERE email = 'admin@example.com';"
      }
    end

    context "with valid parameters" do
      it "creates a new capsule in registry" do
        expect do
          post :create, params: valid_params
        end.to change(PgSqlTriggers::TriggerRegistry, :count).by(1)
      end

      it "saves capsule with correct attributes" do
        post :create, params: valid_params

        capsule = PgSqlTriggers::TriggerRegistry.last
        expect(capsule.trigger_name).to eq("sql_capsule_fix_permissions")
        expect(capsule.source).to eq("manual_sql")
        expect(capsule.table_name).to eq("manual_sql_execution")
        expect(capsule.function_body).to eq(valid_params[:sql])
        expect(capsule.condition).to eq(valid_params[:purpose])
        expect(capsule.environment).to eq("production")
        expect(capsule.enabled).to be false
      end

      it "calculates and stores checksum" do
        post :create, params: valid_params

        capsule = PgSqlTriggers::TriggerRegistry.last
        expected_checksum = Digest::SHA256.hexdigest(valid_params[:sql])
        expect(capsule.checksum).to eq(expected_checksum)
      end

      it "redirects to show page" do
        post :create, params: valid_params
        expect(response).to redirect_to(sql_capsule_path(id: "fix_permissions"))
      end

      it "sets success notice" do
        post :create, params: valid_params
        expect(flash[:notice]).to match(/created successfully/)
        expect(flash[:notice]).to include("fix_permissions")
      end
    end

    context "with invalid parameters" do
      it "renders new template on validation error" do
        post :create, params: valid_params.merge(name: "")

        expect(response).to render_template(:new)
        expect(flash.now[:alert]).to match(/Invalid capsule/)
      end

      it "preserves form values on error" do
        post :create, params: valid_params.merge(name: "")

        expect(assigns(:capsule_name)).to eq("")
        expect(assigns(:environment)).to eq("production")
        expect(assigns(:purpose)).to eq(valid_params[:purpose])
        expect(assigns(:sql)).to eq(valid_params[:sql])
      end

      it "handles ArgumentError from Capsule validation" do
        post :create, params: valid_params.merge(name: "invalid name!")

        expect(response).to render_template(:new)
        expect(flash.now[:alert]).to match(/Invalid capsule/)
      end
    end

    context "when capsule name already exists" do
      before do
        create(:trigger_registry, :disabled, :manual_sql_source, :production,
               trigger_name: "sql_capsule_fix_permissions",
               table_name: "manual_sql_execution",
               checksum: "abc123",
               function_body: "SELECT 1;",
               condition: "test")
      end

      it "does not create duplicate capsule" do
        expect do
          post :create, params: valid_params
        end.not_to change(PgSqlTriggers::TriggerRegistry, :count)
      end

      it "renders new template with error" do
        post :create, params: valid_params

        expect(response).to render_template(:new)
        expect(flash.now[:alert]).to match(/already exists/)
      end
    end

    context "when save fails" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:save).and_return(false)
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:errors).and_return(
          double("Errors", full_messages: ["Version can't be blank"])
        )
      end

      it "renders new template with error" do
        post :create, params: valid_params

        expect(response).to render_template(:new)
        expect(flash.now[:alert]).to match(/Failed to save capsule/)
      end
    end

    context "without operator permissions" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :generate_trigger)
          .and_return(false)
      end

      it "redirects to dashboard" do
        post :create, params: valid_params
        expect(response).to redirect_to(dashboard_path)
      end

      it "does not create capsule" do
        expect do
          post :create, params: valid_params
        end.not_to change(PgSqlTriggers::TriggerRegistry, :count)
      end
    end
  end

  describe "GET #show" do
    let!(:capsule_entry) do
      create(:trigger_registry, :disabled, :manual_sql_source, :production,
             trigger_name: "sql_capsule_test",
             table_name: "manual_sql_execution",
             version: Time.current.to_i,
             checksum: "abc123",
             function_body: "SELECT 1;",
             condition: "Test capsule")
    end

    context "when capsule exists" do
      it "renders show template" do
        get :show, params: { id: "test" }
        expect(response).to have_http_status(:success)
        expect(response).to render_template(:show)
      end

      it "loads the capsule" do
        get :show, params: { id: "test" }
        expect(assigns(:capsule)).to be_present
        expect(assigns(:capsule).name).to eq("test")
      end

      it "calculates checksum" do
        get :show, params: { id: "test" }
        expect(assigns(:checksum)).to eq(Digest::SHA256.hexdigest("SELECT 1;"))
      end

      it "sets can_execute flag based on permissions" do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql)
          .and_return(true)

        get :show, params: { id: "test" }
        expect(assigns(:can_execute)).to be true
      end

      it "sets can_execute to false without admin permissions" do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql)
          .and_return(false)

        get :show, params: { id: "test" }
        expect(assigns(:can_execute)).to be false
      end
    end

    context "when capsule does not exist" do
      it "redirects to new capsule path" do
        get :show, params: { id: "nonexistent" }
        expect(response).to redirect_to(new_sql_capsule_path)
      end

      it "sets not found alert" do
        get :show, params: { id: "nonexistent" }
        expect(flash[:alert]).to eq("Capsule not found")
      end
    end

    context "without operator permissions" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :generate_trigger)
          .and_return(false)
      end

      it "redirects to dashboard" do
        get :show, params: { id: "test" }
        expect(response).to redirect_to(dashboard_path)
      end
    end
  end

  describe "POST #execute" do
    let!(:capsule_entry) do
      create(:trigger_registry, :disabled, :manual_sql_source, :production,
             trigger_name: "sql_capsule_test",
             table_name: "manual_sql_execution",
             version: Time.current.to_i,
             checksum: "abc123",
             function_body: "SELECT 1 AS result;",
             condition: "Test capsule")
    end

    context "with admin permissions" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql)
          .and_return(true)
      end

      context "when execution succeeds" do
        before do
          allow(PgSqlTriggers::SQL::Executor).to receive(:execute).and_return(
            success: true,
            message: "SQL executed successfully"
          )
        end

        it "executes the capsule" do
          expect(PgSqlTriggers::SQL::Executor).to receive(:execute)

          post :execute, params: { id: "test" }
        end

        it "passes confirmation to executor" do
          expect(PgSqlTriggers::SQL::Executor).to receive(:execute).with(
            anything,
            hash_including(confirmation: "EXECUTE SQL")
          )

          post :execute, params: { id: "test", confirmation: "EXECUTE SQL" }
        end

        it "redirects to show page" do
          post :execute, params: { id: "test" }
          expect(response).to redirect_to(sql_capsule_path(id: "test"))
        end

        it "sets success notice" do
          post :execute, params: { id: "test" }
          expect(flash[:notice]).to match(/executed successfully/)
        end
      end

      context "when execution fails" do
        before do
          allow(PgSqlTriggers::SQL::Executor).to receive(:execute).and_return(
            success: false,
            message: "SQL execution failed"
          )
        end

        it "redirects to show page" do
          post :execute, params: { id: "test" }
          expect(response).to redirect_to(sql_capsule_path(id: "test"))
        end

        it "sets error alert" do
          post :execute, params: { id: "test" }
          expect(flash[:alert]).to eq("SQL execution failed")
        end
      end

      context "when kill switch blocks execution" do
        before do
          allow(controller).to receive(:check_kill_switch)
            .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch active"))
        end

        it "redirects to show page" do
          post :execute, params: { id: "test" }
          expect(response).to redirect_to(sql_capsule_path(id: "test"))
        end

        it "sets kill switch alert" do
          post :execute, params: { id: "test" }
          expect(flash[:alert]).to match(/Kill switch blocked execution/)
        end

        it "does not execute capsule" do
          expect(PgSqlTriggers::SQL::Executor).not_to receive(:execute)
          post :execute, params: { id: "test" }
        end
      end

      context "when permission error occurs during execution" do
        before do
          allow(PgSqlTriggers::SQL::Executor).to receive(:execute)
            .and_raise(PgSqlTriggers::PermissionError.new("Admin role required"))
        end

        it "redirects to show page" do
          post :execute, params: { id: "test" }
          expect(response).to redirect_to(sql_capsule_path(id: "test"))
        end

        it "sets permission denied alert" do
          post :execute, params: { id: "test" }
          expect(flash[:alert]).to match(/Permission denied/)
        end
      end

      context "when standard error occurs" do
        before do
          allow(PgSqlTriggers::SQL::Executor).to receive(:execute)
            .and_raise(StandardError.new("Unexpected error"))
        end

        it "redirects to show page" do
          post :execute, params: { id: "test" }
          expect(response).to redirect_to(sql_capsule_path(id: "test"))
        end

        it "sets error alert" do
          post :execute, params: { id: "test" }
          expect(flash[:alert]).to match(/Execution failed/)
          expect(flash[:alert]).to include("Unexpected error")
        end

        it "logs the error" do
          expect(Rails.logger).to receive(:error).with(/SQL Capsule execution failed/)
          post :execute, params: { id: "test" }
        end
      end
    end

    context "when capsule does not exist" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql)
          .and_return(true)
      end

      it "redirects to new capsule path" do
        post :execute, params: { id: "nonexistent" }
        expect(response).to redirect_to(new_sql_capsule_path)
      end

      it "sets not found alert" do
        post :execute, params: { id: "nonexistent" }
        expect(flash[:alert]).to eq("Capsule not found")
      end

      it "does not execute capsule" do
        expect(PgSqlTriggers::SQL::Executor).not_to receive(:execute)
        post :execute, params: { id: "nonexistent" }
      end
    end

    context "without admin permissions" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql)
          .and_return(false)
      end

      it "redirects to dashboard" do
        post :execute, params: { id: "test" }
        expect(response).to redirect_to(dashboard_path)
      end

      it "sets permission denied alert" do
        post :execute, params: { id: "test" }
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Admin role required")
      end

      it "does not execute capsule" do
        expect(PgSqlTriggers::SQL::Executor).not_to receive(:execute)
        post :execute, params: { id: "test" }
      end
    end
  end

  describe "permission checks" do
    describe "#check_admin_permission" do
      it "allows action when user has admin permission" do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql)
          .and_return(true)

        get :show, params: { id: "test" }
        expect(response).not_to redirect_to(dashboard_path)
      end

      it "blocks action when user lacks admin permission" do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql)
          .and_return(false)

        # Execute action requires admin permission
        post :execute, params: { id: "test" }
        expect(response).to redirect_to(dashboard_path)
      end
    end

    describe "#check_operator_permission" do
      it "allows action when user has operator permission" do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :generate_trigger)
          .and_return(true)

        get :new
        expect(response).not_to redirect_to(dashboard_path)
      end

      it "blocks action when user lacks operator permission" do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :generate_trigger)
          .and_return(false)

        get :new
        expect(response).to redirect_to(dashboard_path)
      end
    end
  end

  describe "private methods" do
    describe "#build_capsule_from_params" do
      it "strips whitespace from parameters" do
        post :create, params: {
          name: "  test  ",
          environment: "  production  ",
          purpose: "  test purpose  ",
          sql: "  SELECT 1;  "
        }

        # The controller should strip whitespace before creating the capsule
        # If it fails validation, the stripped values should be preserved
        expect(assigns(:capsule_name)).to eq("test")
        expect(assigns(:environment)).to eq("production")
        expect(assigns(:purpose)).to eq("test purpose")
        expect(assigns(:sql)).to eq("SELECT 1;")
      end
    end

    describe "#can_execute_capsule?" do
      let!(:capsule_entry) do
        create(:trigger_registry, :disabled, :manual_sql_source, :production,
               trigger_name: "sql_capsule_test",
               table_name: "manual_sql_execution",
               version: Time.current.to_i,
               checksum: "abc123",
               function_body: "SELECT 1;",
               condition: "Test capsule")
      end

      it "returns true when user has execute_sql permission" do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql)
          .and_return(true)
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :generate_trigger)
          .and_return(true)

        get :show, params: { id: "test" }
        expect(assigns(:can_execute)).to be true
      end

      it "returns false when user lacks execute_sql permission" do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql)
          .and_return(false)

        # Need to bypass admin permission check for show action
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :generate_trigger)
          .and_return(true)

        get :show, params: { id: "test" }
        expect(assigns(:can_execute)).to be false
      end
    end
  end
end
