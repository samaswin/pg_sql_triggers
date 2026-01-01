# frozen_string_literal: true

module PgSqlTriggers
  module Registry
    class Manager
      class << self
        # Request-level cache to avoid N+1 queries when loading multiple trigger files
        # This cache is cleared after each request/transaction to ensure data consistency
        def _registry_cache
          @_registry_cache ||= {}
        end

        def _clear_registry_cache
          @_registry_cache = {}
        end

        # Batch load existing triggers into cache to avoid N+1 queries
        # Call this before registering multiple triggers for better performance
        def preload_triggers(trigger_names)
          return if trigger_names.empty?

          # Find all triggers that aren't already cached
          uncached_names = trigger_names - _registry_cache.keys
          return if uncached_names.empty?

          # Batch load all uncached triggers in a single query
          PgSqlTriggers::TriggerRegistry.where(trigger_name: uncached_names).find_each do |trigger|
            _registry_cache[trigger.trigger_name] = trigger
          end
        end

        def register(definition)
          trigger_name = definition.name

          # Use cached lookup if available to avoid N+1 queries during trigger file loading
          # Explicitly check cache first to avoid query in some Ruby versions where ||= may evaluate RHS
          existing = if _registry_cache.key?(trigger_name)
                       _registry_cache[trigger_name]
                     else
                       _registry_cache[trigger_name] =
                         PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
                     end

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
            # Check if attributes have actually changed to avoid unnecessary queries
            attributes_changed = attributes.any? do |key, value|
              existing.send(key) != value
            end

            if attributes_changed
              begin
                existing.update!(attributes)
                # Update cache with the modified record (reload to get fresh data)
                reloaded = existing.reload
                _registry_cache[trigger_name] = reloaded
                reloaded
              rescue ActiveRecord::RecordNotFound
                # Cached record was deleted, create a new one
                new_record = PgSqlTriggers::TriggerRegistry.create!(attributes)
                _registry_cache[trigger_name] = new_record
                new_record
              end
            else
              # No changes, return cached record without any queries
              existing
            end
          else
            new_record = PgSqlTriggers::TriggerRegistry.create!(attributes)
            # Cache the newly created record
            _registry_cache[trigger_name] = new_record
            new_record
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
          return "placeholder" if function_body_value.blank?

          # Use field-concatenation algorithm (consistent with TriggerRegistry#calculate_checksum)
          require "digest"
          Digest::SHA256.hexdigest([
            definition.name,
            definition.table_name,
            definition.version,
            function_body_value,
            definition.condition || "",
            definition.timing || "before"
          ].join)
        end
      end
    end
  end
end
