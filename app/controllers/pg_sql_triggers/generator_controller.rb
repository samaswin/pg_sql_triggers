# frozen_string_literal: true

module PgTriggers
  class GeneratorController < ApplicationController
    # Permissions: Require OPERATOR level for generation
    before_action :check_operator_permission

    # GET /generator/new
    # Display the multi-step form wizard
    def new
      @form = PgTriggers::Generator::Form.new
      @available_tables = fetch_available_tables
    end

    # POST /generator/preview
    # Preview generated DSL and function stub (AJAX or regular POST)
    def preview
      @form = PgTriggers::Generator::Form.new(generator_params)

      if @form.valid?
        # Validate SQL function body (required field)
        @sql_validation = validate_function_sql(@form)

        @dsl_content = PgTriggers::Generator::Service.generate_dsl(@form)
        # Use function_body (required)
        @function_content = @form.function_body
        @file_paths = PgTriggers::Generator::Service.file_paths(@form)

        render :preview
      else
        @available_tables = fetch_available_tables
        render :new
      end
    end

    # POST /generator/create
    # Actually create the files and register in TriggerRegistry
    def create
      @form = PgTriggers::Generator::Form.new(generator_params)

      if @form.valid?
        # Validate SQL function body (required field)
        sql_validation = validate_function_sql(@form)
        unless sql_validation[:valid]
          flash[:alert] = "Cannot create trigger: SQL validation failed - #{sql_validation[:error]}"
          @available_tables = fetch_available_tables
          @dsl_content = PgTriggers::Generator::Service.generate_dsl(@form)
          @function_content = @form.function_body
          @file_paths = PgTriggers::Generator::Service.file_paths(@form)
          @sql_validation = sql_validation
          render :preview
          return
        end

        result = PgTriggers::Generator::Service.create_trigger(@form, actor: current_actor)

        if result[:success]
          files_msg = "Migration: #{result[:migration_path]}, DSL: #{result[:dsl_path]}"
          redirect_to root_path,
                      notice: "Trigger generated successfully. Files created: #{files_msg}"
        else
          flash[:alert] = "Generation failed: #{result[:error]}"
          @available_tables = fetch_available_tables
          render :new
        end
      else
        @available_tables = fetch_available_tables
        render :new
      end
    end

    # POST /generator/validate_table (AJAX)
    # Validate that table exists in database
    def validate_table
      # Extract table_name from JSON request body
      # Rails should parse JSON automatically, but handle both cases
      table_name = extract_table_name_from_request
      
      if table_name.blank?
        render json: { valid: false, error: "Table name is required" }, status: :bad_request
        return
      end

      validator = PgTriggers::DatabaseIntrospection.new
      result = validator.validate_table(table_name)
      render json: result
    end

    # GET /generator/tables (AJAX)
    # Fetch list of tables for dropdown
    def tables
      tables = fetch_available_tables
      render json: { tables: tables }
    end

    private

    def generator_params
      params.require(:pg_sql_triggers_generator_form).permit(
        :trigger_name, :table_name, :function_name, :version,
        :enabled, :condition, :generate_function_stub, :function_body,
        events: [], environments: []
      )
    end

    def check_operator_permission
      unless PgTriggers::Permissions.can?(current_actor, :apply_trigger)
        redirect_to root_path, alert: "Insufficient permissions. Operator role required."
      end
    end

    def fetch_available_tables
      PgTriggers::DatabaseIntrospection.new.list_tables
    rescue => e
      Rails.logger.error("Failed to fetch tables: #{e.message}")
      []
    end

    def extract_table_name_from_request
      # Rails automatically parses JSON request bodies when Content-Type is application/json
      # The parameters are available directly in params
      table_name = params[:table_name]
      
      # If not found, try accessing as string key (some Rails versions use string keys for JSON)
      table_name ||= params['table_name'] if params.key?('table_name')
      
      table_name
    end

    def validate_function_sql(form)
      return nil if form.function_body.blank?

      # Create a temporary trigger registry object for validation
      temp_registry = PgTriggers::TriggerRegistry.new(
        trigger_name: form.trigger_name,
        function_body: form.function_body
      )

      validator = PgTriggers::Testing::SyntaxValidator.new(temp_registry)
      validator.validate_function_syntax
    rescue => e
      { valid: false, error: "Validation error: #{e.message}" }
    end
  end
end
