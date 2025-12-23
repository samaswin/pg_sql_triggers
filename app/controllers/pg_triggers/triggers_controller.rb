# frozen_string_literal: true

module PgTriggers
  class TriggersController < ApplicationController
    before_action :set_trigger, only: [:show, :enable, :disable, :drop, :re_execute, :diff, :test_syntax, :test_dry_run, :test_safe_execute, :test_function]

    def index
      @triggers = TriggerRegistry.all.order(created_at: :desc)
    end

    def show
    end

    def enable
      @trigger.enable!
      redirect_to trigger_path(@trigger), notice: "Trigger enabled successfully"
    rescue StandardError => e
      redirect_to trigger_path(@trigger), alert: "Failed to enable trigger: #{e.message}"
    end

    def disable
      @trigger.disable!
      redirect_to trigger_path(@trigger), notice: "Trigger disabled successfully"
    rescue StandardError => e
      redirect_to trigger_path(@trigger), alert: "Failed to disable trigger: #{e.message}"
    end

    def drop
      reason = params[:reason]
      if reason.blank?
        redirect_to trigger_path(@trigger), alert: "Reason is required for destructive actions"
        return
      end

      @trigger.destroy!
      redirect_to triggers_path, notice: "Trigger dropped successfully"
    rescue StandardError => e
      redirect_to trigger_path(@trigger), alert: "Failed to drop trigger: #{e.message}"
    end

    def re_execute
      # This will re-apply the trigger to the database
      # Implementation will be in a separate service
      redirect_to trigger_path(@trigger), notice: "Trigger re-execution not yet implemented"
    end

    def diff
      # Show diff between DSL and actual database state
      @diff_result = PgTriggers::Drift.detect(@trigger.trigger_name)
    end

    def test_syntax
      validator = PgTriggers::Testing::SyntaxValidator.new(@trigger)
      @results = validator.validate_all

      render json: @results
    end

    def test_dry_run
      dry_run = PgTriggers::Testing::DryRun.new(@trigger)
      @results = dry_run.generate_sql

      render json: @results
    end

    def test_safe_execute
      executor = PgTriggers::Testing::SafeExecutor.new(@trigger)
      test_data = JSON.parse(params[:test_data]) rescue nil
      @results = executor.test_execute(test_data: test_data)

      render json: @results
    end

    def test_function
      tester = PgTriggers::Testing::FunctionTester.new(@trigger)
      @results = tester.test_function_only

      render json: @results
    end

    private

    def set_trigger
      @trigger = TriggerRegistry.find(params[:id])
    end
  end
end
