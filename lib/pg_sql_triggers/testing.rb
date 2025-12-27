# frozen_string_literal: true

module PgTriggers
  module Testing
    autoload :SyntaxValidator, "pg_sql_triggers/testing/syntax_validator"
    autoload :DryRun, "pg_sql_triggers/testing/dry_run"
    autoload :SafeExecutor, "pg_sql_triggers/testing/safe_executor"
    autoload :FunctionTester, "pg_sql_triggers/testing/function_tester"
  end
end
