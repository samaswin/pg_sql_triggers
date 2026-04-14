# frozen_string_literal: true

module PgSqlTriggers
  class DashboardController < ApplicationController
    helper DashboardHelper

    before_action :check_viewer_permission

    DRIFT_STATE_PARAM_MAP = {
      "in_sync" => PgSqlTriggers::DRIFT_STATE_IN_SYNC,
      "drifted" => PgSqlTriggers::DRIFT_STATE_DRIFTED,
      "disabled" => PgSqlTriggers::DRIFT_STATE_DISABLED,
      "dropped" => PgSqlTriggers::DRIFT_STATE_DROPPED,
      "unknown" => PgSqlTriggers::DRIFT_STATE_UNKNOWN,
      "manual_override" => PgSqlTriggers::DRIFT_STATE_MANUAL_OVERRIDE
    }.freeze

    SOURCE_OPTIONS = %w[dsl generated manual_sql].freeze

    def index
      load_filters
      load_triggers
      load_migration_status
    end

    private

    def load_filters
      @filter_table = params[:table].presence
      @filter_state = params[:state].presence
      @filter_source = params[:source].presence
      @filter_query = params[:q].presence
    end

    def load_triggers
      ordered = PgSqlTriggers::TriggerRegistry.order(
        Arel.sql("COALESCE(installed_at, created_at) DESC")
      )
      drift_results = PgSqlTriggers::Drift::Detector.detect_all
      @stats = build_stats(ordered, drift_results)

      filtered = apply_trigger_filters(ordered, drift_results)
      @trigger_list_total = filtered.count

      paginate_triggers(filtered)
      @filter_table_names = PgSqlTriggers::TriggerRegistry.distinct.order(:table_name).pluck(:table_name)
    end

    def paginate_triggers(filtered)
      @trigger_per_page = [(params[:trigger_per_page] || 20).to_i, 100].min
      @trigger_page = (params[:trigger_page] || 1).to_i
      @trigger_total_pages = @trigger_list_total.positive? ? (@trigger_list_total.to_f / @trigger_per_page).ceil : 1
      @trigger_page = @trigger_page.clamp(1, [@trigger_total_pages, 1].max)

      offset = (@trigger_page - 1) * @trigger_per_page
      @triggers = filtered.offset(offset).limit(@trigger_per_page)
    end

    def load_migration_status
      all_migrations = PgSqlTriggers::Migrator.status
      @pending_migrations = PgSqlTriggers::Migrator.pending_migrations
      @current_migration_version = PgSqlTriggers::Migrator.current_version

      paginate_migrations(all_migrations)
    rescue StandardError => e
      Rails.logger.error("Failed to fetch migration status: #{e.message}")
      reset_migration_defaults
    end

    def paginate_migrations(all_migrations)
      @per_page = [(params[:per_page] || 20).to_i, 100].min
      @page = (params[:page] || 1).to_i
      @total_migrations = all_migrations.count
      @total_pages = @total_migrations.positive? ? (@total_migrations.to_f / @per_page).ceil : 1
      @page = @page.clamp(1, @total_pages)

      migration_offset = (@page - 1) * @per_page
      @migration_status = all_migrations.slice(migration_offset, @per_page) || []
    end

    def reset_migration_defaults
      @migration_status = []
      @pending_migrations = []
      @current_migration_version = 0
      @total_migrations = 0
      @total_pages = 1
      @page = 1
      @per_page = 20
    end

    def build_stats(ordered_scope, drift_results)
      {
        total: ordered_scope.count,
        enabled: ordered_scope.enabled.count,
        disabled: ordered_scope.disabled.count,
        drifted: drift_results.count { |r| r[:state] == PgSqlTriggers::DRIFT_STATE_DRIFTED }
      }
    end

    def apply_trigger_filters(relation, drift_results)
      scoped = relation
      scoped = scoped.for_table(@filter_table) if @filter_table.present?

      scoped = scoped.by_source(@filter_source) if @filter_source.present? && SOURCE_OPTIONS.include?(@filter_source)

      scoped = scoped.matching_search(@filter_query) if @filter_query.present?

      if @filter_state.present? && DRIFT_STATE_PARAM_MAP.key?(@filter_state)
        scoped = filter_by_drift_state(scoped, drift_results, DRIFT_STATE_PARAM_MAP[@filter_state])
      end

      scoped
    end

    def filter_by_drift_state(relation, drift_results, drift_constant)
      names = drift_results.each_with_object([]) do |result, acc|
        next unless result[:state] == drift_constant

        entry = result[:registry_entry]
        acc << entry.trigger_name if entry
      end
      return relation.none if names.empty?

      relation.where(trigger_name: names)
    end
  end
end
