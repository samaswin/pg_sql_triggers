# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers::GeneratorController, type: :controller do
  routes { PgTriggers::Engine.routes }

  let(:valid_params) do
    {
      pg_sql_triggers_generator_form: {
        trigger_name: "test_trigger",
        table_name: "users",
        function_name: "test_function",
        function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        events: ["insert", "update"],
        version: 1,
        enabled: false,
        environments: ["production"]
      }
    }
  end

  before do
    # Mock Rails.root
    allow(Rails).to receive(:root).and_return(Pathname.new(Dir.mktmpdir))
    allow(controller).to receive(:current_actor).and_return({ type: "User", id: 1 })

    # Create test table
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR)")
    
    # Mock permissions
    allow(PgTriggers::Permissions).to receive(:can?).and_return(true)
  end

  after do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS users CASCADE")
  end

  describe "GET #new" do
    it "initializes a new form" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users", "posts"])
      get :new
      expect(assigns(:form)).to be_a(PgTriggers::Generator::Form)
      expect(assigns(:available_tables)).to include("users")
    end
  end

  describe "POST #preview" do
    it "generates DSL and function content when form is valid" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      allow(PgTriggers::Testing::SyntaxValidator).to receive_message_chain(:new, :validate_function_syntax).and_return({ valid: true })

      post :preview, params: valid_params
      expect(assigns(:dsl_content)).to be_present
      expect(assigns(:function_content)).to be_present
      expect(assigns(:file_paths)).to be_present
    end

    it "validates SQL function body" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      validator = instance_double(PgTriggers::Testing::SyntaxValidator)
      allow(PgTriggers::Testing::SyntaxValidator).to receive(:new).and_return(validator)
      allow(validator).to receive(:validate_function_syntax).and_return({ valid: true })

      post :preview, params: valid_params
      expect(assigns(:sql_validation)).to be_present
    end

    it "renders new template when form is invalid" do
      invalid_params = valid_params.deep_dup
      invalid_params[:pg_sql_triggers_generator_form][:trigger_name] = ""
      
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])
      post :preview, params: invalid_params
      expect(response).to render_template(:new)
    end
  end

  describe "POST #create" do
    it "creates trigger when form is valid" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      allow(PgTriggers::Testing::SyntaxValidator).to receive_message_chain(:new, :validate_function_syntax).and_return({ valid: true })
      allow(PgTriggers::Generator::Service).to receive(:create_trigger).and_return({
        success: true,
        migration_path: "db/triggers/20231215120001_test_trigger.rb",
        dsl_path: "app/triggers/test_trigger.rb"
      })

      post :create, params: valid_params
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to include("successfully")
    end

    it "shows error when creation fails" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      allow(PgTriggers::Testing::SyntaxValidator).to receive_message_chain(:new, :validate_function_syntax).and_return({ valid: true })
      allow(PgTriggers::Generator::Service).to receive(:create_trigger).and_return({
        success: false,
        error: "Permission denied"
      })
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])

      post :create, params: valid_params
      expect(response).to render_template(:new)
      expect(flash[:alert]).to include("Generation failed")
    end

    it "validates SQL before creating" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      validator = instance_double(PgTriggers::Testing::SyntaxValidator)
      allow(PgTriggers::Testing::SyntaxValidator).to receive(:new).and_return(validator)
      allow(validator).to receive(:validate_function_syntax).and_return({ valid: false, error: "Syntax error" })
      allow(PgTriggers::Generator::Service).to receive(:generate_dsl).and_return("# DSL code")
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])

      post :create, params: valid_params
      expect(response).to render_template(:preview)
      expect(flash[:alert]).to include("SQL validation failed")
    end
  end

  describe "POST #validate_table" do
    it "returns validation result for valid table" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({
        valid: true,
        table_name: "users",
        column_count: 2
      })

      post :validate_table, params: { table_name: "users" }, format: :json
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["valid"]).to be true
    end

    it "returns error for invalid table" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({
        valid: false,
        error: "Table not found"
      })

      post :validate_table, params: { table_name: "nonexistent" }, format: :json
      json = JSON.parse(response.body)
      expect(json["valid"]).to be false
      expect(json["error"]).to include("not found")
    end

    it "returns error for blank table name" do
      post :validate_table, params: { table_name: "" }, format: :json
      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["valid"]).to be false
    end
  end

  describe "GET #tables" do
    it "returns list of tables as JSON" do
      allow(PgTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users", "posts"])

      get :tables, format: :json
      json = JSON.parse(response.body)
      expect(json["tables"]).to include("users", "posts")
    end
  end

  describe "permission checks" do
    it "redirects when permission denied" do
      allow(PgTriggers::Permissions).to receive(:can?).and_return(false)

      get :new
      expect(response).to redirect_to("/")
      expect(flash[:alert]).to include("Insufficient permissions")
    end
  end
end

