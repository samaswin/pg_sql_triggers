# frozen_string_literal: true

module PgTriggers
  module Permissions
    class Checker
      def self.can?(actor, action, environment: nil)
        action_sym = action.to_sym

        # If custom permission checker is configured, use it
        if PgTriggers.permission_checker
          environment ||= PgTriggers.default_environment.call if PgTriggers.default_environment.respond_to?(:call)
          return PgTriggers.permission_checker.call(actor, action_sym, environment)
        end

        # Default behavior: allow all permissions
        # This should be overridden in production via configuration
        true
      end

      def self.check!(actor, action, environment: nil)
        unless can?(actor, action, environment: environment)
          action_sym = action.to_sym
          required_level = Permissions::ACTIONS[action_sym] || "unknown"
          raise PgTriggers::PermissionError,
                "Permission denied: #{action_sym} requires #{required_level} level access"
        end
        true
      end
    end
  end
end

