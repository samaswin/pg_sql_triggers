# frozen_string_literal: true

require "json"
require "set"
require "tsort"

module PgSqlTriggers
  module Registry
    class Validator # rubocop:disable Metrics/ClassLength -- validation rules grouped in one class
      VALID_EVENTS = %w[insert update delete truncate].freeze
      VALID_TIMINGS = %w[before after instead_of].freeze
      VALID_FOR_EACH = %w[row statement].freeze

      def self.validate!
        errors = []
        dsl_triggers = PgSqlTriggers::TriggerRegistry.where(source: "dsl").to_a

        dsl_triggers.each do |trigger|
          errors.concat(validate_dsl_trigger(trigger))
        end

        errors.concat(collect_dependency_and_order_errors(dsl_triggers))

        return true if errors.empty?

        raise PgSqlTriggers::ValidationError.new(
          "Registry validation failed:\n#{errors.map { |e| "  - #{e}" }.join("\n")}",
          error_code: "VALIDATION_FAILED",
          context: { errors: errors }
        )
      end

      # Returns dependency-related errors (missing refs, cycles, incompatible pairs, name order).
      # Used by rake trigger:validate_order and included in {.validate!}.
      def self.trigger_order_validation_errors
        dsl_triggers = PgSqlTriggers::TriggerRegistry.where(source: "dsl").to_a
        collect_dependency_and_order_errors(dsl_triggers)
      end

      # Prerequisite and dependent DSL triggers for the trigger detail page.
      def self.related_triggers_for_show(trigger_record)
        empty = { prerequisites: [], dependents: [] }
        return empty if trigger_record.blank? || trigger_record.source != "dsl"

        defn = parse_definition(trigger_record.definition)
        prerequisite_names = normalize_depends_on(defn)
        prerequisites = prerequisite_names.filter_map do |dep_name|
          PgSqlTriggers::TriggerRegistry.find_by(source: "dsl", trigger_name: dep_name)
        end

        dependents = []
        PgSqlTriggers::TriggerRegistry.where(source: "dsl").find_each do |row|
          next if row.id == trigger_record.id

          other = parse_definition(row.definition)
          dependents << row if normalize_depends_on(other).include?(trigger_record.trigger_name)
        end

        {
          prerequisites: prerequisites.sort_by(&:trigger_name),
          dependents: dependents.sort_by(&:trigger_name)
        }
      end

      class << self
        private

        def normalize_depends_on(defn)
          raw = defn["depends_on"]
          list = case raw
                 when nil then []
                 when Array then raw
                 else [raw]
                 end
          list.flatten.compact.map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
        end

        def effective_timing(defn)
          return "after" if ActiveModel::Type::Boolean.new.cast(defn["constraint_trigger"])

          (defn["timing"].presence || "before").to_s
        end

        def for_each_level(defn)
          (defn["for_each"].presence || "row").to_s
        end

        def event_names_for_overlap(defn)
          Array(defn["events"]).to_set(&:to_s)
        end

        def compatibility_errors(child_row, child_defn, parent_row, parent_defn)
          child_name = child_row.trigger_name
          parent_name = parent_row.trigger_name
          errs = []
          if child_row.table_name != parent_row.table_name
            errs << "Trigger '#{child_name}': depends_on '#{parent_name}' must reference a trigger on the same " \
                    "table (#{child_row.table_name} vs #{parent_row.table_name})"
          end
          if effective_timing(child_defn) != effective_timing(parent_defn)
            errs << "Trigger '#{child_name}': depends_on '#{parent_name}' requires the same timing " \
                    "(#{effective_timing(child_defn)} vs #{effective_timing(parent_defn)})"
          end
          if for_each_level(child_defn) != for_each_level(parent_defn)
            errs << "Trigger '#{child_name}': depends_on '#{parent_name}' requires the same FOR EACH " \
                    "(#{for_each_level(child_defn)} vs #{for_each_level(parent_defn)})"
          end
          ch_ev = event_names_for_overlap(child_defn)
          pa_ev = event_names_for_overlap(parent_defn)
          if (ch_ev & pa_ev).empty?
            errs << "Trigger '#{child_name}': depends_on '#{parent_name}' requires overlapping events"
          end
          errs
        end

        def collect_dependency_and_order_errors(dsl_triggers)
          errors = []
          by_name = dsl_triggers.index_by(&:trigger_name)
          valid_edges = []

          dsl_triggers.each do |child|
            child_name = child.trigger_name
            child_defn = parse_definition(child.definition)
            deps = normalize_depends_on(child_defn)
            deps.each do |parent_name|
              if parent_name == child_name
                errors << "Trigger '#{child_name}': depends_on cannot reference itself"
                next
              end

              parent = by_name[parent_name]
              unless parent
                errors << "Trigger '#{child_name}': depends_on references unknown trigger '#{parent_name}'"
                next
              end

              parent_defn = parse_definition(parent.definition)
              compat = compatibility_errors(child, child_defn, parent, parent_defn)
              errors.concat(compat)
              next if compat.any?

              valid_edges << [parent_name, child_name]
              unless parent_name < child_name
                errors << "Trigger '#{child_name}': depends_on '#{parent_name}' must sort before " \
                          "'#{child_name}' alphabetically (PostgreSQL fires same-kind triggers in name order)"
              end
            end
          end

          errors.concat(cycle_dependency_errors(valid_edges))
          errors
        end

        def cycle_dependency_errors(edges)
          return [] if edges.empty?

          DependsOnSorter.new(edges).tsort
          []
        rescue TSort::Cyclic
          ["depends_on: circular dependency chain detected among DSL triggers"]
        end

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

          errors.concat(validate_update_columns(name, events, definition))

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

        def validate_deferral(name, definition, timing)
          constraint = ActiveModel::Type::Boolean.new.cast(definition["constraint_trigger"])
          deferrable_val = definition["deferrable"].presence&.to_s
          initially_val = definition["initially"].presence&.to_s

          errors = []
          errors.concat(constraint_deferral_errors(name, constraint, timing, definition))
          errors.concat(deferral_value_errors(name, deferrable_val, initially_val))
          errors
        end

        def constraint_deferral_errors(name, constraint, timing, definition)
          deferrable_val = definition["deferrable"].presence&.to_s
          initially_val = definition["initially"].presence&.to_s
          errors = []
          if (deferrable_val.present? || initially_val.present?) && !constraint
            errors << "Trigger '#{name}': deferrable/initially require constraint_trigger (CONSTRAINT TRIGGER)"
          end
          if constraint && timing.to_s != "after"
            errors << "Trigger '#{name}': constraint triggers must use after timing"
          end
          if constraint && events_include_truncate?(definition)
            errors << "Trigger '#{name}': constraint triggers cannot use TRUNCATE events"
          end
          errors
        end

        VALID_DEFERRABLE = %w[deferrable not_deferrable].freeze
        VALID_INITIALLY = %w[deferred immediate].freeze
        private_constant :VALID_DEFERRABLE, :VALID_INITIALLY

        def deferral_value_errors(name, deferrable_val, initially_val)
          errors = []
          if deferrable_val.present? && VALID_DEFERRABLE.exclude?(deferrable_val)
            errors << "Trigger '#{name}': invalid deferrable '#{deferrable_val}' (valid: #{VALID_DEFERRABLE.inspect})"
          end
          if initially_val.present? && VALID_INITIALLY.exclude?(initially_val)
            errors << "Trigger '#{name}': invalid initially '#{initially_val}' (valid: #{VALID_INITIALLY.inspect})"
          end
          if initially_val.present? && deferrable_val != "deferrable"
            errors << "Trigger '#{name}': initially requires deferrable to be 'deferrable'"
          end
          errors
        end

        def events_include_truncate?(definition)
          Array(definition["events"]).map(&:to_s).include?("truncate")
        end

        def validate_update_columns(name, events, definition)
          errs = []
          cols = Array(definition["columns"]).flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?)
          return errs if cols.empty?

          unless events.map(&:to_s).include?("update")
            errs << "Trigger '#{name}': columns require an update event " \
                    "(use on_update_of or include :update)"
          end

          cols.each do |col|
            next if col.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

            errs << "Trigger '#{name}': invalid column name #{col.inspect} (use simple SQL identifiers, no quoting)"
          end
          errs
        end

        def parse_definition(definition_json)
          return {} if definition_json.blank?

          JSON.parse(definition_json)
        rescue JSON::ParserError
          {}
        end
      end

      # Internal helper for cycle detection using Ruby's TSort.
      class DependsOnSorter # :nodoc:
        include TSort

        def initialize(edges)
          @adjacency = Hash.new { |h, k| h[k] = [] }
          edges.each { |(from, to)| @adjacency[from] << to }
          @nodes = (@adjacency.keys | @adjacency.values.flatten).uniq
        end

        def tsort_each_node(&block)
          @nodes.each(&block)
        end

        def tsort_each_child(node, &block)
          Array(@adjacency[node]).each(&block)
        end
      end
      private_constant :DependsOnSorter
    end
  end
end
