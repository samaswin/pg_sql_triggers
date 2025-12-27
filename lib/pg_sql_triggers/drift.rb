# frozen_string_literal: true

module PgTriggers
  module Drift
    autoload :Detector, "pg_sql_triggers/drift/detector"
    autoload :Reporter, "pg_sql_triggers/drift/reporter"

    # Drift states
    MANAGED_IN_SYNC = "managed_in_sync"
    MANAGED_DRIFTED = "managed_drifted"
    MANUAL_OVERRIDE = "manual_override"
    DISABLED = "disabled"
    DROPPED = "dropped"
    UNKNOWN = "unknown"

    def self.detect(trigger_name = nil)
      Detector.detect(trigger_name)
    end

    def self.report
      Reporter.report
    end
  end
end
