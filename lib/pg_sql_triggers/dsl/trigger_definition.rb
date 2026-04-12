# frozen_string_literal: true

module PgSqlTriggers
  module DSL
    class TriggerDefinition
      attr_accessor :name, :table_name, :events, :function_name, :environments, :condition, :version, :enabled,
                    :columns, :deferrable, :initially
      attr_reader :timing, :for_each

      def initialize(name)
        @name = name
        @events = []
        @version = 1
        @enabled = true
        @environments = []
        @condition = nil
        @timing = "before"
        @for_each = "row"
        @columns = nil
        @constraint_trigger = false
        @deferrable = nil
        @initially = nil
      end

      # Intentionally not named `constraint_trigger?` — matches registry column and JSON key.
      def constraint_trigger # rubocop:disable Naming/PredicateMethod
        @constraint_trigger == true
      end

      def constraint_trigger=(value)
        @constraint_trigger = ActiveModel::Type::Boolean.new.cast(value)
        clear_deferral unless @constraint_trigger
      end

      def table(table_name)
        @table_name = table_name
      end

      def on(*events)
        @events = events.map(&:to_s)
        @columns = nil
      end

      def on_update_of(*cols)
        @events = ["update"]
        @columns = cols.map(&:to_s)
      end

      def function(function_name)
        @function_name = function_name
      end

      def timing=(val)
        @timing = val.to_s
      end

      def constraint_trigger!
        self.constraint_trigger = true
      end

      def for_each_row
        @for_each = "row"
      end

      def for_each_statement
        @for_each = "statement"
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
          timing: @timing,
          for_each: @for_each,
          columns: @columns,
          constraint_trigger: @constraint_trigger == true,
          deferrable: @deferrable&.to_s,
          initially: @initially&.to_s
        }
      end

      private

      def clear_deferral
        @deferrable = nil
        @initially = nil
      end
    end
  end
end
