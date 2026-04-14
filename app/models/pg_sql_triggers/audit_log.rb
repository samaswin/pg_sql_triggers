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

    # Known keyword options accepted by log_success / log_failure, in addition to
    # +operation+ (required for both) and +error_message+ (required for log_failure).
    SUCCESS_ATTRS = %i[trigger_name actor environment reason confirmation_text
                       before_state after_state diff].freeze
    FAILURE_ATTRS = %i[trigger_name actor environment reason confirmation_text before_state].freeze

    # Class methods for logging operations
    class << self
      # Log a successful operation.
      #
      # Required: +operation:+ (Symbol/String).
      # Optional (all via keyword args): trigger_name, actor, environment, reason,
      # confirmation_text, before_state, after_state, diff.
      def log_success(operation:, **options)
        attrs = options.slice(*SUCCESS_ATTRS)
        create!(
          attrs.merge(
            operation: operation.to_s,
            actor: serialize_actor(attrs[:actor]),
            status: "success"
          )
        )
      rescue StandardError => e
        Rails.logger.error("Failed to log audit entry: #{e.message}") if defined?(Rails.logger)
        nil
      end

      # Log a failed operation.
      #
      # Required: +operation:+ (Symbol/String) and +error_message:+ (String).
      # Optional (all via keyword args): trigger_name, actor, environment, reason,
      # confirmation_text, before_state.
      def log_failure(operation:, error_message:, **options)
        attrs = options.slice(*FAILURE_ATTRS)
        create!(
          attrs.merge(
            operation: operation.to_s,
            actor: serialize_actor(attrs[:actor]),
            status: "failure",
            error_message: error_message
          )
        )
      rescue StandardError => e
        Rails.logger.error("Failed to log audit entry: #{e.message}") if defined?(Rails.logger)
        nil
      end

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
