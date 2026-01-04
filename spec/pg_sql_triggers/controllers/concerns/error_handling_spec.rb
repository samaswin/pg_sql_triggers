# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::ErrorHandling, type: :controller, uses_database: false do
  # Create a test controller class that includes the concern
  controller_class = Class.new(PgSqlTriggers::ApplicationController) do
    include PgSqlTriggers::ErrorHandling
  end

  controller(controller_class) do
    def index
      render plain: "OK"
    end
  end

  routes { PgSqlTriggers::Engine.routes }

  before do
    routes.draw do
      get "test_index", to: "anonymous#index"
    end
  end

  describe "#format_error_for_flash" do
    context "when error is a PgSqlTriggers::Error" do
      let(:error) do
        PgSqlTriggers::KillSwitchError.new(
          "Kill switch is active",
          error_code: "KILL_SWITCH_ACTIVE",
          recovery_suggestion: "Provide confirmation",
          context: { operation: :test }
        )
      end

      it "returns user_message from error" do
        expect(controller.send(:format_error_for_flash, error)).to eq(error.user_message)
      end

      it "includes recovery suggestion in message" do
        message = controller.send(:format_error_for_flash, error)
        expect(message).to include("Kill switch is active")
        expect(message).to include("Recovery:")
      end
    end

    context "when error is not a PgSqlTriggers::Error" do
      let(:error) { StandardError.new("Generic error") }

      it "returns error message as string" do
        expect(controller.send(:format_error_for_flash, error)).to eq("Generic error")
      end
    end

    context "when error has no recovery suggestion" do
      let(:error) do
        PgSqlTriggers::Error.new("Simple error")
      end

      it "returns message without recovery section" do
        message = controller.send(:format_error_for_flash, error)
        expect(message).to include("Simple error")
      end
    end
  end

  describe "#rescue_pg_sql_triggers_error" do
    let(:error) { PgSqlTriggers::KillSwitchError.new("Kill switch active") }

    before do
      allow(Rails.logger).to receive(:error)
      allow(controller).to receive(:flash).and_return({})
    end

    it "logs the error" do
      expect(Rails.logger).to receive(:error).with(match(/KillSwitchError/))
      expect(Rails.logger).to receive(:error).with(match(/Kill switch active/))
      controller.send(:rescue_pg_sql_triggers_error, error)
    end

    it "logs backtrace in development" do
      allow(Rails.env).to receive(:development?).and_return(true)
      allow(error).to receive(:backtrace).and_return(["line1", "line2"])
      expect(Rails.logger).to receive(:error).with("line1\nline2")
      controller.send(:rescue_pg_sql_triggers_error, error)
    end

    it "does not log backtrace in non-development" do
      allow(Rails.env).to receive(:development?).and_return(false)
      expect(Rails.logger).not_to receive(:error).with(match(/\n/))
      controller.send(:rescue_pg_sql_triggers_error, error)
    end

    it "sets flash error with formatted message for PgSqlTriggers::Error" do
      flash = {}
      allow(controller).to receive(:flash).and_return(flash)
      controller.send(:rescue_pg_sql_triggers_error, error)
      expect(flash[:error]).to eq(error.user_message)
    end

    it "sets flash error with generic message for non-PgSqlTriggers errors" do
      flash = {}
      allow(controller).to receive(:flash).and_return(flash)
      generic_error = StandardError.new("Something went wrong")
      controller.send(:rescue_pg_sql_triggers_error, generic_error)
      expect(flash[:error]).to eq("An unexpected error occurred: Something went wrong")
    end

    it "handles errors without backtrace" do
      error_without_backtrace = PgSqlTriggers::Error.new("No backtrace")
      allow(error_without_backtrace).to receive(:respond_to?).with(:backtrace).and_return(false)
      expect { controller.send(:rescue_pg_sql_triggers_error, error_without_backtrace) }.not_to raise_error
    end
  end

  describe "#handle_kill_switch_error" do
    let(:error) { PgSqlTriggers::KillSwitchError.new("Kill switch active") }

    before do
      allow(controller).to receive(:redirect_to)
      allow(controller).to receive(:flash).and_return({})
    end

    it "sets flash error with error message" do
      flash = {}
      allow(controller).to receive(:flash).and_return(flash)
      controller.send(:handle_kill_switch_error, error)
      expect(flash[:error]).to eq("Kill switch active")
    end

    it "redirects to root_path by default" do
      expect(controller).to receive(:redirect_to).with(root_path)
      controller.send(:handle_kill_switch_error, error)
    end

    it "redirects to custom path when provided" do
      custom_path = "/custom/path"
      expect(controller).to receive(:redirect_to).with(custom_path)
      controller.send(:handle_kill_switch_error, error, redirect_path: custom_path)
    end
  end

  describe "#handle_standard_error" do
    let(:error) { StandardError.new("Operation failed") }

    before do
      allow(Rails.logger).to receive(:error)
      allow(controller).to receive(:redirect_to)
      allow(controller).to receive(:flash).and_return({})
      allow(error).to receive(:backtrace).and_return(["line1", "line2"])
    end

    it "logs the error with operation and backtrace" do
      expect(Rails.logger).to receive(:error).with(match(/Test operation failed/))
      expect(Rails.logger).to receive(:error).with("line1\nline2")
      controller.send(:handle_standard_error, error, operation: "Test operation")
    end

    it "sets flash error with operation and message" do
      flash = {}
      allow(controller).to receive(:flash).and_return(flash)
      controller.send(:handle_standard_error, error, operation: "Test operation")
      expect(flash[:error]).to eq("Test operation: Operation failed")
    end

    it "redirects to root_path by default" do
      expect(controller).to receive(:redirect_to).with(root_path)
      controller.send(:handle_standard_error, error, operation: "Test operation")
    end

    it "redirects to custom path when provided" do
      custom_path = "/custom/path"
      expect(controller).to receive(:redirect_to).with(custom_path)
      controller.send(:handle_standard_error, error, operation: "Test operation", redirect_path: custom_path)
    end

    it "handles errors without backtrace" do
      error_without_backtrace = StandardError.new("No backtrace")
      allow(error_without_backtrace).to receive(:backtrace).and_return(nil)
      expect { controller.send(:handle_standard_error, error_without_backtrace, operation: "Test") }.not_to raise_error
    end
  end
end

