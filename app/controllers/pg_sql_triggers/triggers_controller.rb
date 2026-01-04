# frozen_string_literal: true

module PgSqlTriggers
  # Controller for managing individual triggers via web UI
  # Provides actions to enable and disable triggers
  class TriggersController < ApplicationController
    before_action :check_viewer_permission, only: [:show]
    before_action :check_operator_permission, only: %i[enable disable]
    before_action :check_admin_permission, only: %i[drop re_execute]
    before_action :set_trigger, only: %i[show enable disable drop re_execute]

    def show
      # Load trigger details and drift information
      @drift_info = calculate_drift_info
    end

    def enable
      # Check kill switch before enabling trigger
      check_kill_switch(operation: :ui_trigger_enable, confirmation: params[:confirmation_text])

      @trigger.enable!(confirmation: params[:confirmation_text], actor: current_actor)
      flash[:success] = "Trigger '#{@trigger.trigger_name}' enabled successfully."
      redirect_to redirect_path
    rescue PgSqlTriggers::KillSwitchError => e
      flash[:error] = e.message
      redirect_to redirect_path
    rescue StandardError => e
      Rails.logger.error("Enable failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to enable trigger: #{e.message}"
      redirect_to redirect_path
    end

    def disable
      # Check kill switch before disabling trigger
      check_kill_switch(operation: :ui_trigger_disable, confirmation: params[:confirmation_text])

      @trigger.disable!(confirmation: params[:confirmation_text], actor: current_actor)
      flash[:success] = "Trigger '#{@trigger.trigger_name}' disabled successfully."
      redirect_to redirect_path
    rescue PgSqlTriggers::KillSwitchError => e
      flash[:error] = e.message
      redirect_to redirect_path
    rescue StandardError => e
      Rails.logger.error("Disable failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to disable trigger: #{e.message}"
      redirect_to redirect_path
    end

    def drop
      # Validate required parameters
      if params[:reason].blank?
        flash[:error] = "Reason is required for dropping a trigger."
        redirect_to redirect_path
        return
      end

      # Check kill switch before dropping trigger
      check_kill_switch(operation: :trigger_drop, confirmation: params[:confirmation_text])

      # Drop the trigger
      @trigger.drop!(
        reason: params[:reason],
        confirmation: params[:confirmation_text],
        actor: current_actor
      )

      flash[:success] = "Trigger '#{@trigger.trigger_name}' dropped successfully."
      redirect_to dashboard_path
    rescue PgSqlTriggers::KillSwitchError => e
      flash[:error] = e.message
      redirect_to redirect_path
    rescue ArgumentError => e
      flash[:error] = "Invalid request: #{e.message}"
      redirect_to redirect_path
    rescue StandardError => e
      Rails.logger.error("Drop failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to drop trigger: #{e.message}"
      redirect_to redirect_path
    end

    def re_execute
      # Validate required parameters
      if params[:reason].blank?
        flash[:error] = "Reason is required for re-executing a trigger."
        redirect_to redirect_path
        return
      end

      # Check kill switch before re-executing trigger
      check_kill_switch(operation: :trigger_re_execute, confirmation: params[:confirmation_text])

      # Re-execute the trigger
      @trigger.re_execute!(
        reason: params[:reason],
        confirmation: params[:confirmation_text],
        actor: current_actor
      )

      flash[:success] = "Trigger '#{@trigger.trigger_name}' re-executed successfully."
      redirect_to redirect_path
    rescue PgSqlTriggers::KillSwitchError => e
      flash[:error] = e.message
      redirect_to redirect_path
    rescue ArgumentError => e
      flash[:error] = "Invalid request: #{e.message}"
      redirect_to redirect_path
    rescue StandardError => e
      Rails.logger.error("Re-execute failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to re-execute trigger: #{e.message}"
      redirect_to redirect_path
    end

    private

    def set_trigger
      @trigger = PgSqlTriggers::TriggerRegistry.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      flash[:error] = "Trigger not found."
      redirect_to root_path
    end

    def redirect_path
      # Redirect back to the referring page if possible, otherwise to dashboard
      params[:redirect_to].presence || request.referer || root_path
    end

    def calculate_drift_info
      # Get drift information for this trigger
      drift_reporter = PgSqlTriggers::Drift::Reporter.new
      drift_summary = drift_reporter.summary

      # Find this trigger in the drift summary
      drifted_triggers = drift_summary[:triggers] || []
      drift_data = drifted_triggers.find { |t| t[:trigger_name] == @trigger.trigger_name }

      {
        has_drift: drift_data.present?,
        drift_type: drift_data&.dig(:drift_type),
        expected_sql: drift_data&.dig(:expected_sql),
        actual_sql: drift_data&.dig(:actual_sql)
      }
    rescue StandardError => e
      Rails.logger.error("Failed to calculate drift: #{e.message}")
      { has_drift: false, drift_type: nil, expected_sql: nil, actual_sql: nil }
    end
  end
end
