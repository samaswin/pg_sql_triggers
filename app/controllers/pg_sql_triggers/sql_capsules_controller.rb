# frozen_string_literal: true

module PgSqlTriggers
  class SqlCapsulesController < ApplicationController
    before_action :check_admin_permission, only: [:execute]
    before_action :check_operator_permission, only: %i[new create show]
    before_action :load_capsule, only: %i[show execute]

    def show
      unless @capsule
        redirect_to new_sql_capsule_path, alert: "Capsule not found"
        return
      end

      @checksum = @capsule.checksum
      @can_execute = can_execute_capsule?
    end

    def new
      @capsule_name = params[:name] || ""
      @environment = params[:environment] || current_environment
      @purpose = params[:purpose] || ""
      @sql = params[:sql] || ""
    end

    def create
      # Strip whitespace from parameters
      @capsule_name = params[:name].to_s.strip
      @environment = params[:environment].to_s.strip
      @purpose = params[:purpose].to_s.strip
      @sql = params[:sql].to_s.strip

      capsule = build_capsule_from_params

      # Save the capsule to registry
      result = save_capsule_to_registry(capsule)

      if result[:success]
        redirect_to sql_capsule_path(id: @capsule_name),
                    notice: "SQL Capsule '#{capsule.name}' created successfully"
      else
        flash.now[:alert] = result[:message]
        render :new
      end
    rescue ArgumentError => e
      flash.now[:alert] = "Invalid capsule: #{e.message}"
      render :new
    end

    def execute
      unless @capsule
        redirect_to new_sql_capsule_path, alert: "Capsule not found"
        return
      end

      # Check kill switch with confirmation
      check_kill_switch(
        operation: :execute_sql_capsule,
        confirmation: params[:confirmation]
      )

      # Execute the capsule
      result = PgSqlTriggers::SQL::Executor.execute(
        @capsule,
        actor: current_actor,
        confirmation: params[:confirmation],
        dry_run: false
      )

      if result[:success]
        flash[:notice] = result[:message]
        redirect_to sql_capsule_path(id: params[:id])
      else
        flash[:alert] = result[:message]
        redirect_to sql_capsule_path(id: params[:id])
      end
    rescue PgSqlTriggers::KillSwitchError => e
      flash[:alert] = "Kill switch blocked execution: #{e.message}"
      redirect_to sql_capsule_path(id: params[:id])
    rescue PgSqlTriggers::PermissionError => e
      flash[:alert] = "Permission denied: #{e.message}"
      redirect_to sql_capsule_path(id: params[:id])
    rescue StandardError => e
      Rails.logger.error("SQL Capsule execution failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:alert] = "Execution failed: #{e.message}"
      redirect_to sql_capsule_path(id: params[:id])
    end

    private

    def check_admin_permission
      return if PgSqlTriggers::Permissions.can?(current_actor, :execute_sql)

      redirect_to dashboard_path, alert: "Insufficient permissions. Admin role required."
    end

    def check_operator_permission
      return if PgSqlTriggers::Permissions.can?(current_actor, :generate_trigger)

      redirect_to dashboard_path, alert: "Insufficient permissions. Operator role required."
    end

    def build_capsule_from_params
      PgSqlTriggers::SQL::Capsule.new(
        name: params[:name].to_s.strip,
        environment: params[:environment].to_s.strip,
        purpose: params[:purpose].to_s.strip,
        sql: params[:sql].to_s.strip
      )
    end

    def save_capsule_to_registry(capsule)
      # Check if capsule already exists
      existing = PgSqlTriggers::TriggerRegistry.find_by(
        trigger_name: capsule.registry_trigger_name,
        source: "manual_sql"
      )

      if existing
        return {
          success: false,
          message: "A capsule with this name already exists. Please choose a different name."
        }
      end

      # Create new registry entry
      registry_entry = PgSqlTriggers::TriggerRegistry.new(
        trigger_name: capsule.registry_trigger_name,
        table_name: "manual_sql_execution",
        version: Time.current.to_i,
        checksum: capsule.checksum,
        source: "manual_sql",
        function_body: capsule.sql,
        condition: capsule.purpose,
        environment: capsule.environment,
        enabled: false # Not executed yet
      )

      if registry_entry.save
        { success: true, message: "Capsule saved successfully" }
      else
        { success: false, message: "Failed to save capsule: #{registry_entry.errors.full_messages.join(', ')}" }
      end
    rescue StandardError => e
      Rails.logger.error("Failed to save capsule to registry: #{e.message}")
      { success: false, message: "Failed to save capsule: #{e.message}" }
    end

    def load_capsule
      return unless params[:id].present?

      @capsule = PgSqlTriggers::SQL::Executor.send(
        :load_capsule_from_registry,
        params[:id]
      )
    end

    def can_execute_capsule?
      PgSqlTriggers::Permissions.can?(current_actor, :execute_sql)
    end
  end
end
