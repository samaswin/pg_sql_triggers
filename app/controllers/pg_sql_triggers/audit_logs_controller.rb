# frozen_string_literal: true

module PgSqlTriggers
  class AuditLogsController < ApplicationController
    before_action :check_viewer_permission

    # GET /audit_logs
    # Display audit log entries with filtering and sorting
    def index
      @audit_logs = PgSqlTriggers::AuditLog.all

      # Filter by trigger name
      @audit_logs = @audit_logs.for_trigger(params[:trigger_name]) if params[:trigger_name].present?

      # Filter by operation
      @audit_logs = @audit_logs.for_operation(params[:operation]) if params[:operation].present?

      # Filter by status
      if params[:status].present? && %w[success failure].include?(params[:status])
        @audit_logs = @audit_logs.where(status: params[:status])
      end

      # Filter by environment
      @audit_logs = @audit_logs.for_environment(params[:environment]) if params[:environment].present?

      # Filter by actor (search in JSONB field)
      @audit_logs = @audit_logs.where("actor->>'id' = ?", params[:actor_id]) if params[:actor_id].present?

      # Sort by date (default: most recent first)
      sort_direction = params[:sort] == "asc" ? :asc : :desc
      @audit_logs = @audit_logs.order(created_at: sort_direction)

      # Pagination
      @per_page = (params[:per_page] || 50).to_i
      @per_page = [@per_page, 200].min # Cap at 200
      @page = (params[:page] || 1).to_i
      @total_count = @audit_logs.count
      @total_pages = @total_count.positive? ? (@total_count.to_f / @per_page).ceil : 1
      @page = @page.clamp(1, @total_pages)

      offset = (@page - 1) * @per_page
      @audit_logs = @audit_logs.offset(offset).limit(@per_page)

      # Get distinct values for filter dropdowns
      @available_trigger_names = PgSqlTriggers::AuditLog.distinct.pluck(:trigger_name).compact.sort
      @available_operations = PgSqlTriggers::AuditLog.distinct.pluck(:operation).compact.sort
      @available_environments = PgSqlTriggers::AuditLog.distinct.pluck(:environment).compact.sort

      respond_to do |format|
        format.html
        format.csv do
          send_data generate_csv, filename: "audit_logs_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                                  type: "text/csv", disposition: "attachment"
        end
      end
    end

    private

    def generate_csv
      require "csv"

      # Get all audit logs (no pagination for CSV)
      audit_logs = PgSqlTriggers::AuditLog.all

      # Apply filters
      audit_logs = audit_logs.for_trigger(params[:trigger_name]) if params[:trigger_name].present?
      audit_logs = audit_logs.for_operation(params[:operation]) if params[:operation].present?
      if params[:status].present? && %w[success failure].include?(params[:status])
        audit_logs = audit_logs.where(status: params[:status])
      end
      audit_logs = audit_logs.for_environment(params[:environment]) if params[:environment].present?
      audit_logs = audit_logs.where("actor->>'id' = ?", params[:actor_id]) if params[:actor_id].present?

      CSV.generate(headers: true) do |csv|
        csv << [
          "ID", "Trigger Name", "Operation", "Status", "Environment",
          "Actor Type", "Actor ID", "Reason", "Error Message",
          "Created At"
        ]

        audit_logs.order(created_at: :desc).find_each do |log|
          actor_type = log.actor.is_a?(Hash) ? log.actor["type"] || log.actor[:type] : nil
          actor_id = log.actor.is_a?(Hash) ? log.actor["id"] || log.actor[:id] : nil

          csv << [
            log.id,
            log.trigger_name || "",
            log.operation,
            log.status,
            log.environment || "",
            actor_type || "",
            actor_id || "",
            log.reason || "",
            log.error_message || "",
            log.created_at&.iso8601 || ""
          ]
        end
      end
    end
  end
end
