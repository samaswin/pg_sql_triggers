# frozen_string_literal: true

module PgSqlTriggers
  class TablesController < ApplicationController
    def index
      all_tables = PgSqlTriggers::DatabaseIntrospection.new.tables_with_triggers
      # Only show tables that have at least one trigger
      @tables_with_triggers = all_tables.select { |t| t[:trigger_count].positive? }
      @total_tables = @tables_with_triggers.count
      @tables_with_trigger_count = @tables_with_triggers.count
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
