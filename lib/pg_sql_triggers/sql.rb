# frozen_string_literal: true

module PgTriggers
  module SQL
    autoload :Capsule, "pg_sql_triggers/sql/capsule"
    autoload :Executor, "pg_sql_triggers/sql/executor"
    autoload :KillSwitch, "pg_sql_triggers/sql/kill_switch"

    def self.execute_capsule(capsule_name, **options)
      Executor.execute_capsule(capsule_name, **options)
    end

    def self.kill_switch_active?
      KillSwitch.active?
    end

    def self.override_kill_switch(&block)
      KillSwitch.override(&block)
    end
  end
end
