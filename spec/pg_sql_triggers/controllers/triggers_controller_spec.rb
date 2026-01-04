# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::TriggersController, type: :controller do
  routes { PgSqlTriggers::Engine.routes }

  let(:trigger) do
    create(:trigger_registry, :enabled, :dsl_source,
           trigger_name: "test_trigger",
           table_name: "test_table",
           checksum: "abc123")
  end

  before do
    allow(Rails.logger).to receive(:error)
    # Allow permissions by default
    allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
  end

  describe "POST #enable" do
    let(:disabled_trigger) do
      create(:trigger_registry, :disabled, :dsl_source,
             trigger_name: "disabled_trigger",
             table_name: "test_table",
             checksum: "def456")
    end

    context "when trigger is successfully enabled" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!).and_return(true)
      end

      it "enables the trigger" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!).with(
          hash_including(confirmation: nil, actor: { type: "User", id: "unknown" })
        )
        post :enable, params: { id: disabled_trigger.id }
      end

      it "passes confirmation text to enable!" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:enable!)
          .with(hash_including(confirmation: "EXECUTE TRIGGER_ENABLE", actor: { type: "User", id: "unknown" }))
        post :enable, params: { id: disabled_trigger.id, confirmation_text: "EXECUTE TRIGGER_ENABLE" }
      end

      it "sets success flash message" do
        post :enable, params: { id: disabled_trigger.id }
        expect(flash[:success]).to match(/enabled successfully/)
        expect(flash[:success]).to include(disabled_trigger.trigger_name)
      end

      it "redirects to root path by default" do
        post :enable, params: { id: disabled_trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to specified path when redirect_to param present" do
        post :enable, params: { id: disabled_trigger.id, redirect_to: "/custom/path" }
        expect(response).to redirect_to("/custom/path")
      end
    end

    context "when trigger is not found" do
      it "sets error flash and redirects" do
        post :enable, params: { id: 99_999 }
        expect(flash[:error]).to eq("Trigger not found.")
        expect(response).to redirect_to(root_path)
      end
    end

    context "when enable fails" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:enable!)
          .and_raise(StandardError.new("Database connection failed"))
      end

      it "sets error flash with failure message" do
        post :enable, params: { id: disabled_trigger.id }
        expect(flash[:error]).to match(/Failed to enable trigger/)
        expect(flash[:error]).to include("Database connection failed")
      end

      it "logs the error" do
        post :enable, params: { id: disabled_trigger.id }
        expect(Rails.logger).to have_received(:error).with(/Enable failed/)
      end

      it "redirects to root path" do
        post :enable, params: { id: disabled_trigger.id }
        expect(response).to redirect_to(root_path)
      end
    end

    context "when kill switch blocks operation" do
      before do
        allow_any_instance_of(described_class)
          .to receive(:check_kill_switch)
          .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch is active"))
      end

      it "sets error flash with kill switch message" do
        post :enable, params: { id: disabled_trigger.id }
        expect(flash[:error]).to eq("Kill switch is active")
      end

      it "redirects to root path" do
        post :enable, params: { id: disabled_trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to custom path if provided" do
        post :enable, params: { id: disabled_trigger.id, redirect_to: "/custom/path" }
        expect(response).to redirect_to("/custom/path")
      end
    end
  end

  describe "POST #disable" do
    context "when trigger is successfully disabled" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:disable!).and_return(true)
      end

      it "disables the trigger" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:disable!).with(
          hash_including(confirmation: nil, actor: { type: "User", id: "unknown" })
        )
        post :disable, params: { id: trigger.id }
      end

      it "passes confirmation text to disable!" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:disable!)
          .with(hash_including(confirmation: "EXECUTE TRIGGER_DISABLE", actor: { type: "User", id: "unknown" }))
        post :disable, params: { id: trigger.id, confirmation_text: "EXECUTE TRIGGER_DISABLE" }
      end

      it "sets success flash message" do
        post :disable, params: { id: trigger.id }
        expect(flash[:success]).to match(/disabled successfully/)
        expect(flash[:success]).to include(trigger.trigger_name)
      end

      it "redirects to root path by default" do
        post :disable, params: { id: trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to specified path when redirect_to param present" do
        post :disable, params: { id: trigger.id, redirect_to: "/custom/path" }
        expect(response).to redirect_to("/custom/path")
      end
    end

    context "when trigger is not found" do
      it "sets error flash and redirects" do
        post :disable, params: { id: 99_999 }
        expect(flash[:error]).to eq("Trigger not found.")
        expect(response).to redirect_to(root_path)
      end
    end

    context "when disable fails" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:disable!)
          .and_raise(StandardError.new("Permission denied"))
      end

      it "sets error flash with failure message" do
        post :disable, params: { id: trigger.id }
        expect(flash[:error]).to match(/Failed to disable trigger/)
        expect(flash[:error]).to include("Permission denied")
      end

      it "logs the error" do
        post :disable, params: { id: trigger.id }
        expect(Rails.logger).to have_received(:error).with(/Disable failed/)
      end

      it "redirects to root path" do
        post :disable, params: { id: trigger.id }
        expect(response).to redirect_to(root_path)
      end
    end

    context "when kill switch blocks operation" do
      before do
        allow_any_instance_of(described_class)
          .to receive(:check_kill_switch)
          .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch is active"))
      end

      it "sets error flash with kill switch message" do
        post :disable, params: { id: trigger.id }
        expect(flash[:error]).to eq("Kill switch is active")
      end

      it "redirects to root path" do
        post :disable, params: { id: trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to custom path if provided" do
        post :disable, params: { id: trigger.id, redirect_to: "/custom/path" }
        expect(response).to redirect_to("/custom/path")
      end
    end
  end

  describe "permission checks" do
    context "when user lacks permissions" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?) do |_actor, action, _options|
          action != :enable_trigger
        end
      end

      it "blocks enable action" do
        post :enable, params: { id: trigger.id }
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Operator role required")
        expect(response).to redirect_to(root_path)
      end

      it "blocks disable action" do
        allow(PgSqlTriggers::Permissions).to receive(:can?) do |_actor, action, _options|
          action != :enable_trigger
        end
        post :disable, params: { id: trigger.id }
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Operator role required")
        expect(response).to redirect_to(root_path)
      end

      it "does not call enable! when permission is denied" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:enable!)
        post :enable, params: { id: trigger.id }
      end

      it "does not call disable! when permission is denied" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:disable!)
        post :disable, params: { id: trigger.id }
      end
    end

    context "when user has permissions" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).with(anything, :enable_trigger).and_return(true)
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!).and_return(true)
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:disable!).and_return(true)
      end

      it "allows enable action" do
        post :enable, params: { id: trigger.id }
        expect(flash[:alert]).to be_nil
        expect(flash[:success]).to be_present
      end

      it "allows disable action" do
        post :disable, params: { id: trigger.id }
        expect(flash[:alert]).to be_nil
        expect(flash[:success]).to be_present
      end
    end
  end

  describe "redirect behavior" do
    before do
      allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!).and_return(true)
    end

    it "uses redirect_to param if present" do
      post :enable, params: { id: trigger.id, redirect_to: "/tables/test_table" }
      expect(response).to redirect_to("/tables/test_table")
    end

    it "falls back to referer if no redirect_to" do
      request.env["HTTP_REFERER"] = "/tables/test_table"
      post :enable, params: { id: trigger.id }
      expect(response).to redirect_to("/tables/test_table")
    end

    it "falls back to root if no redirect_to or referer" do
      post :enable, params: { id: trigger.id }
      expect(response).to redirect_to(root_path)
    end
  end

  describe "error handling hierarchy" do
    it "handles KillSwitchError before StandardError" do
      allow_any_instance_of(described_class)
        .to receive(:check_kill_switch)
        .and_raise(PgSqlTriggers::KillSwitchError.new("Blocked"))

      post :enable, params: { id: trigger.id }
      expect(flash[:error]).to eq("Blocked")
      expect(Rails.logger).not_to have_received(:error)
    end

    it "handles StandardError when operation fails" do
      allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
        .to receive(:enable!)
        .and_raise(StandardError.new("Generic error"))

      post :enable, params: { id: trigger.id }
      expect(flash[:error]).to match(/Failed to enable trigger/)
      expect(Rails.logger).to have_received(:error)
    end

    it "handles RecordNotFound before action execution" do
      post :enable, params: { id: 99_999 }
      expect(flash[:error]).to eq("Trigger not found.")
      expect(Rails.logger).not_to have_received(:error)
    end
  end

  describe "GET #show" do
    before do
      allow(PgSqlTriggers::Permissions).to receive(:can?).with(anything, :view_triggers).and_return(true)
    end

    context "when trigger exists" do
      it "loads the trigger" do
        get :show, params: { id: trigger.id }
        expect(assigns(:trigger)).to eq(trigger)
      end

      it "calculates drift information" do
        get :show, params: { id: trigger.id }
        expect(assigns(:drift_info)).to be_a(Hash)
        expect(assigns(:drift_info)).to have_key(:has_drift)
        expect(assigns(:drift_info)).to have_key(:drift_type)
      end

      it "includes expected_sql and actual_sql in drift_info" do
        get :show, params: { id: trigger.id }
        expect(assigns(:drift_info)).to have_key(:expected_sql)
        expect(assigns(:drift_info)).to have_key(:actual_sql)
      end

      it "renders the show template" do
        get :show, params: { id: trigger.id }
        expect(response).to render_template(:show)
      end

      it "returns successful response" do
        get :show, params: { id: trigger.id }
        expect(response).to have_http_status(:success)
      end

      context "when trigger has drift" do
        before do
          drift_summary = {
            triggers: [
              {
                trigger_name: trigger.trigger_name,
                drift_type: "checksum_mismatch",
                expected_sql: "CREATE FUNCTION...",
                actual_sql: "CREATE FUNCTION..."
              }
            ]
          }
          allow_any_instance_of(PgSqlTriggers::Drift::Reporter).to receive(:summary).and_return(drift_summary)
        end

        it "detects drift" do
          get :show, params: { id: trigger.id }
          expect(assigns(:drift_info)[:has_drift]).to be true
          expect(assigns(:drift_info)[:drift_type]).to eq("checksum_mismatch")
        end

        it "includes expected and actual SQL" do
          get :show, params: { id: trigger.id }
          expect(assigns(:drift_info)[:expected_sql]).to be_present
          expect(assigns(:drift_info)[:actual_sql]).to be_present
        end
      end

      context "when trigger is in sync" do
        before do
          drift_summary = {
            triggers: []
          }
          allow_any_instance_of(PgSqlTriggers::Drift::Reporter).to receive(:summary).and_return(drift_summary)
        end

        it "shows no drift" do
          get :show, params: { id: trigger.id }
          expect(assigns(:drift_info)[:has_drift]).to be false
        end
      end
    end

    context "when trigger does not exist" do
      it "sets error flash and redirects" do
        get :show, params: { id: 99_999 }
        expect(flash[:error]).to eq("Trigger not found.")
        expect(response).to redirect_to(root_path)
      end

      it "does not attempt to calculate drift" do
        expect_any_instance_of(PgSqlTriggers::Drift::Reporter).not_to receive(:summary)
        get :show, params: { id: 99_999 }
      end
    end

    context "when user lacks view permission" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?) do |_actor, action, _options|
          action != :view_triggers
        end
      end

      it "redirects to root with alert" do
        get :show, params: { id: trigger.id }
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Viewer role required")
        expect(response).to redirect_to(root_path)
      end

      it "does not load the trigger" do
        get :show, params: { id: trigger.id }
        expect(assigns(:trigger)).to be_nil
      end

      it "does not calculate drift" do
        expect_any_instance_of(PgSqlTriggers::Drift::Reporter).not_to receive(:summary)
        get :show, params: { id: trigger.id }
      end
    end

    context "when drift calculation fails" do
      before do
        allow(Rails.logger).to receive(:error)
        allow_any_instance_of(PgSqlTriggers::Drift::Reporter).to receive(:summary).and_raise(StandardError.new("DB error"))
      end

      it "returns default drift info" do
        get :show, params: { id: trigger.id }
        expect(assigns(:drift_info)).to eq({ has_drift: false, drift_type: nil, expected_sql: nil, actual_sql: nil })
      end

      it "logs the error" do
        get :show, params: { id: trigger.id }
        expect(Rails.logger).to have_received(:error).with(/Failed to calculate drift/)
      end

      it "still renders the show template" do
        get :show, params: { id: trigger.id }
        expect(response).to render_template(:show)
      end
    end
  end

  describe "POST #drop" do
    before do
      allow(PgSqlTriggers::Permissions).to receive(:can?).with(anything, :drop_trigger).and_return(true)
    end

    context "when drop is successful" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:drop!).and_return(true)
      end

      it "drops the trigger with reason" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:drop!).with(
          reason: "No longer needed",
          confirmation: nil,
          actor: anything
        )
        post :drop, params: { id: trigger.id, reason: "No longer needed" }
      end

      it "passes confirmation text" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:drop!).with(
          reason: "Test reason",
          confirmation: "EXECUTE DROP",
          actor: anything
        )
        post :drop, params: { id: trigger.id, reason: "Test reason", confirmation_text: "EXECUTE DROP" }
      end

      it "sets success flash message" do
        post :drop, params: { id: trigger.id, reason: "No longer needed" }
        expect(flash[:success]).to match(/dropped successfully/)
        expect(flash[:success]).to include(trigger.trigger_name)
      end

      it "redirects to dashboard" do
        post :drop, params: { id: trigger.id, reason: "No longer needed" }
        expect(response).to redirect_to(dashboard_path)
      end
    end

    context "when reason is missing" do
      it "sets error flash" do
        post :drop, params: { id: trigger.id }
        expect(flash[:error]).to eq("Reason is required for dropping a trigger.")
      end

      it "redirects to root path" do
        post :drop, params: { id: trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "does not call drop!" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:drop!)
        post :drop, params: { id: trigger.id }
      end
    end

    context "when reason is blank" do
      it "sets error flash" do
        post :drop, params: { id: trigger.id, reason: "   " }
        expect(flash[:error]).to eq("Reason is required for dropping a trigger.")
      end
    end

    context "when kill switch blocks operation" do
      before do
        allow_any_instance_of(described_class)
          .to receive(:check_kill_switch)
          .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch active"))
      end

      it "sets error flash" do
        post :drop, params: { id: trigger.id, reason: "Test" }
        expect(flash[:error]).to eq("Kill switch active")
      end

      it "redirects to root path" do
        post :drop, params: { id: trigger.id, reason: "Test" }
        expect(response).to redirect_to(root_path)
      end
    end

    context "when drop raises ArgumentError" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:drop!)
          .and_raise(ArgumentError.new("Invalid argument"))
      end

      it "sets error flash with ArgumentError message" do
        post :drop, params: { id: trigger.id, reason: "Test" }
        expect(flash[:error]).to match(/Invalid request/)
        expect(flash[:error]).to include("Invalid argument")
      end
    end

    context "when drop fails with StandardError" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:drop!)
          .and_raise(StandardError.new("Database error"))
      end

      it "sets error flash" do
        post :drop, params: { id: trigger.id, reason: "Test" }
        expect(flash[:error]).to match(/Failed to drop trigger/)
        expect(flash[:error]).to include("Database error")
      end

      it "logs the error" do
        post :drop, params: { id: trigger.id, reason: "Test" }
        expect(Rails.logger).to have_received(:error).with(/Drop failed/)
      end
    end

    context "when user lacks drop permission" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?) do |_actor, action, _options|
          action != :drop_trigger
        end
      end

      it "redirects to root with alert" do
        post :drop, params: { id: trigger.id, reason: "Test" }
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Admin role required")
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST #re_execute" do
    before do
      allow(PgSqlTriggers::Permissions).to receive(:can?).with(anything, :drop_trigger).and_return(true)
      trigger.update!(function_body: "CREATE FUNCTION test() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
    end

    context "when re-execute is successful" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:re_execute!).and_return(true)
      end

      it "re-executes the trigger with reason" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:re_execute!).with(
          reason: "Fixing drift",
          confirmation: nil,
          actor: anything
        )
        post :re_execute, params: { id: trigger.id, reason: "Fixing drift" }
      end

      it "passes confirmation text" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:re_execute!).with(
          reason: "Test reason",
          confirmation: "EXECUTE RE_EXECUTE",
          actor: anything
        )
        post :re_execute, params: { id: trigger.id, reason: "Test reason", confirmation_text: "EXECUTE RE_EXECUTE" }
      end

      it "sets success flash message" do
        post :re_execute, params: { id: trigger.id, reason: "Fixing drift" }
        expect(flash[:success]).to match(/re-executed successfully/)
        expect(flash[:success]).to include(trigger.trigger_name)
      end

      it "redirects to root path by default" do
        post :re_execute, params: { id: trigger.id, reason: "Fixing drift" }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to specified path when redirect_to param present" do
        post :re_execute, params: { id: trigger.id, reason: "Fixing drift", redirect_to: "/custom/path" }
        expect(response).to redirect_to("/custom/path")
      end
    end

    context "when reason is missing" do
      it "sets error flash" do
        post :re_execute, params: { id: trigger.id }
        expect(flash[:error]).to eq("Reason is required for re-executing a trigger.")
      end

      it "redirects to root path" do
        post :re_execute, params: { id: trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "does not call re_execute!" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:re_execute!)
        post :re_execute, params: { id: trigger.id }
      end
    end

    context "when reason is blank" do
      it "sets error flash" do
        post :re_execute, params: { id: trigger.id, reason: "   " }
        expect(flash[:error]).to eq("Reason is required for re-executing a trigger.")
      end
    end

    context "when kill switch blocks operation" do
      before do
        allow_any_instance_of(described_class)
          .to receive(:check_kill_switch)
          .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch active"))
      end

      it "sets error flash" do
        post :re_execute, params: { id: trigger.id, reason: "Test" }
        expect(flash[:error]).to eq("Kill switch active")
      end

      it "redirects to root path" do
        post :re_execute, params: { id: trigger.id, reason: "Test" }
        expect(response).to redirect_to(root_path)
      end
    end

    context "when re-execute raises ArgumentError" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:re_execute!)
          .and_raise(ArgumentError.new("Missing function body"))
      end

      it "sets error flash with ArgumentError message" do
        post :re_execute, params: { id: trigger.id, reason: "Test" }
        expect(flash[:error]).to match(/Invalid request/)
        expect(flash[:error]).to include("Missing function body")
      end
    end

    context "when re-execute fails with StandardError" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:re_execute!)
          .and_raise(StandardError.new("Execution failed"))
      end

      it "sets error flash" do
        post :re_execute, params: { id: trigger.id, reason: "Test" }
        expect(flash[:error]).to match(/Failed to re-execute trigger/)
        expect(flash[:error]).to include("Execution failed")
      end

      it "logs the error" do
        post :re_execute, params: { id: trigger.id, reason: "Test" }
        expect(Rails.logger).to have_received(:error).with(/Re-execute failed/)
      end
    end

    context "when user lacks admin permission" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?) do |_actor, action, _options|
          action != :drop_trigger
        end
      end

      it "redirects to root with alert" do
        post :re_execute, params: { id: trigger.id, reason: "Test" }
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Admin role required")
        expect(response).to redirect_to(root_path)
      end
    end
  end
end
