# frozen_string_literal: true

module PgTriggers
  class TablesController < ApplicationController
    def index
      all_tables = PgTriggers::DatabaseIntrospection.new.tables_with_triggers
      # Only show tables that have at least one trigger
      @tables_with_triggers = all_tables.select { |t| t[:trigger_count] > 0 }
      @total_tables = @tables_with_triggers.count
      @tables_with_trigger_count = @tables_with_triggers.count
    end

    def show
      @table_info = PgTriggers::DatabaseIntrospection.new.table_triggers(params[:id])
      @columns = PgTriggers::DatabaseIntrospection.new.table_columns(params[:id])
      
      respond_to do |format|
        format.html
        format.json do
          render json: {
            table_name: @table_info[:table_name],
            registry_triggers: @table_info[:registry_triggers].map do |t|
              {
                id: t.id,
                trigger_name: t.trigger_name,
                function_name: t.definition.present? ? (JSON.parse(t.definition) rescue {})["function_name"] : nil,
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

