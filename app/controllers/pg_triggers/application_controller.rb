# frozen_string_literal: true

module PgTriggers
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    layout "pg_triggers/application"

    before_action :check_permissions

    private

    def check_permissions
      # Override this method in host application to implement custom permission checks
      true
    end

    def current_actor
      # Override this in host application to provide actual user
      {
        type: current_user_type,
        id: current_user_id
      }
    end

    def current_user_type
      "User"
    end

    def current_user_id
      "unknown"
    end
  end
end
