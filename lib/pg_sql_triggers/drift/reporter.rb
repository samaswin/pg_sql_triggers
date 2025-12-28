# frozen_string_literal: true

require_relative "detector"

module PgSqlTriggers
  module Drift
    class Reporter
      class << self
        # Generate a summary report
        def summary
          results = Detector.detect_all

          {
            total: results.count,
            in_sync: results.count { |r| r[:state] == PgSqlTriggers::DRIFT_STATE_IN_SYNC },
            drifted: results.count { |r| r[:state] == PgSqlTriggers::DRIFT_STATE_DRIFTED },
            disabled: results.count { |r| r[:state] == PgSqlTriggers::DRIFT_STATE_DISABLED },
            dropped: results.count { |r| r[:state] == PgSqlTriggers::DRIFT_STATE_DROPPED },
            unknown: results.count { |r| r[:state] == PgSqlTriggers::DRIFT_STATE_UNKNOWN },
            manual_override: results.count { |r| r[:state] == PgSqlTriggers::DRIFT_STATE_MANUAL_OVERRIDE }
          }
        end

        # Generate detailed report for a trigger
        def report(trigger_name)
          result = Detector.detect(trigger_name)

          output = []
          output << ("=" * 80)
          output << "Drift Report: #{trigger_name}"
          output << ("=" * 80)
          output << ""

          # State
          output << "State: #{format_state(result[:state])}"
          output << ""

          # Details
          output << "Details: #{result[:details]}"
          output << ""

          # Registry info
          if result[:registry_entry]
            output << "Registry Information:"
            output << "  Table: #{result[:registry_entry].table_name}"
            output << "  Version: #{result[:registry_entry].version}"
            output << "  Enabled: #{result[:registry_entry].enabled}"
            output << "  Source: #{result[:registry_entry].source}"
            output << "  Checksum: #{result[:registry_entry].checksum}"
            output << ""
          end

          # Database info
          if result[:db_trigger]
            output << "Database Information:"
            output << "  Table: #{result[:db_trigger]['table_name']}"
            output << "  Function: #{result[:db_trigger]['function_name']}"
            output << "  Enabled: #{result[:db_trigger]['enabled']}"
            output << ""
          end

          # If drifted, show diff
          output << diff(trigger_name) if result[:state] == PgSqlTriggers::DRIFT_STATE_DRIFTED

          output << ("=" * 80)

          output.join("\n")
        end

        # Generate diff view (expected vs actual)
        def diff(trigger_name)
          result = Detector.detect(trigger_name)

          return "No drift detected" if result[:state] != PgSqlTriggers::DRIFT_STATE_DRIFTED

          output = []
          output << "Drift Comparison:"
          output << ("-" * 80)

          registry_entry = result[:registry_entry]
          db_trigger = result[:db_trigger]

          # Version comparison
          output << "Version:"
          output << "  Registry: #{registry_entry.version}"
          output << "  Database: (version not stored in DB)"
          output << ""

          # Checksum comparison
          output << "Checksum:"
          output << "  Registry: #{registry_entry.checksum}"
          output << "  Database: (calculated from current DB state)"
          output << ""

          # Function comparison
          output << "Function:"
          output << "  Registry Function Body:"
          output << indent_text(registry_entry.function_body || "(not set)", 4)
          output << ""
          output << "  Database Function Definition:"
          output << indent_text(db_trigger["function_definition"] || "(not found)", 4)
          output << ""

          # Condition comparison
          if registry_entry.respond_to?(:condition) && registry_entry.condition.present?
            output << "Condition:"
            output << "  Registry: #{registry_entry.condition}"
            # Extract condition from DB trigger definition
            trigger_def = db_trigger["trigger_definition"]
            db_condition = trigger_def.match(/WHEN\s+\((.+?)\)\s+EXECUTE/i)&.[](1)
            output << "  Database: #{db_condition || '(none)'}"
            output << ""
          end

          output << ("-" * 80)

          output.join("\n")
        end

        # Generate simple text list of drifted triggers
        def drifted_list
          results = Detector.detect_all
          drifted = results.select { |r| r[:state] == PgSqlTriggers::DRIFT_STATE_DRIFTED }

          return "No drifted triggers found" if drifted.empty?

          output = []
          output << "Drifted Triggers (#{drifted.count}):"
          output << ""

          drifted.each do |result|
            entry = result[:registry_entry]
            output << "  - #{entry.trigger_name} (#{entry.table_name})"
          end

          output.join("\n")
        end

        # Generate problematic triggers list (for dashboard)
        def problematic_list
          results = Detector.detect_all
          results.select do |r|
            [
              PgSqlTriggers::DRIFT_STATE_DRIFTED,
              PgSqlTriggers::DRIFT_STATE_DROPPED,
              PgSqlTriggers::DRIFT_STATE_UNKNOWN
            ].include?(r[:state])
          end
        end

        private

        def format_state(state)
          case state
          when PgSqlTriggers::DRIFT_STATE_IN_SYNC
            "IN SYNC"
          when PgSqlTriggers::DRIFT_STATE_DRIFTED
            "DRIFTED"
          when PgSqlTriggers::DRIFT_STATE_DROPPED
            "DROPPED"
          when PgSqlTriggers::DRIFT_STATE_UNKNOWN
            "UNKNOWN (External)"
          when PgSqlTriggers::DRIFT_STATE_DISABLED
            "DISABLED"
          when PgSqlTriggers::DRIFT_STATE_MANUAL_OVERRIDE
            "MANUAL OVERRIDE"
          else
            "UNKNOWN STATE"
          end
        end

        def indent_text(text, spaces)
          indent = " " * spaces
          text.to_s.lines.map { |line| "#{indent}#{line}" }.join
        end
      end
    end
  end
end
