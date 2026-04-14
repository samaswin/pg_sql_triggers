# frozen_string_literal: true

module PgSqlTriggers
  class AuditLogsController < ApplicationController
    before_action :check_viewer_permission

    TEXT_SEARCH_SQL = [
      "trigger_name ILIKE :t",
      "operation ILIKE :t",
      "COALESCE(reason, '') ILIKE :t",
      "COALESCE(error_message, '') ILIKE :t"
    ].join(" OR ").freeze

    CSV_HEADERS = [
      "ID", "Trigger Name", "Operation", "Status", "Environment",
      "Actor Type", "Actor ID", "Reason", "Error Message",
      "Created At"
    ].freeze

    # GET /audit_logs
    # Display audit log entries with filtering and sorting
    def index
      scope = apply_filters(PgSqlTriggers::AuditLog.all)
      @audit_logs = scope.order(created_at: sort_direction)

      paginate_audit_logs
      load_filter_options

      respond_to do |format|
        format.html
        format.csv { send_csv_response(scope) }
      end
    end

    private

    def apply_filters(scope)
      scope = scope.for_trigger(params[:trigger_name]) if params[:trigger_name].present?
      scope = scope.for_operation(params[:operation]) if params[:operation].present?
      scope = scope.where(status: params[:status]) if valid_status?(params[:status])
      scope = scope.for_environment(params[:environment]) if params[:environment].present?
      scope = scope.where("actor->>'id' = ?", params[:actor_id]) if params[:actor_id].present?
      apply_text_search(scope)
    end

    def apply_text_search(scope)
      return scope if params[:q].blank?

      term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
      scope.where(TEXT_SEARCH_SQL, t: term)
    end

    def valid_status?(status)
      status.present? && %w[success failure].include?(status)
    end

    def sort_direction
      params[:sort] == "asc" ? :asc : :desc
    end

    def paginate_audit_logs
      @per_page = [(params[:per_page] || 50).to_i, 200].min
      @page = (params[:page] || 1).to_i
      @total_count = @audit_logs.count
      @total_pages = @total_count.positive? ? (@total_count.to_f / @per_page).ceil : 1
      @page = @page.clamp(1, @total_pages)

      offset = (@page - 1) * @per_page
      @audit_logs = @audit_logs.offset(offset).limit(@per_page)
    end

    def load_filter_options
      @available_trigger_names = PgSqlTriggers::AuditLog.distinct.pluck(:trigger_name).compact.sort
      @available_operations = PgSqlTriggers::AuditLog.distinct.pluck(:operation).compact.sort
      @available_environments = PgSqlTriggers::AuditLog.distinct.pluck(:environment).compact.sort
    end

    def send_csv_response(scope)
      send_data generate_csv(scope),
                filename: "audit_logs_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                type: "text/csv",
                disposition: "attachment"
    end

    def generate_csv(scope)
      require "csv"

      CSV.generate(headers: true) do |csv|
        csv << CSV_HEADERS
        scope.order(created_at: :desc).find_each do |log|
          csv << csv_row_for(log)
        end
      end
    end

    def csv_row_for(log)
      actor_type, actor_id = extract_actor_fields(log.actor)

      [
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

    def extract_actor_fields(actor)
      return [nil, nil] unless actor.is_a?(Hash)

      [actor["type"] || actor[:type], actor["id"] || actor[:id]]
    end
  end
end
