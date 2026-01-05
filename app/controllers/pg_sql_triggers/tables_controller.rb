# frozen_string_literal: true

module PgSqlTriggers
  class TablesController < ApplicationController
    before_action :check_viewer_permission

    def index
      all_tables = PgSqlTriggers::DatabaseIntrospection.new.tables_with_triggers

      # Calculate statistics
      @tables_with_trigger_count = all_tables.count { |t| t[:trigger_count].positive? }
      @tables_without_trigger_count = all_tables.count { |t| t[:trigger_count].zero? }
      @total_tables_count = all_tables.count

      # Filter based on parameter
      @filter = params[:filter] || "with_triggers"
      filtered_tables = case @filter
                        when "with_triggers"
                          all_tables.select { |t| t[:trigger_count].positive? }
                        when "without_triggers"
                          all_tables.select { |t| t[:trigger_count].zero? }
                        else # 'all'
                          all_tables
                        end

      @total_tables = filtered_tables.count

      # Pagination
      @per_page = (params[:per_page] || 20).to_i
      @per_page = [@per_page, 100].min # Cap at 100
      @page = (params[:page] || 1).to_i
      @total_pages = @total_tables.positive? ? (@total_tables.to_f / @per_page).ceil : 1
      @page = @page.clamp(1, @total_pages) # Ensure page is within valid range

      offset = (@page - 1) * @per_page
      @tables_with_triggers = filtered_tables.slice(offset, @per_page) || []
    end

    def show
      @table_info = PgSqlTriggers::DatabaseIntrospection.new.table_triggers(params[:id])
      @columns = PgSqlTriggers::DatabaseIntrospection.new.table_columns(params[:id])

      respond_to do |format|
        format.html
        format.json do
          render json: {
            table_name: @table_info[:table_name],
            registry_triggers: @table_info[:registry_triggers].map do |t|
              {
                id: t.id,
                trigger_name: t.trigger_name,
                function_name: if t.definition.present?
                                 begin
                                   JSON.parse(t.definition)
                                 rescue StandardError
                                   {}
                                 end["function_name"]
                               end,
                enabled: t.enabled,
                version: t.version,
                source: t.source
              }
            end,
            database_triggers: @table_info[:database_triggers]
          }
        end
      end
    end
  end
end
