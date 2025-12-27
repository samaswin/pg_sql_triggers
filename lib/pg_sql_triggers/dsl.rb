# frozen_string_literal: true

module PgTriggers
  module DSL
    autoload :TriggerDefinition, "pg_sql_triggers/dsl/trigger_definition"
    autoload :Builder, "pg_sql_triggers/dsl/builder"

    def self.pg_trigger(name, &block)
      definition = TriggerDefinition.new(name)
      definition.instance_eval(&block)
      Registry.register(definition)
      definition
    end
  end
end
