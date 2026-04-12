# frozen_string_literal: true

module PgSqlTriggers
  # Normalizes deferrable / initially metadata for checksum calculation so
  # {Registry::Manager}, {TriggerRegistry#calculate_checksum}, and {Drift::Detector}
  # stay aligned with PostgreSQL's pg_trigger flags.
  module DeferralChecksum
    module_function

    # @return [Array<String>] always three elements: constraint flag, deferrable mode, initially mode
    def parts(constraint_trigger:, deferrable:, initially:)
      constraint = ActiveModel::Type::Boolean.new.cast(constraint_trigger)
      return ["0", "", ""] unless constraint

      deferrable_sym =
        if deferrable.nil? || deferrable.to_s.strip.empty?
          nil
        else
          deferrable.to_sym
        end

      deferrable_key = deferrable_sym == :deferrable ? "deferrable" : "not_deferrable"

      initially_key = if deferrable_key == "deferrable"
                        case initially&.to_sym
                        when :deferred then "deferred"
                        else "immediate"
                        end
                      else
                        ""
                      end

      ["1", deferrable_key, initially_key]
    end

    # @param db_trigger [Hash] row from {Drift::DbQueries} including tgconstraint, tgdeferrable, tginitdeferred
    # @return [Array<String>] three elements matching {.parts}
    def parts_from_db(db_trigger)
      constraint = db_trigger["tgconstraint"].to_i.nonzero?
      return ["0", "", ""] unless constraint

      deferrable = ActiveModel::Type::Boolean.new.cast(db_trigger["tgdeferrable"])
      deferrable_key = deferrable ? "deferrable" : "not_deferrable"

      initially_key = if deferrable
                        ActiveModel::Type::Boolean.new.cast(db_trigger["tginitdeferred"]) ? "deferred" : "immediate"
                      else
                        ""
                      end

      ["1", deferrable_key, initially_key]
    end
  end
end
