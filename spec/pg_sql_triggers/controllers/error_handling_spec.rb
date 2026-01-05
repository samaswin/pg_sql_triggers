# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::ErrorHandling, type: :controller do
  # Create a test controller that includes the ErrorHandling concern
  controller(PgSqlTriggers::ApplicationController) do
    def index
      render plain: "OK"
    end
  end

  # Use existing engine routes
  routes { PgSqlTriggers::Engine.routes }

  before do
    allow(Rails.logger).to receive(:error)
    allow(controller).to receive(:redirect_to)
    allow(controller).to receive_messages(root_path: "/", flash: {})
  end

  describe "#format_error_for_flash" do
    context "when error is a PgSqlTriggers::Error" do
      let(:error) do
        PgSqlTriggers::Error.new(
          "Custom error message",
          recovery_suggestion: "Try again"
        )
      end

      it "returns the user_message which includes recovery suggestions" do
        result = controller.send(:format_error_for_flash, error)
        expect(result).to include("Custom error message")
        expect(result).to include("Recovery: Try again")
      end

      it "calls user_message on the error" do
        allow(error).to receive(:user_message).and_return("Formatted message")
        result = controller.send(:format_error_for_flash, error)
        expect(result).to eq("Formatted message")
        expect(error).to have_received(:user_message)
      end
    end

    context "when error is not a PgSqlTriggers::Error" do
      let(:error) { StandardError.new("Standard error message") }

      it "returns error.to_s" do
        result = controller.send(:format_error_for_flash, error)
        expect(result).to eq("Standard error message")
      end

      it "handles errors without messages" do
        error_without_message = StandardError.new
        result = controller.send(:format_error_for_flash, error_without_message)
        # StandardError.to_s returns the class name when no message is provided
        expect(result).to eq("StandardError")
      end
    end

    context "when error is a different type" do
      let(:error) { ArgumentError.new("Invalid argument") }

      it "returns error.to_s" do
        result = controller.send(:format_error_for_flash, error)
        expect(result).to eq("Invalid argument")
      end
    end
  end

  describe "#rescue_pg_sql_triggers_error" do
    let(:flash) { {} }

    before do
      allow(controller).to receive(:flash).and_return(flash)
    end

    context "when error is a PgSqlTriggers::Error" do
      let(:error) do
        error = PgSqlTriggers::Error.new(
          "PgSqlTriggers error message",
          recovery_suggestion: "Fix it"
        )
        # Ensure error has a backtrace for testing
        allow(error).to receive(:backtrace).and_return(["line1.rb:1", "line2.rb:2"])
        error
      end

      it "sets flash[:error] using format_error_for_flash" do
        controller.send(:rescue_pg_sql_triggers_error, error)
        expect(flash[:error]).to include("PgSqlTriggers error message")
        expect(flash[:error]).to include("Recovery: Fix it")
      end

      it "logs the error" do
        controller.send(:rescue_pg_sql_triggers_error, error)
        expect(Rails.logger).to have_received(:error).with(
          "#{error.class.name}: PgSqlTriggers error message"
        )
      end

      context "when in development environment" do
        before do
          allow(Rails.env).to receive(:development?).and_return(true)
        end

        it "logs the backtrace" do
          controller.send(:rescue_pg_sql_triggers_error, error)
          # Should log error message and backtrace (2 calls)
          expect(Rails.logger).to have_received(:error).twice
          expect(Rails.logger).to have_received(:error).with(
            "#{error.class.name}: PgSqlTriggers error message"
          )
          # Second call should be the backtrace (a string with newlines)
          expect(Rails.logger).to have_received(:error).with(a_string_matching(/\n/))
        end
      end

      context "when not in development environment" do
        before do
          allow(Rails.env).to receive(:development?).and_return(false)
        end

        it "does not log the backtrace" do
          controller.send(:rescue_pg_sql_triggers_error, error)
          expect(Rails.logger).to have_received(:error).once
          expect(Rails.logger).to have_received(:error).with(
            "#{error.class.name}: PgSqlTriggers error message"
          )
        end
      end

      context "when error does not respond to backtrace" do
        let(:error_without_backtrace) do
          error = PgSqlTriggers::Error.new("Error message")
          allow(error).to receive(:respond_to?).with(:backtrace).and_return(false)
          # Ensure backtrace is nil to avoid join call
          allow(error).to receive(:backtrace).and_return(nil)
          error
        end

        before do
          allow(Rails.env).to receive(:development?).and_return(true)
        end

        it "does not log the backtrace" do
          controller.send(:rescue_pg_sql_triggers_error, error_without_backtrace)
          expect(Rails.logger).to have_received(:error).with(
            "#{error_without_backtrace.class.name}: Error message"
          )
        end
      end
    end

    context "when error is not a PgSqlTriggers::Error" do
      let(:error) do
        error = StandardError.new("Unexpected error occurred")
        # Ensure error has a backtrace for testing
        allow(error).to receive(:backtrace).and_return(["line1.rb:1", "line2.rb:2"])
        error
      end

      it "sets flash[:error] with a generic message" do
        controller.send(:rescue_pg_sql_triggers_error, error)
        expect(flash[:error]).to eq("An unexpected error occurred: Unexpected error occurred")
      end

      it "logs the error" do
        controller.send(:rescue_pg_sql_triggers_error, error)
        expect(Rails.logger).to have_received(:error).with(
          "StandardError: Unexpected error occurred"
        )
      end

      context "when in development environment" do
        before do
          allow(Rails.env).to receive(:development?).and_return(true)
        end

        it "logs the backtrace" do
          controller.send(:rescue_pg_sql_triggers_error, error)
          # Should log error message and backtrace (2 calls)
          expect(Rails.logger).to have_received(:error).twice
          expect(Rails.logger).to have_received(:error).with(
            "StandardError: Unexpected error occurred"
          )
          # Second call should be the backtrace (a string with newlines)
          expect(Rails.logger).to have_received(:error).with(a_string_matching(/\n/))
        end
      end

      context "when error does not respond to backtrace" do
        let(:error_without_backtrace) do
          error = StandardError.new("Error")
          allow(error).to receive(:respond_to?).with(:backtrace).and_return(false)
          # Ensure backtrace is nil to avoid join call
          allow(error).to receive(:backtrace).and_return(nil)
          error
        end

        before do
          allow(Rails.env).to receive(:development?).and_return(true)
        end

        it "does not attempt to log backtrace" do
          controller.send(:rescue_pg_sql_triggers_error, error_without_backtrace)
          expect(Rails.logger).to have_received(:error).with(
            "StandardError: Error"
          )
        end
      end
    end
  end

  describe "#handle_kill_switch_error" do
    let(:error) { PgSqlTriggers::KillSwitchError.new("Kill switch is active") }
    let(:flash) { {} }

    before do
      allow(controller).to receive(:flash).and_return(flash)
    end

    context "when redirect_path is provided" do
      it "sets flash[:error] with the error message" do
        controller.send(:handle_kill_switch_error, error, redirect_path: "/custom/path")
        expect(flash[:error]).to eq("Kill switch is active")
      end

      it "redirects to the provided path" do
        controller.send(:handle_kill_switch_error, error, redirect_path: "/custom/path")
        expect(controller).to have_received(:redirect_to).with("/custom/path")
      end
    end

    context "when redirect_path is not provided" do
      it "sets flash[:error] with the error message" do
        controller.send(:handle_kill_switch_error, error)
        expect(flash[:error]).to eq("Kill switch is active")
      end

      it "redirects to root_path" do
        controller.send(:handle_kill_switch_error, error)
        expect(controller).to have_received(:redirect_to).with("/")
      end
    end

    context "when redirect_path is nil explicitly" do
      it "redirects to root_path" do
        controller.send(:handle_kill_switch_error, error, redirect_path: nil)
        expect(controller).to have_received(:redirect_to).with("/")
      end
    end
  end

  describe "#handle_standard_error" do
    let(:error) { StandardError.new("Operation failed") }
    let(:flash) { {} }

    before do
      allow(controller).to receive(:flash).and_return(flash)
      allow(error).to receive(:backtrace).and_return(%w[line1 line2])
    end

    context "when redirect_path is provided" do
      it "sets flash[:error] with operation and error message" do
        controller.send(:handle_standard_error, error, operation: "Test operation", redirect_path: "/custom/path")
        expect(flash[:error]).to eq("Test operation: Operation failed")
      end

      it "logs the error with operation and backtrace" do
        controller.send(:handle_standard_error, error, operation: "Test operation", redirect_path: "/custom/path")
        expect(Rails.logger).to have_received(:error).with(
          include("Test operation failed: Operation failed")
        )
        expect(Rails.logger).to have_received(:error).with(
          include("line1\nline2")
        )
      end

      it "redirects to the provided path" do
        controller.send(:handle_standard_error, error, operation: "Test operation", redirect_path: "/custom/path")
        expect(controller).to have_received(:redirect_to).with("/custom/path")
      end
    end

    context "when redirect_path is not provided" do
      it "sets flash[:error] with operation and error message" do
        controller.send(:handle_standard_error, error, operation: "Test operation")
        expect(flash[:error]).to eq("Test operation: Operation failed")
      end

      it "logs the error with operation and backtrace" do
        controller.send(:handle_standard_error, error, operation: "Test operation")
        expect(Rails.logger).to have_received(:error).with(
          include("Test operation failed: Operation failed")
        )
        expect(Rails.logger).to have_received(:error).with(
          include("line1\nline2")
        )
      end

      it "redirects to root_path" do
        controller.send(:handle_standard_error, error, operation: "Test operation")
        expect(controller).to have_received(:redirect_to).with("/")
      end
    end

    context "when redirect_path is nil explicitly" do
      it "redirects to root_path" do
        controller.send(:handle_standard_error, error, operation: "Test operation", redirect_path: nil)
        expect(controller).to have_received(:redirect_to).with("/")
      end
    end

    context "with different operation names" do
      it "includes the operation name in the flash message" do
        controller.send(:handle_standard_error, error, operation: "Enable trigger")
        expect(flash[:error]).to eq("Enable trigger: Operation failed")
      end

      it "includes the operation name in the log message" do
        controller.send(:handle_standard_error, error, operation: "Disable trigger")
        expect(Rails.logger).to have_received(:error).with(
          include("Disable trigger failed: Operation failed")
        )
      end
    end

    context "when error has a multi-line backtrace" do
      before do
        allow(error).to receive(:backtrace).and_return(["line1.rb:1", "line2.rb:2", "line3.rb:3"])
      end

      it "joins backtrace with newlines" do
        controller.send(:handle_standard_error, error, operation: "Test")
        expect(Rails.logger).to have_received(:error).with(
          include("line1.rb:1\nline2.rb:2\nline3.rb:3")
        )
      end
    end
  end
end
