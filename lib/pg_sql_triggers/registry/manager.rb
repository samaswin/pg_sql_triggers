# frozen_string_literal: true

module PgTriggers
  module Registry
    class Manager
      class << self
        def register(definition)
          trigger_name = definition.name
          existing = TriggerRegistry.find_by(trigger_name: trigger_name)

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
            TriggerRegistry.create!(attributes.merge(checksum: "placeholder"))
          end
        end

        def list
          TriggerRegistry.all
        end

        def enabled
          TriggerRegistry.enabled
        end

        def disabled
          TriggerRegistry.disabled
        end

        def for_table(table_name)
          TriggerRegistry.for_table(table_name)
        end

        def diff
          # Compare DSL definitions with actual database state
          # This will be implemented in the Drift::Detector
          Drift.detect
        end
      end
    end
  end
end
