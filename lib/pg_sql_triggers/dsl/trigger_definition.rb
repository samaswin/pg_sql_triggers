# frozen_string_literal: true

module PgSqlTriggers
  module DSL
    class TriggerDefinition
      attr_accessor :name, :table_name, :events, :function_name, :environments, :condition

      def initialize(name)
        @name = name
        @events = []
        @version = 1
        @enabled = false
        @environments = []
        @condition = nil
      end

      def table(table_name)
        @table_name = table_name
      end

      def on(*events)
        @events = events.map(&:to_s)
      end

      def function(function_name)
        @function_name = function_name
      end

      def version(version = nil)
        if version.nil?
          @version
        else
          @version = version
        end
      end

      def enabled(enabled = nil)
        if enabled.nil?
          @enabled
        else
          @enabled = enabled
        end
      end

      def when_env(*environments)
        @environments = environments.map(&:to_s)
      end

      def when_condition(condition_sql)
        @condition = condition_sql
      end

      def function_body
        nil # DSL definitions don't include function_body directly
      end

      def to_h
        {
          name: @name,
          table_name: @table_name,
          events: @events,
          function_name: @function_name,
          version: @version,
          enabled: @enabled,
          environments: @environments,
          condition: @condition
        }
      end
    end
  end
end
