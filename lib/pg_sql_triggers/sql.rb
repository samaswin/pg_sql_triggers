# frozen_string_literal: true

module PgSqlTriggers
  module SQL
    autoload :KillSwitch, "pg_sql_triggers/sql/kill_switch"

    def self.kill_switch_active?
      KillSwitch.active?
    end

    def self.override_kill_switch(&block)
      KillSwitch.override(&block)
    end
  end
end
