# frozen_string_literal: true

module PgSqlTriggers
  module Registry
    class Manager
      class << self
        def register(definition)
          trigger_name = definition.name
          existing = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)

          # Calculate checksum using field-concatenation (consistent with TriggerRegistry model)
          checksum = calculate_checksum(definition)

          attributes = {
            trigger_name: definition.name,
            table_name: definition.table_name,
            version: definition.version,
            enabled: definition.enabled,
            source: "dsl",
            environment: definition.environments.join(","),
            definition: definition.to_h.to_json,
            checksum: checksum
          }

          if existing
            existing.update!(attributes)
            existing
          else
            PgSqlTriggers::TriggerRegistry.create!(attributes)
          end
        end

        def list
          PgSqlTriggers::TriggerRegistry.all
        end

        delegate :enabled, to: PgSqlTriggers::TriggerRegistry

        delegate :disabled, to: PgSqlTriggers::TriggerRegistry

        delegate :for_table, to: PgSqlTriggers::TriggerRegistry

        def diff(trigger_name = nil)
          PgSqlTriggers::Drift.detect(trigger_name)
        end

        def drifted
          PgSqlTriggers::Drift::Detector.detect_all.select do |r|
            r[:state] == PgSqlTriggers::DRIFT_STATE_DRIFTED
          end
        end

        def in_sync
          PgSqlTriggers::Drift::Detector.detect_all.select do |r|
            r[:state] == PgSqlTriggers::DRIFT_STATE_IN_SYNC
          end
        end

        def unknown_triggers
          PgSqlTriggers::Drift::Detector.detect_all.select do |r|
            r[:state] == PgSqlTriggers::DRIFT_STATE_UNKNOWN
          end
        end

        def dropped
          PgSqlTriggers::Drift::Detector.detect_all.select do |r|
            r[:state] == PgSqlTriggers::DRIFT_STATE_DROPPED
          end
        end

        private

        def calculate_checksum(definition)
          # DSL definitions don't have function_body, so use placeholder
          # Generator forms have function_body, so calculate real checksum
          function_body_value = definition.respond_to?(:function_body) ? definition.function_body : nil
          return "placeholder" if function_body_value.nil? || function_body_value.empty?

          # Use field-concatenation algorithm (consistent with TriggerRegistry#calculate_checksum)
          require "digest"
          Digest::SHA256.hexdigest([
            definition.name,
            definition.table_name,
            definition.version,
            function_body_value,
            definition.condition || ""
          ].join)
        end
      end
    end
  end
end
