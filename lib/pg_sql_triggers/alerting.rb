# frozen_string_literal: true

module PgSqlTriggers
  # Drift alerting: configurable callback when drift detection finds drifted, dropped, or unknown
  # triggers. Use with +trigger:check_drift+ or +PgSqlTriggers::Alerting.check_and_notify+.
  module Alerting
    ALERTABLE_STATES = [
      PgSqlTriggers::DRIFT_STATE_DRIFTED,
      PgSqlTriggers::DRIFT_STATE_DROPPED,
      PgSqlTriggers::DRIFT_STATE_UNKNOWN
    ].freeze

    class << self
      # @param result [Hash] a single drift result from {Drift::Detector}
      # @return [Boolean]
      def alertable?(result)
        ALERTABLE_STATES.include?(result[:state])
      end

      # @param results [Array<Hash>] drift results from {Drift::Detector.detect_all}
      # @return [Array<Hash>]
      def filter_alertable(results)
        results.select { |r| alertable?(r) }
      end

      # Runs drift detection for all triggers, invokes +PgSqlTriggers.drift_notifier+ when configured
      # and there is at least one alertable result, and emits +ActiveSupport::Notifications+ when
      # available.
      #
      # The notifier receives one argument: an Array of alertable result hashes (same shape as
      # {Drift::Detector}). For advanced use, a second keyword argument +all_results:+ is passed
      # with the full result set.
      #
      # @return [Hash] +:results+ (all), +:alertable+ (subset), +:notified+ (Boolean)
      def check_and_notify
        results = PgSqlTriggers::Drift::Detector.detect_all
        alertable = filter_alertable(results)
        notified = false

        payload = {
          results: results,
          alertable: alertable,
          alertable_count: alertable.size,
          total_count: results.size,
          notified: false
        }

        instrument("pg_sql_triggers.drift_check", payload) do
          if alertable.any? && PgSqlTriggers.drift_notifier
            PgSqlTriggers.drift_notifier.call(alertable, all_results: results)
            notified = true
          end
          payload[:notified] = notified
        end

        { results: results, alertable: alertable, notified: notified }
      end

      private

      def instrument(name, payload, &block)
        if defined?(ActiveSupport::Notifications)
          ActiveSupport::Notifications.instrument(name, payload, &block)
        else
          block.call
        end
      end
    end
  end
end
