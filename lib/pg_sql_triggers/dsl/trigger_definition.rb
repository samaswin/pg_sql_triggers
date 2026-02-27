# frozen_string_literal: true

module PgSqlTriggers
  module DSL
    class TriggerDefinition
      attr_accessor :name, :table_name, :events, :function_name, :environments, :condition, :version, :enabled
      attr_reader :timing

      def initialize(name)
        @name = name
        @events = []
        @version = 1
        @enabled = false
        @environments = []
        @condition = nil
        @timing = "before"
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

      def timing=(val)
        @timing = val.to_s
      end

      def when_env(*environments)
        warn "[DEPRECATION] `when_env` is deprecated and will be removed in a future version. " \
             "Environment-specific trigger behavior causes schema drift between environments. " \
             "Use application-level configuration instead."
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
          condition: @condition,
          timing: @timing
        }
      end
    end
  end
end
