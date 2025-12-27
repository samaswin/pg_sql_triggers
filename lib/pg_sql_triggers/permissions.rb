# frozen_string_literal: true

module PgTriggers
  module Permissions
    autoload :Checker, "pg_sql_triggers/permissions/checker"

    # Permission levels
    VIEWER = "viewer"
    OPERATOR = "operator"
    ADMIN = "admin"

    # Actions
    ACTIONS = {
      view_triggers: VIEWER,
      view_diffs: VIEWER,
      enable_trigger: OPERATOR,
      disable_trigger: OPERATOR,
      apply_trigger: OPERATOR,
      dry_run_sql: OPERATOR,
      generate_trigger: OPERATOR,
      test_trigger: OPERATOR,
      drop_trigger: ADMIN,
      execute_sql: ADMIN,
      override_drift: ADMIN
    }.freeze

    def self.check!(actor, action, environment: nil)
      Checker.check!(actor, action, environment: environment)
    end

    def self.can?(actor, action, environment: nil)
      Checker.can?(actor, action, environment: environment)
    end
  end
end
