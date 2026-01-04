# frozen_string_literal: true

module PgSqlTriggers
  module KillSwitchProtection
    extend ActiveSupport::Concern

    included do
      # Helper method available in views
      helper_method :kill_switch_active?, :expected_confirmation_text, :current_environment
    end

    # Checks if kill switch is active for the current environment.
    #
    # @return [Boolean] true if kill switch is active, false otherwise
    def kill_switch_active?
      PgSqlTriggers::SQL::KillSwitch.active?(environment: current_environment)
    end

    # Checks kill switch before executing a dangerous operation.
    # Raises KillSwitchError if the operation is blocked.
    #
    # @param operation [Symbol] The operation being performed
    # @param confirmation [String, nil] Optional confirmation text from params
    # @raise [PgSqlTriggers::KillSwitchError] If the operation is blocked
    # @return [true] If the operation is allowed
    def check_kill_switch(operation:, confirmation: nil)
      PgSqlTriggers::SQL::KillSwitch.check!(
        operation: operation,
        environment: current_environment,
        confirmation: confirmation,
        actor: current_actor
      )
    end

    # Before action to require kill switch override for an action.
    # Add to specific controller actions that need protection:
    #   before_action -> { require_kill_switch_override(:operation_name) }, only: [:dangerous_action]
    #
    # @param operation [Symbol] The operation name
    # @param confirmation [String, nil] Optional confirmation text
    # @raise [PgSqlTriggers::KillSwitchError] If the operation is blocked
    def require_kill_switch_override(operation, confirmation: nil)
      check_kill_switch(operation: operation, confirmation: confirmation)
    end

    # Returns the expected confirmation text for an operation (for use in views).
    #
    # @param operation [Symbol] The operation name
    # @return [String] The expected confirmation text
    def expected_confirmation_text(operation)
      if PgSqlTriggers.respond_to?(:kill_switch_confirmation_pattern) &&
         PgSqlTriggers.kill_switch_confirmation_pattern.respond_to?(:call)
        PgSqlTriggers.kill_switch_confirmation_pattern.call(operation)
      else
        "EXECUTE #{operation.to_s.upcase}"
      end
    end

    # Returns the current environment.
    #
    # @return [String] The current Rails environment
    def current_environment
      Rails.env
    end
  end
end

