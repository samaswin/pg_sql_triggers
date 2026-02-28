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

          errors
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
