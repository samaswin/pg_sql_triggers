# frozen_string_literal: true

module PgSqlTriggers
  module PermissionChecking
    extend ActiveSupport::Concern

    included do
      # Helper methods available in views
      helper_method :current_actor, :can_view_triggers?, :can_enable_disable_triggers?,
                    :can_drop_triggers?, :can_execute_sql?, :can_generate_triggers?, :can_apply_triggers?
    end

    # Returns the current actor (user) performing the action.
    # Override this method in host application to provide actual user.
    #
    # @return [Hash] Actor information with :type and :id keys
    def current_actor
      {
        type: current_user_type,
        id: current_user_id
      }
    end

    # Returns the current user type.
    # Override this method in host application.
    #
    # @return [String] User type (default: "User")
    def current_user_type
      "User"
    end

    # Returns the current user ID.
    # Override this method in host application.
    #
    # @return [String] User ID (default: "unknown")
    def current_user_id
      "unknown"
    end

    # Checks if current actor has viewer permissions.
    #
    # @raise [ActionController::RedirectError] Redirects if permission denied
    def check_viewer_permission
      can_access = begin
        PgSqlTriggers::Permissions.can?(current_actor, :view_triggers, environment: current_environment)
      rescue StandardError => e
        Rails.logger.error("Permission check failed: #{e.message}\n#{e.backtrace.join("\n")}")
        false
      end
      unless can_access
        redirect_to root_path, alert: "Insufficient permissions. Viewer role required."
      end
    end

    # Checks if current actor has operator permissions (enable/disable/apply).
    #
    # @raise [ActionController::RedirectError] Redirects if permission denied
    def check_operator_permission
      can_access = begin
        PgSqlTriggers::Permissions.can?(current_actor, :enable_trigger, environment: current_environment)
      rescue StandardError => e
        Rails.logger.error("Permission check failed: #{e.message}\n#{e.backtrace.join("\n")}")
        false
      end
      unless can_access
        redirect_to root_path, alert: "Insufficient permissions. Operator role required."
      end
    end

    # Checks if current actor has admin permissions (drop/re-execute/execute SQL).
    #
    # @raise [ActionController::RedirectError] Redirects if permission denied
    def check_admin_permission
      can_access = begin
        PgSqlTriggers::Permissions.can?(current_actor, :drop_trigger, environment: current_environment)
      rescue StandardError => e
        Rails.logger.error("Permission check failed: #{e.message}\n#{e.backtrace.join("\n")}")
        false
      end
      unless can_access
        redirect_to root_path, alert: "Insufficient permissions. Admin role required."
      end
    end

    # Permission helper methods for views

    # @return [Boolean] true if current actor can view triggers
    def can_view_triggers?
      PgSqlTriggers::Permissions.can?(current_actor, :view_triggers, environment: current_environment)
    end

    # @return [Boolean] true if current actor can enable/disable triggers
    def can_enable_disable_triggers?
      PgSqlTriggers::Permissions.can?(current_actor, :enable_trigger, environment: current_environment)
    end

    # @return [Boolean] true if current actor can drop triggers
    def can_drop_triggers?
      PgSqlTriggers::Permissions.can?(current_actor, :drop_trigger, environment: current_environment)
    end

    # @return [Boolean] true if current actor can execute SQL capsules
    def can_execute_sql?
      PgSqlTriggers::Permissions.can?(current_actor, :execute_sql, environment: current_environment)
    end

    # @return [Boolean] true if current actor can generate triggers
    def can_generate_triggers?
      PgSqlTriggers::Permissions.can?(current_actor, :apply_trigger, environment: current_environment)
    end

    # @return [Boolean] true if current actor can apply triggers
    def can_apply_triggers?
      PgSqlTriggers::Permissions.can?(current_actor, :apply_trigger, environment: current_environment)
    end
  end
end

