# frozen_string_literal: true

require "json"

module PgSqlTriggers
  module Registry
    class Validator
      VALID_EVENTS = %w[insert update delete truncate].freeze
      VALID_TIMINGS = %w[before after instead_of].freeze
      VALID_FOR_EACH = %w[row statement].freeze

      def self.validate!
        errors = []

        PgSqlTriggers::TriggerRegistry.where(source: "dsl").find_each do |trigger|
          errors.concat(validate_dsl_trigger(trigger))
        end

        return true if errors.empty?

        raise PgSqlTriggers::ValidationError.new(
          "Registry validation failed:\n#{errors.map { |e| "  - #{e}" }.join("\n")}",
          error_code: "VALIDATION_FAILED",
          context: { errors: errors }
        )
      end
      class << self
        private

        def validate_dsl_trigger(trigger)
          errors = []
          name = trigger.trigger_name
          definition = parse_definition(trigger.definition)

          errors << "Trigger '#{name}': missing table_name" if definition["table_name"].blank?

          events = Array(definition["events"])
          if events.empty?
            errors << "Trigger '#{name}': events cannot be empty"
          else
            invalid = events - VALID_EVENTS
            if invalid.any?
              errors << "Trigger '#{name}': invalid events #{invalid.inspect} (valid: #{VALID_EVENTS.inspect})"
            end
          end

          errors << "Trigger '#{name}': missing function_name" if definition["function_name"].blank?

          timing = definition["timing"].to_s
          if timing.present? && VALID_TIMINGS.exclude?(timing)
            errors << "Trigger '#{name}': invalid timing '#{timing}' (valid: #{VALID_TIMINGS.inspect})"
          end

          for_each = definition["for_each"].to_s
          if for_each.present? && VALID_FOR_EACH.exclude?(for_each)
            errors << "Trigger '#{name}': invalid for_each '#{for_each}' (valid: #{VALID_FOR_EACH.inspect})"
          end

          errors.concat(validate_deferral(name, definition, timing))

          errors
        end

        def validate_deferral(name, definition, timing) # rubocop:disable Metrics/PerceivedComplexity
          errors = []
          constraint = ActiveModel::Type::Boolean.new.cast(definition["constraint_trigger"])
          deferrable_val = definition["deferrable"].presence&.to_s
          initially_val = definition["initially"].presence&.to_s

          if (deferrable_val.present? || initially_val.present?) && !constraint
            errors << "Trigger '#{name}': deferrable/initially require constraint_trigger (CONSTRAINT TRIGGER)"
          end

          if constraint && timing.to_s != "after"
            errors << "Trigger '#{name}': constraint triggers must use after timing"
          end
          if constraint && events_include_truncate?(definition)
            errors << "Trigger '#{name}': constraint triggers cannot use TRUNCATE events"
          end

          valid_deferrable = %w[deferrable not_deferrable]
          if deferrable_val.present? && valid_deferrable.exclude?(deferrable_val)
            errors << "Trigger '#{name}': invalid deferrable '#{deferrable_val}' (valid: #{valid_deferrable.inspect})"
          end

          valid_initially = %w[deferred immediate]
          if initially_val.present? && valid_initially.exclude?(initially_val)
            errors << "Trigger '#{name}': invalid initially '#{initially_val}' (valid: #{valid_initially.inspect})"
          end

          if initially_val.present? && deferrable_val != "deferrable"
            errors << "Trigger '#{name}': initially requires deferrable to be 'deferrable'"
          end

          errors
        end # rubocop:enable Metrics/PerceivedComplexity

        def events_include_truncate?(definition)
          Array(definition["events"]).map(&:to_s).include?("truncate")
        end

        def parse_definition(definition_json)
          return {} if definition_json.blank?

          JSON.parse(definition_json)
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
