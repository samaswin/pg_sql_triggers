# frozen_string_literal: true

module PgSqlTriggers
  module Permissions
    class Checker
      def self.can?(actor, action, environment: nil)
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
          raise PgSqlTriggers::PermissionError,
                "Permission denied: #{action_sym} requires #{required_level} level access"
        end
        true
      end
      # rubocop:enable Naming/PredicateMethod
    end
  end
end
