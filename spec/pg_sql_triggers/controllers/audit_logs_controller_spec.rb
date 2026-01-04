# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::AuditLogsController, type: :controller do
  routes { PgSqlTriggers::Engine.routes }

  before do
    # Configure view paths
    engine_view_path = PgSqlTriggers::Engine.root.join("app/views").to_s
    controller.prepend_view_path(engine_view_path) if controller.respond_to?(:prepend_view_path)

    # Allow permissions by default
    allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
  end

  describe "GET #index" do
    let!(:successful_audit_log) do
      PgSqlTriggers::AuditLog.create!(
        trigger_name: "test_trigger_1",
        operation: "enable",
        status: "success",
        environment: "test",
        actor: { type: "User", id: "1" },
        created_at: 3.days.ago
      )
    end

    let!(:failed_audit_log) do
      PgSqlTriggers::AuditLog.create!(
        trigger_name: "test_trigger_2",
        operation: "disable",
        status: "failure",
        environment: "test",
        actor: { type: "User", id: "2" },
        error_message: "Permission denied",
        created_at: 2.days.ago
      )
    end

    let!(:recent_audit_log) do
      PgSqlTriggers::AuditLog.create!(
        trigger_name: "test_trigger_1",
        operation: "drop",
        status: "success",
        environment: "production",
        actor: { type: "Admin", id: "3" },
        reason: "No longer needed",
        created_at: 1.day.ago
      )
    end

    it "loads all audit logs" do
      get :index
      expect(assigns(:audit_logs).count).to eq(3)
    end

    it "sorts by created_at descending by default" do
      get :index
      logs = assigns(:audit_logs)
      expect(logs.first.id).to eq(recent_audit_log.id)
      expect(logs.last.id).to eq(successful_audit_log.id)
    end

    it "sorts by created_at ascending when sort=asc" do
      get :index, params: { sort: "asc" }
      logs = assigns(:audit_logs)
      expect(logs.first.id).to eq(successful_audit_log.id)
      expect(logs.last.id).to eq(recent_audit_log.id)
    end

    it "filters by trigger_name" do
      get :index, params: { trigger_name: "test_trigger_1" }
      logs = assigns(:audit_logs)
      expect(logs.count).to eq(2)
      expect(logs.map(&:trigger_name).uniq).to eq(["test_trigger_1"])
    end

    it "filters by operation" do
      get :index, params: { operation: "enable" }
      logs = assigns(:audit_logs)
      expect(logs.count).to eq(1)
      expect(logs.first.operation).to eq("enable")
    end

    it "filters by status" do
      get :index, params: { status: "success" }
      logs = assigns(:audit_logs)
      expect(logs.count).to eq(2)
      expect(logs.map(&:status).uniq).to eq(["success"])
    end

    it "filters by environment" do
      get :index, params: { environment: "production" }
      logs = assigns(:audit_logs)
      expect(logs.count).to eq(1)
      expect(logs.first.environment).to eq("production")
    end

    it "filters by actor_id" do
      get :index, params: { actor_id: "1" }
      logs = assigns(:audit_logs)
      expect(logs.count).to eq(1)
      expect(logs.first.actor["id"]).to eq("1")
    end

    it "combines multiple filters" do
      get :index, params: { trigger_name: "test_trigger_1", status: "success" }
      logs = assigns(:audit_logs)
      expect(logs.count).to eq(2)
      expect(logs.map(&:trigger_name).uniq).to eq(["test_trigger_1"])
      expect(logs.map(&:status).uniq).to eq(["success"])
    end

    it "paginates results" do
      # Create more audit logs
      15.times do |i|
        PgSqlTriggers::AuditLog.create!(
          trigger_name: "trigger_#{i}",
          operation: "enable",
          status: "success",
          environment: "test",
          actor: { type: "User", id: i.to_s }
        )
      end

      get :index, params: { page: 1, per_page: 10 }
      expect(assigns(:audit_logs).count).to eq(10)
      expect(assigns(:per_page)).to eq(10)
      expect(assigns(:page)).to eq(1)
    end

    it "caps per_page at 200" do
      get :index, params: { per_page: 500 }
      expect(assigns(:per_page)).to eq(200)
    end

    it "clamps page to valid range" do
      get :index, params: { page: 100 }
      expect(assigns(:page)).to be <= assigns(:total_pages)
    end

    it "provides distinct values for filter dropdowns" do
      get :index
      expect(assigns(:available_trigger_names)).to include("test_trigger_1", "test_trigger_2")
      expect(assigns(:available_operations)).to include("enable", "disable", "drop")
      expect(assigns(:available_environments)).to include("test", "production")
    end

    it "renders HTML format" do
      get :index
      expect(response).to render_template(:index)
      expect(response.content_type).to include("text/html")
    end

    context "when user lacks view permission" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)
      end

      it "redirects to root with alert" do
        get :index
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Viewer role required")
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "GET #index as CSV" do
    let!(:audit_log) do
      PgSqlTriggers::AuditLog.create!(
        trigger_name: "test_trigger",
        operation: "enable",
        status: "success",
        environment: "test",
        actor: { type: "User", id: "123" },
        reason: "Testing",
        error_message: nil
      )
    end

    it "generates CSV with headers" do
      get :index, format: :csv
      expect(response.content_type).to include("text/csv")
      csv = CSV.parse(response.body)
      expect(csv.first).to eq([
                                "ID", "Trigger Name", "Operation", "Status", "Environment",
                                "Actor Type", "Actor ID", "Reason", "Error Message", "Created At"
                              ])
    end

    it "includes audit log data in CSV" do
      get :index, format: :csv
      csv = CSV.parse(response.body)
      # Skip header row
      data_row = csv[1]
      expect(data_row[0]).to eq(audit_log.id.to_s)
      expect(data_row[1]).to eq("test_trigger")
      expect(data_row[2]).to eq("enable")
      expect(data_row[3]).to eq("success")
      expect(data_row[4]).to eq("test")
      expect(data_row[5]).to eq("User")
      expect(data_row[6]).to eq("123")
      expect(data_row[7]).to eq("Testing")
      expect(data_row[8]).to eq("")
    end

    it "applies filters to CSV export" do
      PgSqlTriggers::AuditLog.create!(
        trigger_name: "other_trigger",
        operation: "disable",
        status: "failure",
        environment: "test",
        actor: { type: "User", id: "456" }
      )

      get :index, format: :csv, params: { trigger_name: "test_trigger" }
      csv = CSV.parse(response.body)
      # Header + 1 data row
      expect(csv.count).to eq(2)
      expect(csv[1][1]).to eq("test_trigger")
    end

    it "sets correct filename" do
      get :index, format: :csv
      expect(response.headers["Content-Disposition"]).to match(/attachment/)
      expect(response.headers["Content-Disposition"]).to match(/audit_logs_\d{8}_\d{6}\.csv/)
    end

    it "exports all records (no pagination)" do
      # Clear existing audit logs for this test
      PgSqlTriggers::AuditLog.delete_all

      # Create more than one page of records
      25.times do |i|
        PgSqlTriggers::AuditLog.create!(
          trigger_name: "trigger_#{i}",
          operation: "enable",
          status: "success",
          environment: "test",
          actor: { type: "User", id: i.to_s }
        )
      end

      get :index, format: :csv, params: { per_page: 10 }
      csv = CSV.parse(response.body)
      # Header + all 25 records
      expect(csv.count).to eq(26)
    end
  end
end
