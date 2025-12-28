# frozen_string_literal: true

module PgSqlTriggers
  module Drift
    autoload :DbQueries, "pg_sql_triggers/drift/db_queries"
    autoload :Detector, "pg_sql_triggers/drift/detector"
    autoload :Reporter, "pg_sql_triggers/drift/reporter"

    # Convenience method for detecting drift
    def self.detect(trigger_name = nil)
      if trigger_name
        Detector.detect(trigger_name)
      else
        Detector.detect_all
      end
    end

    # Convenience method for reporting
    def self.summary
      Reporter.summary
    end

    def self.report(trigger_name)
      Reporter.report(trigger_name)
    end
  end
end
