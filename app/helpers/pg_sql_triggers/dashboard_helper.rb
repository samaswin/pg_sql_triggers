# frozen_string_literal: true

module PgSqlTriggers
  # URL helpers for dashboard list filters and dual pagination (triggers vs migrations).
  module DashboardHelper
    # Params to preserve when linking within the dashboard (filters + both paginations).
    DASHBOARD_PARAM_KEYS = %i[
      table state source q
      trigger_page trigger_per_page
      page per_page
    ].freeze

    def dashboard_list_params(extra = {})
      keys = DashboardHelper::DASHBOARD_PARAM_KEYS
      base = params.permit(*keys).to_h.symbolize_keys
      base.merge(extra.symbolize_keys).compact_blank
    end
  end
end
