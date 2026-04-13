# frozen_string_literal: true

module PgSqlTriggers
  # Normalizes trigger event lists (including PostgreSQL +UPDATE OF col1, col2+) for checksums so
  # {TriggerRegistry#calculate_checksum}, {Registry::Manager#calculate_checksum}, and
  # {Drift::Detector#calculate_db_checksum} stay aligned.
  module EventsChecksum
    module_function

    # @param defn [Hash] parsed registry +definition+ JSON (string or symbol keys)
    # @return [String] canonical token string, or empty when +events+ is missing/empty
    def canonical_from_definition(defn)
      hash = stringify(defn)
      events = Array(hash["events"]).map(&:to_s).map(&:downcase)
      return "" if events.empty?

      columns = normalized_columns(hash["columns"])
      build_tokens(events, columns).sort.join("|")
    end

    # @param definition_json [String, nil]
    def segment_from_definition_json(definition_json)
      return "" if definition_json.blank?

      canonical_from_definition(JSON.parse(definition_json))
    rescue JSON::ParserError
      ""
    end

    # @param trigger_def [String] +pg_get_triggerdef+ output
    def canonical_from_pg_triggerdef(trigger_def)
      return "" if trigger_def.blank?

      clause = extract_events_clause(trigger_def)
      return "" if clause.blank?

      parse_events_clause(clause).sort.join("|")
    end

    # SQL fragment for the event list (e.g. +INSERT OR UPDATE OF "email"+), preserving DSL event order.
    def events_sql_fragment(defn, quote_column:)
      hash = stringify(defn)
      events = Array(hash["events"]).map(&:to_s).map(&:downcase)
      columns = ordered_columns(hash["columns"])
      return "INSERT" if events.empty?

      events.map do |ev|
        if ev == "update" && columns.any?
          quoted = columns.map { |c| quote_column.call(c) }.join(", ")
          "UPDATE OF #{quoted}"
        else
          ev.upcase
        end
      end.join(" OR ")
    end

    def normalized_columns(raw)
      ordered_columns(raw).map(&:downcase).sort
    end

    def ordered_columns(raw)
      Array(raw).flatten.compact.map { |c| c.to_s.strip }.reject(&:empty?)
    end

    def build_tokens(events, sorted_lowercase_columns)
      cols_join = sorted_lowercase_columns.join(",")
      events.map do |ev|
        if ev == "update" && cols_join.present?
          "update:#{cols_join}"
        else
          ev
        end
      end
    end

    def extract_events_clause(trigger_def)
      s = trigger_def.to_s.squish
      m = s.match(/(?:BEFORE|AFTER|INSTEAD\s+OF)\s+(.+?)\s+ON\s+/i)
      return "" unless m

      m.captures.first.to_s.strip
    end

    def parse_events_clause(clause)
      clause.split(/\s+OR\s+/i).filter_map do |part|
        part = part.strip
        next if part.empty?

        um = part.match(/\AUPDATE\s+OF\s+(.+)\z/i)
        if um
          cols = um[1].split(",").map { |c| normalize_pg_identifier(c) }.sort
          "update:#{cols.join(',')}"
        else
          part.downcase
        end
      end
    end

    def normalize_pg_identifier(fragment)
      f = fragment.to_s.strip
      if f.start_with?('"') && f.end_with?('"') && f.length >= 2
        f[1...-1].gsub('""', '"').downcase
      else
        f.downcase
      end
    end

    def stringify(defn)
      return {} if defn.nil?

      defn.transform_keys(&:to_s)
    end
  end
end
