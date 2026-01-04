# frozen_string_literal: true

module PgSqlTriggers
  # Audit log model for tracking all trigger operations
  class AuditLog < PgSqlTriggers::ApplicationRecord
    self.table_name = "pg_sql_triggers_audit_log"

    # Scopes
    scope :for_trigger, ->(trigger_name) { where(trigger_name: trigger_name) }
    scope :for_operation, ->(operation) { where(operation: operation) }
    scope :for_environment, ->(env) { where(environment: env) }
    scope :successful, -> { where(status: "success") }
    scope :failed, -> { where(status: "failure") }
    scope :recent, -> { order(created_at: :desc) }

    # Validations
    validates :operation, presence: true
    validates :status, presence: true, inclusion: { in: %w[success failure] }

    # Class methods for logging operations
    class << self
      # Log a successful operation
      #
      # @param operation [Symbol, String] The operation being performed
      # @param trigger_name [String, nil] The trigger name (if applicable)
      # @param actor [Hash] Information about who performed the action
      # @param environment [String, nil] The environment
      # @param reason [String, nil] Reason for the operation
      # @param confirmation_text [String, nil] Confirmation text used
      # @param before_state [Hash, nil] State before operation
      # @param after_state [Hash, nil] State after operation
      # @param diff [String, nil] Diff information
      # rubocop:disable Metrics/ParameterLists
      def log_success(operation:, trigger_name: nil, actor: nil, environment: nil,
                      reason: nil, confirmation_text: nil, before_state: nil,
                      after_state: nil, diff: nil)
        create!(
          trigger_name: trigger_name,
          operation: operation.to_s,
          actor: serialize_actor(actor),
          environment: environment,
          status: "success",
          reason: reason,
          confirmation_text: confirmation_text,
          before_state: before_state,
          after_state: after_state,
          diff: diff
        )
      rescue StandardError => e
        Rails.logger.error("Failed to log audit entry: #{e.message}") if defined?(Rails.logger)
        nil
      end
      # rubocop:enable Metrics/ParameterLists

      # Log a failed operation
      #
      # @param operation [Symbol, String] The operation being performed
      # @param trigger_name [String, nil] The trigger name (if applicable)
      # @param actor [Hash] Information about who performed the action
      # @param environment [String, nil] The environment
      # @param error_message [String] Error message
      # @param reason [String, nil] Reason for the operation (if provided before failure)
      # @param confirmation_text [String, nil] Confirmation text used
      # @param before_state [Hash, nil] State before operation
      # rubocop:disable Metrics/ParameterLists
      def log_failure(operation:, error_message:, trigger_name: nil, actor: nil, environment: nil, reason: nil,
                      confirmation_text: nil, before_state: nil)
        create!(
          trigger_name: trigger_name,
          operation: operation.to_s,
          actor: serialize_actor(actor),
          environment: environment,
          status: "failure",
          error_message: error_message,
          reason: reason,
          confirmation_text: confirmation_text,
          before_state: before_state
        )
      rescue StandardError => e
        Rails.logger.error("Failed to log audit entry: #{e.message}") if defined?(Rails.logger)
        nil
      end
      # rubocop:enable Metrics/ParameterLists

      # Get audit log entries for a specific trigger
      #
      # @param trigger_name [String] The trigger name
      # @return [ActiveRecord::Relation] Audit log entries for the trigger
      def for_trigger_name(trigger_name)
        for_trigger(trigger_name).recent
      end

      private

      def serialize_actor(actor)
        return nil if actor.nil?

        if actor.is_a?(Hash)
          actor
        else
          { type: actor.class.name, id: actor.id.to_s }
        end
      end
    end
  end
end
