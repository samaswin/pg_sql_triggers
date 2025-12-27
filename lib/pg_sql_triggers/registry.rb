# frozen_string_literal: true

module PgTriggers
  module Registry
    autoload :Manager, "pg_sql_triggers/registry/manager"
    autoload :Validator, "pg_sql_triggers/registry/validator"

    def self.register(definition)
      Manager.register(definition)
    end

    def self.list
      Manager.list
    end

    def self.enabled
      Manager.enabled
    end

    def self.disabled
      Manager.disabled
    end

    def self.for_table(table_name)
      Manager.for_table(table_name)
    end

    def self.diff
      Manager.diff
    end

    def self.validate!
      Validator.validate!
    end
  end
end
