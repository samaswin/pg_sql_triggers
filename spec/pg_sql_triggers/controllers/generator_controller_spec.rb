# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe PgSqlTriggers::GeneratorController, type: :controller do
  routes { PgSqlTriggers::Engine.routes }

  let(:trigger_name) { "test_trigger_generator_controller_#{SecureRandom.hex(4)}" }
  let(:valid_params) do
    {
      pg_sql_triggers_generator_form: {
        trigger_name: trigger_name,
        table_name: "users",
        function_name: "test_function",
        function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        events: %w[insert update],
        version: 1,
        enabled: false,
        environments: ["production"]
      }
    }
  end

  let(:tmp_dir) { Dir.mktmpdir }
  let(:actor) { { type: "User", id: 1 } }

  before do
    # Configure view paths
    engine_view_path = PgSqlTriggers::Engine.root.join("app/views").to_s
    controller.prepend_view_path(engine_view_path) if controller.respond_to?(:prepend_view_path)

    # Mock Rails.root (acceptable for file system testing)
    allow(Rails).to receive(:root).and_return(Pathname.new(tmp_dir))

    # Set up current_actor via current_user_type/id (real controller actor setup)
    allow(controller).to receive_messages(current_user_type: actor[:type], current_user_id: actor[:id])

    # Create test tables for real database introspection
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR)")
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS posts (id SERIAL PRIMARY KEY, title VARCHAR, user_id INTEGER)")

    # Configure permissions to allow all by default (using real permission configuration)
    # Individual tests can override with with_permission_checker if needed
  end

  after do
    # Clean up test tables
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS users CASCADE")
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS posts CASCADE")

    # Clean up created trigger files
    FileUtils.rm_rf(tmp_dir)

    # Clean up registry entries
    PgSqlTriggers::TriggerRegistry.where(trigger_name: trigger_name).destroy_all if defined?(trigger_name)
    PgSqlTriggers::TriggerRegistry.where("trigger_name LIKE ?", "restored_trigger_%").destroy_all
  end

  describe "GET #new" do
    it "initializes a new form" do
      with_all_permissions_allowed do
        get :new
        expect(assigns(:form)).to be_a(PgSqlTriggers::Generator::Form)
        expect(assigns(:available_tables)).to include("users")
      end
    end

    context "when session contains form data" do
      let(:session_form_data) do
        {
          "trigger_name" => "restored_trigger",
          "table_name" => "users",
          "function_name" => "restored_function",
          "function_body" => "CREATE OR REPLACE FUNCTION restored_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
          "events" => %w[insert update],
          "version" => "2",
          "enabled" => "true",
          "timing" => "after",
          "condition" => "NEW.status = 'active'",
          "environments" => ["production"],
          "generate_function_stub" => "true"
        }
      end

      it "restores form data from session when available" do
        with_all_permissions_allowed do
          session[:generator_form_data] = session_form_data

          get :new

          form = assigns(:form)
          aggregate_failures do
            expect(form).to be_a(PgSqlTriggers::Generator::Form)
            expect(form.trigger_name).to eq("restored_trigger")
            expect(form.table_name).to eq("users")
            expect(form.function_name).to eq("restored_function")
            expect(form.function_body).to include("restored_function")
            expect(form.events).to include("insert", "update")
            # Version is stored as string in session, but Form converts it to integer
            expect(form.version.to_i).to eq(2)
            expect(form.enabled).to be true
            expect(form.timing).to eq("after")
            expect(form.condition).to eq("NEW.status = 'active'")
            expect(form.environments).to include("production")
          end
        end
      end

      it "clears session data after restoring" do
        with_all_permissions_allowed do
          session[:generator_form_data] = session_form_data

          get :new

          expect(session[:generator_form_data]).to be_nil
        end
      end

      it "initializes new form when session data is empty" do
        with_all_permissions_allowed do
          session[:generator_form_data] = nil

          get :new

          form = assigns(:form)
          expect(form).to be_a(PgSqlTriggers::Generator::Form)
          expect(form.trigger_name).to be_nil
        end
      end
    end
  end

  describe "POST #preview" do
    it "generates DSL and function content when form is valid" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          post :preview, params: valid_params
          expect(response).to render_template(:preview)
          expect(assigns(:dsl_content)).to be_present
          expect(assigns(:function_content)).to be_present
          expect(assigns(:file_paths)).to be_present
        end
      end
    end

    it "stores form data in session when form is valid" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          post :preview, params: valid_params

          expect(session[:generator_form_data]).to be_present
          expect(session[:generator_form_data]["trigger_name"]).to eq(trigger_name)
          expect(session[:generator_form_data]["table_name"]).to eq("users")
          expect(session[:generator_form_data]["function_name"]).to eq("test_function")
          expect(session[:generator_form_data]["events"]).to include("insert", "update")
        end
      end
    end

    it "does not store form data in session when form is invalid" do
      with_all_permissions_allowed do
        invalid_params = valid_params.deep_dup
        invalid_params[:pg_sql_triggers_generator_form][:trigger_name] = ""

        post :preview, params: invalid_params

        expect(response).to render_template(:new)
        expect(session[:generator_form_data]).to be_nil
      end
    end

    it "validates SQL function body" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          post :preview, params: valid_params
          expect(assigns(:sql_validation)).to be_present
          expect(assigns(:sql_validation)[:valid]).to be true
        end
      end
    end

    it "renders new template when form is invalid" do
      with_all_permissions_allowed do
        invalid_params = valid_params.deep_dup
        invalid_params[:pg_sql_triggers_generator_form][:trigger_name] = ""

        post :preview, params: invalid_params
        expect(response).to render_template(:new)
      end
    end

    context "when back_to_edit parameter is present" do
      it "stores form data in session and redirects to new" do
        with_all_permissions_allowed do
          params_with_back = valid_params.deep_dup
          params_with_back[:back_to_edit] = "1"

          post :preview, params: params_with_back

          expect(session[:generator_form_data]).to be_present
          expect(session[:generator_form_data]["trigger_name"]).to eq(trigger_name)
          expect(session[:generator_form_data]["table_name"]).to eq("users")
          expect(response).to redirect_to(new_generator_path)
        end
      end

      it "preserves all form fields including condition and timing" do
        with_all_permissions_allowed do
          params_with_back = valid_params.deep_dup
          params_with_back[:back_to_edit] = "1"
          params_with_back[:pg_sql_triggers_generator_form][:condition] = "NEW.id > 0"
          params_with_back[:pg_sql_triggers_generator_form][:timing] = "after"

          post :preview, params: params_with_back

          expect(session[:generator_form_data]["condition"]).to eq("NEW.id > 0")
          expect(session[:generator_form_data]["timing"]).to eq("after")
          expect(response).to redirect_to(new_generator_path)
        end
      end

      it "does not validate form when back_to_edit is present" do
        with_all_permissions_allowed do
          invalid_params = valid_params.deep_dup
          invalid_params[:back_to_edit] = "1"
          invalid_params[:pg_sql_triggers_generator_form][:trigger_name] = ""

          post :preview, params: invalid_params

          # Should still store and redirect even if form is invalid
          expect(session[:generator_form_data]).to be_present
          expect(response).to redirect_to(new_generator_path)
        end
      end
    end
  end

  describe "POST #create" do
    it "creates trigger when form is valid" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          post :create, params: valid_params
          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to include("successfully")

          # Verify files were created
          migration_files = Dir.glob(File.join(tmp_dir, "db/triggers/*_#{trigger_name}.rb"))
          dsl_files = Dir.glob(File.join(tmp_dir, "app/triggers/#{trigger_name}.rb"))
          expect(migration_files).not_to be_empty
          expect(dsl_files).not_to be_empty

          # Verify registry entry was created
          registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
          expect(registry).to be_present
        end
      end
    end

    it "clears session data after successful creation" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          session[:generator_form_data] = { "trigger_name" => "test" }

          post :create, params: valid_params

          expect(session[:generator_form_data]).to be_nil
        end
      end
    end

    it "does not clear session data when creation fails" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          session[:generator_form_data] = { "trigger_name" => "test" }

          # Use invalid SQL that still contains function name (to pass form validation)
          # but has syntax errors (to fail SQL validation)
          invalid_params = valid_params.deep_dup
          invalid_params[:pg_sql_triggers_generator_form][:function_body] = "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN INVALID SYNTAX HERE !!! RETURN NEW; END; $$ LANGUAGE plpgsql;"

          post :create, params: invalid_params

          expect(response).to render_template(:preview)
          # Session data should still be present (though it might be overwritten by the new form data)
          expect(session[:generator_form_data]).to be_present
        end
      end
    end

    it "shows error when creation fails" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          # Use invalid SQL that still contains function name (to pass form validation)
          # but has syntax errors (to fail SQL validation)
          invalid_params = valid_params.deep_dup
          invalid_params[:pg_sql_triggers_generator_form][:function_body] = "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN INVALID SYNTAX HERE !!! RETURN NEW; END; $$ LANGUAGE plpgsql;"

          post :create, params: invalid_params

          expect(response).to render_template(:preview)
          expect(flash[:alert]).to include("SQL validation failed")
        end
      end
    end

    it "validates SQL before creating" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          # Use invalid SQL syntax that still contains function name (to pass form validation)
          invalid_sql_params = valid_params.deep_dup
          invalid_sql_params[:pg_sql_triggers_generator_form][:function_body] = "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN INVALID SYNTAX HERE !!! RETURN NEW; END; $$ LANGUAGE plpgsql;"

          post :create, params: invalid_sql_params

          expect(response).to render_template(:preview)
          expect(flash[:alert]).to include("SQL validation failed")
        end
      end
    end

    context "with WHEN condition" do
      let(:params_with_condition) do
        valid_params.deep_dup.tap do |p|
          p[:pg_sql_triggers_generator_form][:condition] = "NEW.id > 0"
        end
      end

      it "validates WHEN condition when present" do
        with_all_permissions_allowed do
          with_kill_switch_disabled do
            post :create, params: params_with_condition
            expect(response).to redirect_to(root_path)
            expect(flash[:notice]).to include("successfully")

            # Verify registry entry was created
            registry = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: trigger_name)
            expect(registry).to be_present
            expect(registry.condition).to eq("NEW.id > 0")
          end
        end
      end

      it "rejects invalid WHEN condition syntax" do
        with_all_permissions_allowed do
          with_kill_switch_disabled do
            invalid_condition_params = valid_params.deep_dup.tap do |p|
              p[:pg_sql_triggers_generator_form][:condition] = "INVALID SQL SYNTAX !!!"
            end

            post :create, params: invalid_condition_params
            expect(response).to render_template(:preview)
            expect(flash[:alert]).to include("WHEN condition validation failed")
          end
        end
      end

      it "validates condition in preview" do
        with_all_permissions_allowed do
          with_kill_switch_disabled do
            post :preview, params: params_with_condition
            expect(assigns(:sql_validation)).to be_present
            # Condition validation should pass for valid condition
            expect(assigns(:sql_validation)[:valid]).to be true
          end
        end
      end

      it "validates condition syntax with real database" do
        with_all_permissions_allowed do
          with_kill_switch_disabled do
            # Use real validator to test actual SQL validation
            # The condition "NEW.id > 0" should be valid for the users table with id column
            post :create, params: params_with_condition

            # The validation should pass and redirect
            expect(response).to redirect_to(root_path)
            expect(flash[:notice]).to include("successfully")
          end
        end
      end

      it "rejects invalid condition syntax during database validation" do
        with_all_permissions_allowed do
          with_kill_switch_disabled do
            invalid_condition_params = valid_params.deep_dup.tap do |p|
              p[:pg_sql_triggers_generator_form][:condition] = "INVALID SQL SYNTAX !!!"
            end

            post :create, params: invalid_condition_params
            expect(response).to render_template(:preview)
            expect(flash[:alert]).to include("WHEN condition validation failed")
          end
        end
      end
    end

    it "skips condition validation when condition is blank" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          # valid_params doesn't include condition, so validation should skip it
          post :create, params: valid_params
          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to include("successfully")
        end
      end
    end

    it "handles condition attribute when column doesn't exist" do
      with_all_permissions_allowed do
        with_kill_switch_disabled do
          # Temporarily stub column_names to exclude condition (simulating older schema)
          original_column_names = PgSqlTriggers::TriggerRegistry.column_names
          allow(PgSqlTriggers::TriggerRegistry).to receive(:column_names).and_return(original_column_names - ["condition"])

          params_with_condition = valid_params.deep_dup.tap do |p|
            p[:pg_sql_triggers_generator_form][:condition] = "NEW.id > 0"
          end

          # Should not raise an error about unknown attribute 'condition'
          # The condition validation should still run, but the attribute won't be set on the registry object
          post :create, params: params_with_condition
          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to include("successfully")
        end
      end
    end
  end

  describe "POST #validate_table" do
    it "returns validation result for valid table" do
      with_all_permissions_allowed do
        post :validate_table, params: { table_name: "users" }, format: :json
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["valid"]).to be true
        expect(json["table_name"]).to eq("users")
      end
    end

    it "returns error for invalid table" do
      with_all_permissions_allowed do
        post :validate_table, params: { table_name: "nonexistent" }, format: :json
        json = JSON.parse(response.body)
        expect(json["valid"]).to be false
        expect(json["error"]).to include("not found")
      end
    end

    it "returns error for blank table name" do
      with_all_permissions_allowed do
        post :validate_table, params: { table_name: "" }, format: :json
        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["valid"]).to be false
      end
    end
  end

  describe "GET #tables" do
    it "returns list of tables as JSON" do
      with_all_permissions_allowed do
        get :tables, format: :json
        json = JSON.parse(response.body)
        expect(json["tables"]).to include("users", "posts")
      end
    end
  end

  describe "permission checks" do
    it "redirects when permission denied" do
      with_permission_checker(apply_trigger: false) do
        get :new
        expect(response).to redirect_to("/")
        expect(flash[:alert]).to include("Insufficient permissions")
      end
    end
  end
end
