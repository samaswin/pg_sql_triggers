# frozen_string_literal: true

module PgTriggers
  class DashboardController < ApplicationController
    def index
      @triggers = TriggerRegistry.all.order(created_at: :desc)
      @stats = {
        total: @triggers.count,
        enabled: @triggers.enabled.count,
        disabled: @triggers.disabled.count,
        drifted: 0 # Will be calculated by Drift::Detector
      }
      
      # Migration status
      begin
        @migration_status = PgTriggers::Migrator.status
        @pending_migrations = PgTriggers::Migrator.pending_migrations
        @current_migration_version = PgTriggers::Migrator.current_version
      rescue => e
        Rails.logger.error("Failed to fetch migration status: #{e.message}")
        @migration_status = []
        @pending_migrations = []
        @current_migration_version = 0
      end
    end
  end
end
