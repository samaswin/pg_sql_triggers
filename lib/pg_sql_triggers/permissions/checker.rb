# frozen_string_literal: true

module PgSqlTriggers
  module Permissions
    class Checker
      def self.can?(actor, action, environment: nil)
        return true if action.nil? # Handle nil action gracefully
        action_sym = action.to_sym

        # If custom permission checker is configured, use it
        if PgSqlTriggers.permission_checker
          environment ||= PgSqlTriggers.default_environment.call if PgSqlTriggers.default_environment.respond_to?(:call)
          return PgSqlTriggers.permission_checker.call(actor, action_sym, environment)
        end

        # Default behavior: allow all permissions
        # This should be overridden in production via configuration
        true
      end

      # rubocop:disable Naming/PredicateMethod
      def self.check!(actor, action, environment: nil)
        unless can?(actor, action, environment: environment)
          action_sym = action.to_sym
          required_level = Permissions::ACTIONS[action_sym] || "unknown"
          message = "Permission denied: #{action_sym} requires #{required_level} level access"
          recovery = "Contact your administrator to request #{required_level} level access for this operation."

          raise PgSqlTriggers::PermissionError.new(
            message,
            error_code: "PERMISSION_DENIED",
            recovery_suggestion: recovery,
            context: { action: action_sym, required_role: required_level, environment: environment }
          )
        end
        true
      end
      # rubocop:enable Naming/PredicateMethod
    end
  end
end
