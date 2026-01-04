# frozen_string_literal: true

module PgSqlTriggers
  module ErrorHandling
    extend ActiveSupport::Concern

    # Handles errors and formats them for display.
    # Returns a formatted error message for flash display.
    #
    # @param error [Exception] The error to format
    # @return [String] Formatted error message
    def format_error_for_flash(error)
      return error.to_s unless error.is_a?(PgSqlTriggers::Error)

      # Use user_message which includes recovery suggestions
      error.user_message
    end

    # Rescues from PgSqlTriggers errors and sets appropriate flash messages.
    #
    # @param error [Exception] The error to handle
    # @return [void]
    def rescue_pg_sql_triggers_error(error)
      Rails.logger.error("#{error.class.name}: #{error.message}")
      Rails.logger.error(error.backtrace.join("\n")) if Rails.env.development? && error.respond_to?(:backtrace)

      flash[:error] = if error.is_a?(PgSqlTriggers::Error)
                        format_error_for_flash(error)
                      else
                        "An unexpected error occurred: #{error.message}"
                      end
    end

    # Handles kill switch errors with appropriate flash message and redirect.
    #
    # @param error [PgSqlTriggers::KillSwitchError] The kill switch error
    # @param redirect_path [String, nil] Optional redirect path (defaults to root_path)
    # @return [void]
    def handle_kill_switch_error(error, redirect_path: nil)
      flash[:error] = error.message
      redirect_to redirect_path || root_path
    end

    # Handles standard errors with logging and flash message.
    #
    # @param error [Exception] The error to handle
    # @param operation [String] Description of the operation that failed
    # @param redirect_path [String, nil] Optional redirect path (defaults to root_path)
    # @return [void]
    def handle_standard_error(error, operation:, redirect_path: nil)
      Rails.logger.error("#{operation} failed: #{error.message}\n#{error.backtrace.join("\n")}")
      flash[:error] = "#{operation}: #{error.message}"
      redirect_to redirect_path || root_path
    end
  end
end
