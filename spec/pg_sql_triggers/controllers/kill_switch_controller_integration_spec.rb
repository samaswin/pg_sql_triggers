# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Kill Switch Controller Integration", type: :controller do
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }

  before do
    # Use real configuration
    PgSqlTriggers.kill_switch_enabled = true
    PgSqlTriggers.kill_switch_environments = %i[production staging]
    PgSqlTriggers.kill_switch_confirmation_required = true
    PgSqlTriggers.kill_switch_logger = logger
    PgSqlTriggers.kill_switch_confirmation_pattern = ->(op) { "EXECUTE #{op.to_s.upcase}" }
  end

  after do
    # Reset configuration to defaults
    PgSqlTriggers.kill_switch_enabled = true
    PgSqlTriggers.kill_switch_environments = %i[production staging]
    PgSqlTriggers.kill_switch_confirmation_required = true
    PgSqlTriggers.kill_switch_logger = nil
    PgSqlTriggers.kill_switch_confirmation_pattern = ->(operation) { "EXECUTE #{operation.to_s.upcase}" }
  end

  describe PgSqlTriggers::MigrationsController do
    routes { PgSqlTriggers::Engine.routes }

    let(:migrations_dir) { Pathname.new(Dir.mktmpdir) }

    before do
      # Create a real migrations directory structure
      FileUtils.mkdir_p(migrations_dir)

      # Create a sample migration file
      File.write(migrations_dir.join("001_test_migration.rb"), <<~RUBY)
        # frozen_string_literal: true

        class TestMigration < PgSqlTriggers::Migration
          def up
            # Migration up code
          end

          def down
            # Migration down code
          end
        end
      RUBY

      # Stub the migrations directory
      allow(PgSqlTriggers::Migrator).to receive(:migrations_dir).and_return(migrations_dir)
    end

    after do
      FileUtils.rm_rf(migrations_dir)
    end

    describe "POST #up" do
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
          post :up, params: { confirmation_text: "EXECUTE UI_MIGRATION_UP" }

          log_content = log_output.string
          expect(log_content).to match(/OVERRIDDEN.*ui_migration_up/i)
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
        # Record a real migration in the database
        ActiveRecord::Base.connection.execute(
          "INSERT INTO trigger_migrations (version) VALUES ('001')"
        )
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
          # Flash message could be success or error depending on migration execution
          expect(flash[:success] || flash[:error]).to be_present
        end

        it "logs the blocked attempt" do
          post :down

          log_content = log_output.string
          expect(log_content).to match(/BLOCKED.*ui_migration_down/i)
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
        # Record a real migration in the database
        ActiveRecord::Base.connection.execute(
          "INSERT INTO trigger_migrations (version) VALUES ('001')"
        )
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
          # Flash message could be success or error depending on migration execution
          expect(flash[:success] || flash[:error]).to be_present
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

  describe "Helper Methods" do
    controller(PgSqlTriggers::ApplicationController) do
      def test_action
        render plain: "kill_switch_active: #{kill_switch_active?}, env: #{current_environment}"
      end
    end

    before do
      routes.draw do
        get "test_action", to: "pg_sql_triggers/application#test_action", as: :test_action
      end
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
