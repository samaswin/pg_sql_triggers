# frozen_string_literal: true

module PgSqlTriggers
  module PermissionsHelper
    # Check if the current actor can perform an action
    #
    # @param action [Symbol, String] The action to check
    # @return [Boolean] True if the actor can perform the action
    def can?(action)
      PgSqlTriggers::Permissions.can?(current_actor, action, environment: current_environment)
    end

    # Check if the current actor can view triggers
    def can_view_triggers?
      can?(:view_triggers)
    end

    # Check if the current actor can enable/disable triggers
    def can_enable_disable_triggers?
      can?(:enable_trigger)
    end

    # Check if the current actor can drop triggers
    def can_drop_triggers?
      can?(:drop_trigger)
    end

    # Check if the current actor can execute SQL capsules
    def can_execute_sql?
      can?(:execute_sql)
    end

    # Check if the current actor can generate triggers
    def can_generate_triggers?
      can?(:generate_trigger)
    end

    # Check if the current actor can apply triggers (run migrations)
    def can_apply_triggers?
      can?(:apply_trigger)
    end
  end
end
