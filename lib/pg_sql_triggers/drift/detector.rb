# frozen_string_literal: true

require "digest"
require_relative "db_queries"

module PgSqlTriggers
  module Drift
    class Detector
      class << self
        # Detect drift for a single trigger
        def detect(trigger_name)
          registry_entry = TriggerRegistry.find_by(trigger_name: trigger_name)
          db_trigger = DbQueries.find_trigger(trigger_name)
          detect_with_preloaded(registry_entry, db_trigger)
        end

        # Detect drift for all triggers
        def detect_all
          registry_entries = TriggerRegistry.all.to_a
          db_triggers = DbQueries.all_triggers

          db_trigger_map = db_triggers.index_by { |t| t["trigger_name"] }

          results = registry_entries.map do |entry|
            detect_with_preloaded(entry, db_trigger_map[entry.trigger_name])
          end

          # Find unknown (external) triggers not in registry
          registry_trigger_names = registry_entries.to_set(&:trigger_name)
          db_triggers.each do |db_trigger|
            next if registry_trigger_names.include?(db_trigger["trigger_name"])

            results << unknown_state(db_trigger)
          end

          results
        end

        # Detect drift for a specific table
        def detect_for_table(table_name)
          registry_entries = TriggerRegistry.for_table(table_name).to_a
          db_triggers = DbQueries.find_triggers_for_table(table_name)

          db_trigger_map = db_triggers.index_by { |t| t["trigger_name"] }

          results = registry_entries.map do |entry|
            detect_with_preloaded(entry, db_trigger_map[entry.trigger_name])
          end

          # Find unknown triggers on this table
          registry_trigger_names = registry_entries.to_set(&:trigger_name)
          db_triggers.each do |db_trigger|
            next if registry_trigger_names.include?(db_trigger["trigger_name"])

            results << unknown_state(db_trigger)
          end

          results
        end

        private

        # Core state computation using pre-loaded data — no additional DB queries.
        def detect_with_preloaded(registry_entry, db_trigger)
          return disabled_state(registry_entry, db_trigger) if registry_entry&.enabled == false
          return manual_override_state(registry_entry, db_trigger) if registry_entry&.source == "manual_sql"
          return dropped_state(registry_entry) if registry_entry && !db_trigger
          return unknown_state(db_trigger) if !registry_entry && db_trigger

          if registry_entry && db_trigger && !checksums_match?(registry_entry, db_trigger)
            return drifted_state(registry_entry, db_trigger)
          end

          in_sync_state(registry_entry, db_trigger)
        end

        # Compare registry checksum with calculated DB checksum
        def checksums_match?(registry_entry, db_trigger)
          db_checksum = calculate_db_checksum(registry_entry, db_trigger)
          registry_entry.checksum == db_checksum
        end

        # Calculate checksum from DB trigger (must match registry algorithm)
        def calculate_db_checksum(registry_entry, db_trigger)
          function_body = if registry_entry.source == "dsl"
                            db_trigger["function_definition"] || ""
                          else
                            extract_function_body(db_trigger) || ""
                          end

          # Extract condition from trigger definition
          condition = extract_trigger_condition(db_trigger)

          # Use same algorithm as TriggerRegistry#calculate_checksum
          Digest::SHA256.hexdigest([
            registry_entry.trigger_name,
            registry_entry.table_name,
            registry_entry.version,
            function_body,
            condition || "",
            registry_entry.timing || "before"
          ].join)
        end

        # Extract just the PL/pgSQL body from pg_get_functiondef output.
        # pg_get_functiondef() returns the full CREATE OR REPLACE FUNCTION statement;
        # we extract only the content between the dollar-quote delimiters so the
        # comparison is format-agnostic (handles $$ and $function$ styles).
        def extract_function_body(db_trigger)
          function_def = db_trigger["function_definition"]
          return nil unless function_def

          # Match any dollar-quoted string: $tag$body$tag$ (tag may be empty)
          match = function_def.match(/\$([^$]*)\$(.*?)\$\1\$/m)
          match ? match[2].strip : function_def.strip
        end

        # Extract WHEN condition from trigger definition
        def extract_trigger_condition(db_trigger)
          trigger_def = db_trigger["trigger_definition"]
          return nil unless trigger_def

          # Extract WHEN clause from trigger definition
          # Example: "... WHEN ((new.email IS NOT NULL)) EXECUTE ..."
          match = trigger_def.match(/WHEN\s+\((.+?)\)\s+EXECUTE/i)
          match ? match[1].strip : nil
        end

        # State helper methods
        def disabled_state(registry_entry, db_trigger)
          {
            state: PgSqlTriggers::DRIFT_STATE_DISABLED,
            registry_entry: registry_entry,
            db_trigger: db_trigger,
            details: "Trigger is disabled in registry"
          }
        end

        def manual_override_state(registry_entry, db_trigger)
          {
            state: PgSqlTriggers::DRIFT_STATE_MANUAL_OVERRIDE,
            registry_entry: registry_entry,
            db_trigger: db_trigger,
            details: "Trigger marked as manual SQL override"
          }
        end

        def dropped_state(registry_entry)
          {
            state: PgSqlTriggers::DRIFT_STATE_DROPPED,
            registry_entry: registry_entry,
            db_trigger: nil,
            details: "Trigger exists in registry but not in database"
          }
        end

        def unknown_state(db_trigger)
          {
            state: PgSqlTriggers::DRIFT_STATE_UNKNOWN,
            registry_entry: nil,
            db_trigger: db_trigger,
            details: "Trigger exists in database but not in registry (external)"
          }
        end

        def drifted_state(registry_entry, db_trigger)
          {
            state: PgSqlTriggers::DRIFT_STATE_DRIFTED,
            registry_entry: registry_entry,
            db_trigger: db_trigger,
            checksum_match: false,
            details: "Trigger has drifted (checksum mismatch between registry and database)"
          }
        end

        def in_sync_state(registry_entry, db_trigger)
          {
            state: PgSqlTriggers::DRIFT_STATE_IN_SYNC,
            registry_entry: registry_entry,
            db_trigger: db_trigger,
            checksum_match: true,
            details: "Trigger matches registry (in sync)"
          }
        end
      end
    end
  end
end
