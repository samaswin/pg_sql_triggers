# frozen_string_literal: true

module PgSqlTriggers
  class DashboardController < ApplicationController
    def index
      @triggers = PgSqlTriggers::TriggerRegistry.order(created_at: :desc)

      # Get drift summary
      drift_summary = PgSqlTriggers::Drift::Reporter.summary
      @stats = {
        total: @triggers.count,
        enabled: @triggers.enabled.count,
        disabled: @triggers.disabled.count,
        drifted: drift_summary[:drifted]
      }

      # Migration status with pagination
      begin
        all_migrations = PgSqlTriggers::Migrator.status
        @pending_migrations = PgSqlTriggers::Migrator.pending_migrations
        @current_migration_version = PgSqlTriggers::Migrator.current_version

        # Pagination
        @per_page = (params[:per_page] || 20).to_i
        @per_page = [@per_page, 100].min # Cap at 100
        @page = (params[:page] || 1).to_i
        @total_migrations = all_migrations.count
        @total_pages = @total_migrations.positive? ? (@total_migrations.to_f / @per_page).ceil : 1
        @page = @page.clamp(1, @total_pages) # Ensure page is within valid range

        offset = (@page - 1) * @per_page
        @migration_status = all_migrations.slice(offset, @per_page) || []
      rescue StandardError => e
        Rails.logger.error("Failed to fetch migration status: #{e.message}")
        @migration_status = []
        @pending_migrations = []
        @current_migration_version = 0
        @total_migrations = 0
        @total_pages = 1
        @page = 1
        @per_page = 20
      end
    end
  end
end
