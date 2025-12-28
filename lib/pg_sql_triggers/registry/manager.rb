# frozen_string_literal: true

module PgSqlTriggers
  module Registry
    class Manager
      class << self
        def register(definition)
          trigger_name = definition.name
          existing = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)

          attributes = {
            trigger_name: definition.name,
            table_name: definition.table_name,
            version: definition.version,
            enabled: definition.enabled,
            source: "dsl",
            environment: definition.environments.join(","),
            definition: definition.to_h.to_json
          }

          if existing
            existing.update!(attributes)
            existing
          else
            PgSqlTriggers::TriggerRegistry.create!(attributes.merge(checksum: "placeholder"))
          end
        end

        def list
          PgSqlTriggers::TriggerRegistry.all
        end

        delegate :enabled, to: PgSqlTriggers::TriggerRegistry

        delegate :disabled, to: PgSqlTriggers::TriggerRegistry

        delegate :for_table, to: PgSqlTriggers::TriggerRegistry

        def diff
          # Compare DSL definitions with actual database state
          # This will be implemented in the Drift::Detector
          Drift.detect
        end
      end
    end
  end
end
