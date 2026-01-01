# frozen_string_literal: true

module PgSqlTriggers
  module SQL
    # Executor handles the execution of SQL capsules with safety checks and logging
    #
    # @example Execute a SQL capsule
    #   capsule = PgSqlTriggers::SQL::Capsule.new(name: "fix", ...)
    #   result = PgSqlTriggers::SQL::Executor.execute(capsule, actor: current_actor, confirmation: "EXECUTE FIX")
    #
    class Executor
      class << self
        # Executes a SQL capsule with safety checks
        #
        # @param capsule [Capsule] The SQL capsule to execute
        # @param actor [Hash] Information about who is executing the capsule
        # @param confirmation [String, nil] The confirmation text for kill switch
        # @param dry_run [Boolean] If true, only validate without executing
        # @return [Hash] Result of the execution with :success, :message, and :data keys
        def execute(capsule, actor:, confirmation: nil, dry_run: false)
          validate_capsule!(capsule)

          # Check permissions
          check_permissions!(actor)

          # Check kill switch
          check_kill_switch!(capsule, actor, confirmation)

          # Log the execution attempt
          log_execution_attempt(capsule, actor, dry_run)

          if dry_run
            return {
              success: true,
              message: "Dry run successful. SQL would be executed.",
              data: { checksum: capsule.checksum }
            }
          end

          # Execute in transaction
          result = execute_in_transaction(capsule, actor)

          # Update registry after successful execution
          update_registry(capsule) if result[:success]

          # Log the result
          log_execution_result(capsule, actor, result)

          result
        rescue StandardError => e
          log_execution_error(capsule, actor, e)
          {
            success: false,
            message: "Execution failed: #{e.message}",
            error: e
          }
        end

        # Executes a SQL capsule by name from the registry
        #
        # @param capsule_name [String] The name of the capsule to execute
        # @param actor [Hash] Information about who is executing the capsule
        # @param confirmation [String, nil] The confirmation text for kill switch
        # @param dry_run [Boolean] If true, only validate without executing
        # @return [Hash] Result of the execution
        def execute_capsule(capsule_name, actor:, confirmation: nil, dry_run: false)
          capsule = load_capsule_from_registry(capsule_name)

          unless capsule
            return {
              success: false,
              message: "Capsule '#{capsule_name}' not found in registry"
            }
          end

          execute(capsule, actor: actor, confirmation: confirmation, dry_run: dry_run)
        end

        private

        def validate_capsule!(capsule)
          raise ArgumentError, "Capsule must be a PgSqlTriggers::SQL::Capsule" unless capsule.is_a?(Capsule)
        end

        def check_permissions!(actor)
          PgSqlTriggers::Permissions.check!(actor, :execute_sql)
        rescue PgSqlTriggers::PermissionError => e
          raise PgSqlTriggers::PermissionError,
                "SQL capsule execution requires Admin role: #{e.message}"
        end

        def check_kill_switch!(_capsule, actor, confirmation)
          PgSqlTriggers::SQL::KillSwitch.check!(
            operation: :execute_sql_capsule,
            environment: Rails.env,
            confirmation: confirmation,
            actor: actor
          )
        end

        def execute_in_transaction(capsule, _actor)
          ActiveRecord::Base.transaction do
            result = ActiveRecord::Base.connection.execute(capsule.sql)

            {
              success: true,
              message: "SQL capsule '#{capsule.name}' executed successfully",
              data: {
                checksum: capsule.checksum,
                rows_affected: result.cmd_tuples || 0
              }
            }
          end
        end

        def update_registry(capsule)
          # Check if capsule already exists in registry
          registry_entry = PgSqlTriggers::TriggerRegistry.find_or_initialize_by(
            trigger_name: capsule.registry_trigger_name
          )

          registry_entry.assign_attributes(
            table_name: "manual_sql_execution",
            version: Time.current.to_i,
            checksum: capsule.checksum,
            source: "manual_sql",
            function_body: capsule.sql,
            condition: capsule.purpose,
            environment: capsule.environment,
            enabled: true,
            last_executed_at: Time.current
          )

          registry_entry.save!
        rescue StandardError => e
          logger&.error "[SQL_CAPSULE] Failed to update registry: #{e.message}"
          # Don't fail the execution if registry update fails
        end

        def load_capsule_from_registry(capsule_name)
          trigger_name = "sql_capsule_#{capsule_name}"
          registry_entry = PgSqlTriggers::TriggerRegistry.find_by(
            trigger_name: trigger_name,
            source: "manual_sql"
          )

          return nil unless registry_entry

          Capsule.new(
            name: capsule_name,
            environment: registry_entry.environment || Rails.env.to_s,
            purpose: registry_entry.condition || "No purpose specified",
            sql: registry_entry.function_body,
            created_at: registry_entry.created_at
          )
        end

        # Logging methods

        def log_execution_attempt(capsule, actor, dry_run)
          mode = dry_run ? "DRY_RUN" : "EXECUTE"
          logger&.info "[SQL_CAPSULE] #{mode} ATTEMPT: name=#{capsule.name} " \
                       "environment=#{capsule.environment} actor=#{format_actor(actor)}"
        end

        def log_execution_result(capsule, actor, result)
          status = result[:success] ? "SUCCESS" : "FAILED"
          logger&.info "[SQL_CAPSULE] #{status}: name=#{capsule.name} " \
                       "environment=#{capsule.environment} actor=#{format_actor(actor)} " \
                       "checksum=#{capsule.checksum}"
        end

        def log_execution_error(capsule, actor, error)
          # Handle case where capsule might not be valid
          capsule_name = capsule.respond_to?(:name) ? capsule.name : "invalid_capsule"
          environment = capsule.respond_to?(:environment) ? capsule.environment : "unknown"

          logger&.error "[SQL_CAPSULE] ERROR: name=#{capsule_name} " \
                        "environment=#{environment} actor=#{format_actor(actor)} " \
                        "error=#{error.class.name} message=#{error.message}"
        end

        def format_actor(actor)
          return "unknown" if actor.nil?
          return actor.to_s unless actor.is_a?(Hash)

          "#{actor[:type] || 'unknown'}:#{actor[:id] || 'unknown'}"
        end

        def logger
          if PgSqlTriggers.respond_to?(:logger) && PgSqlTriggers.logger
            PgSqlTriggers.logger
          elsif defined?(Rails) && Rails.respond_to?(:logger)
            Rails.logger
          end
        end
      end
    end
  end
end
