# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kill Switch Controller Integration", type: :controller do
  let(:logger) { instance_double(Logger) }

  before do
    # Setup default configuration
    allow(PgSqlTriggers).to receive_messages(kill_switch_enabled: true, kill_switch_environments: %i[production staging], kill_switch_confirmation_required: true, kill_switch_logger: logger, kill_switch_confirmation_pattern: ->(op) { "EXECUTE #{op.to_s.upcase}" })

    # Stub logger methods
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe PgSqlTriggers::MigrationsController do
    routes { PgSqlTriggers::Engine.routes }

    describe "POST #up" do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:ensure_migrations_table!)
        allow(PgSqlTriggers::Migrator).to receive(:pending_migrations).and_return([])
        allow(PgSqlTriggers::Migrator).to receive(:run_up)
      end

      # rubocop:disable RSpec/NestedGroups
      context "when in production environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        end

        it "blocks migration without confirmation" do
          post :up
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Kill switch is active/)
        end

        it "allows migration with correct confirmation" do
          post :up, params: { confirmation_text: "EXECUTE UI_MIGRATION_UP" }
          expect(response).to redirect_to(root_path)
          expect(flash[:info]).to match(/No pending migrations/) # or success message
        end

        it "blocks migration with incorrect confirmation" do
          post :up, params: { confirmation_text: "WRONG TEXT" }
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Invalid confirmation text/)
        end

        it "logs override when confirmation provided" do
          expect(logger).to receive(:warn).with(/OVERRIDDEN.*ui_migration_up/)
          post :up, params: { confirmation_text: "EXECUTE UI_MIGRATION_UP" }
        end
      end
      # rubocop:enable RSpec/NestedGroups

      # rubocop:disable RSpec/NestedGroups
      context "when in development environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        end

        it "allows migration without confirmation" do
          post :up
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to be_nil
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end

    describe "POST #down" do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:ensure_migrations_table!)
        allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(1)
        allow(PgSqlTriggers::Migrator).to receive(:run_down)
      end

      # rubocop:disable RSpec/NestedGroups
      context "when in production environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        end

        it "blocks rollback without confirmation" do
          post :down
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Kill switch is active/)
        end

        it "allows rollback with correct confirmation" do
          post :down, params: { confirmation_text: "EXECUTE UI_MIGRATION_DOWN" }
          expect(response).to redirect_to(root_path)
          expect(flash[:success]).to match(/Rolled back/) # or similar success message
        end

        it "logs the blocked attempt" do
          expect(logger).to receive(:error).with(/BLOCKED.*ui_migration_down/)
          post :down
        end
      end
      # rubocop:enable RSpec/NestedGroups

      # rubocop:disable RSpec/NestedGroups
      context "when in development environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        end

        it "allows rollback without confirmation" do
          post :down
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to be_nil
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end

    describe "POST #redo" do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:ensure_migrations_table!)
        allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(1)
        allow(PgSqlTriggers::Migrator).to receive(:run_down)
        allow(PgSqlTriggers::Migrator).to receive(:run_up)
      end

      # rubocop:disable RSpec/NestedGroups
      context "when in production environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        end

        it "blocks redo without confirmation" do
          post :redo
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Kill switch is active/)
        end

        it "allows redo with correct confirmation" do
          post :redo, params: { confirmation_text: "EXECUTE UI_MIGRATION_REDO" }
          expect(response).to redirect_to(root_path)
          expect(flash[:success]).to match(/redone/) # or similar success message
        end
      end
      # rubocop:enable RSpec/NestedGroups

      # rubocop:disable RSpec/NestedGroups
      context "when in development environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        end

        it "allows redo without confirmation" do
          post :redo
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to be_nil
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end
  end

  describe PgSqlTriggers::GeneratorController do
    routes { PgSqlTriggers::Engine.routes }

    describe "POST #create" do
      let(:valid_params) do
        {
          pg_sql_triggers_generator_form: {
            trigger_name: "test_trigger",
            table_name: "users",
            function_name: "test_function",
            version: "1",
            enabled: "false",
            events: ["insert"],
            environments: ["production"],
            function_body: "BEGIN RETURN NEW; END;"
          }
        }
      end

      before do
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(
          instance_double(PgSqlTriggers::DatabaseIntrospection, list_tables: ["users"])
        )
        allow(PgSqlTriggers::Generator::Service).to receive(:create_trigger).and_return(
          { success: true, migration_path: "test", dsl_path: "test" }
        )
        allow(PgSqlTriggers::Testing::SyntaxValidator).to receive(:new).and_return(
          instance_double(PgSqlTriggers::Testing::SyntaxValidator,
                          validate_function_syntax: { valid: true })
        )
      end

      # rubocop:disable RSpec/NestedGroups
      context "when in production environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        end

        it "blocks generation without confirmation" do
          post :create, params: valid_params
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Kill switch is active/)
        end

        it "allows generation with correct confirmation" do
          post :create, params: valid_params.merge(confirmation_text: "EXECUTE UI_TRIGGER_GENERATE")
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to be_nil
        end

        it "logs override when confirmation provided" do
          expect(logger).to receive(:warn).with(/OVERRIDDEN.*ui_trigger_generate/)
          post :create, params: valid_params.merge(confirmation_text: "EXECUTE UI_TRIGGER_GENERATE")
        end
      end
      # rubocop:enable RSpec/NestedGroups

      # rubocop:disable RSpec/NestedGroups
      context "when in development environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        end

        it "allows generation without confirmation" do
          post :create, params: valid_params
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to be_nil
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end
  end

  describe "Helper Methods" do
    controller(PgSqlTriggers::ApplicationController) do
      def test_action
        render plain: "kill_switch_active: #{kill_switch_active?}, env: #{current_environment}"
      end
    end

    before do
      routes.draw { get "test_action" => "anonymous#test_action" }
    end

    it "provides current_environment helper" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      get :test_action
      expect(response.body).to include("env: production")
    end

    it "provides kill_switch_active? helper" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      get :test_action
      expect(response.body).to include("kill_switch_active: true")
    end

    it "returns false for kill_switch_active? in development" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      get :test_action
      expect(response.body).to include("kill_switch_active: false")
    end
  end
end
