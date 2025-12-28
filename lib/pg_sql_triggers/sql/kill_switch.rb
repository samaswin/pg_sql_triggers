# frozen_string_literal: true

module PgSqlTriggers
  module SQL
    # KillSwitch is a centralized safety gate that prevents dangerous operations
    # from being executed in protected environments (typically production).
    #
    # It operates on three levels:
    # 1. Configuration Level: Environment-based activation via PgSqlTriggers.kill_switch_enabled
    # 2. Runtime Level: ENV variable override support (KILL_SWITCH_OVERRIDE)
    # 3. Explicit Confirmation Level: Typed confirmation text for critical operations
    #
    # @example Basic usage in a dangerous operation
    #   KillSwitch.check!(
    #     operation: :migrate_up,
    #     environment: Rails.env,
    #     confirmation: params[:confirmation_text],
    #     actor: { type: 'UI', id: current_user.email }
    #   )
    #
    # @example Using override block
    #   KillSwitch.override(confirmation: "EXECUTE MIGRATE_UP") do
    #     # dangerous operation here
    #   end
    #
    # @example CLI usage with ENV override
    #   KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE MIGRATE_UP" rake pg_sql_triggers:migrate
    #
    # rubocop:disable Metrics/ModuleLength
    module KillSwitch
      # Thread-local storage key for override state
      OVERRIDE_KEY = :pg_sql_triggers_kill_switch_override

      class << self
        # Checks if the kill switch is active for the given environment and operation.
        #
        # @param environment [String, Symbol, nil] The environment to check (defaults to current environment)
        # @param operation [String, Symbol, nil] The operation being performed (for logging)
        # @return [Boolean] true if kill switch is active, false otherwise
        def active?(environment: nil, operation: nil)
          # Check if kill switch is globally disabled
          return false unless kill_switch_enabled?

          # Detect environment
          env = detect_environment(environment)

          # Check if this environment is protected
          is_active = protected_environment?(env)

          # Log the check if logger is available and operation is provided
          if logger && operation
            logger.debug "[KILL_SWITCH] Check: operation=#{operation} environment=#{env} active=#{is_active}"
          end

          is_active
        end

        # Checks if an operation should be blocked by the kill switch.
        # Raises KillSwitchError if the operation is blocked.
        #
        # @param operation [String, Symbol] The operation being performed
        # @param environment [String, Symbol, nil] The environment (defaults to current)
        # @param confirmation [String, nil] The confirmation text provided by the user
        # @param actor [Hash, nil] Information about who is performing the operation
        # @raise [PgSqlTriggers::KillSwitchError] if the operation is blocked
        # @return [void]
        def check!(operation:, environment: nil, confirmation: nil, actor: nil)
          env = detect_environment(environment)

          # Check if kill switch is active for this environment
          unless active?(environment: env, operation: operation)
            log_allowed(operation: operation, environment: env, actor: actor, reason: "not_protected_environment")
            return
          end

          # Check for thread-local override
          if thread_override_active?
            log_override(operation: operation, environment: env, actor: actor, source: "thread_local")
            return
          end

          # Check for ENV override
          if env_override_active?
            # If ENV override is present, check confirmation if required
            if confirmation_required?
              validate_confirmation!(confirmation, operation)
              log_override(operation: operation, environment: env, actor: actor, source: "env_with_confirmation",
                           confirmation: confirmation)
            else
              log_override(operation: operation, environment: env, actor: actor, source: "env_without_confirmation")
            end
            return
          end

          # If confirmation is provided, validate it
          unless confirmation.nil?
            validate_confirmation!(confirmation, operation)
            log_override(operation: operation, environment: env, actor: actor, source: "explicit_confirmation",
                         confirmation: confirmation)
            return
          end

          # No override mechanism satisfied - block the operation
          log_blocked(operation: operation, environment: env, actor: actor)
          raise_blocked_error(operation: operation, environment: env)
        end

        # Temporarily overrides the kill switch for the duration of the block.
        # Uses thread-local storage to ensure thread safety.
        #
        # @param confirmation [String, nil] Optional confirmation text
        # @yield The block to execute with kill switch overridden
        # @return The return value of the block
        def override(confirmation: nil)
          raise ArgumentError, "Block required for kill switch override" unless block_given?

          # Validate confirmation if provided and required
          if confirmation.present? && confirmation_required?
            # NOTE: We can't validate against a specific operation here since we don't know it
            # The block itself will call check! with the operation, which will see the override
            logger&.info "[KILL_SWITCH] Override block initiated with confirmation: #{confirmation}"
          end

          # Set thread-local override
          previous_value = Thread.current[OVERRIDE_KEY]
          Thread.current[OVERRIDE_KEY] = true

          begin
            yield
          ensure
            # Restore previous value
            Thread.current[OVERRIDE_KEY] = previous_value
          end
        end

        # Validates the confirmation text against the expected pattern for the operation.
        #
        # @param confirmation [String, nil] The confirmation text to validate
        # @param operation [String, Symbol] The operation being confirmed
        # @raise [PgSqlTriggers::KillSwitchError] if confirmation is invalid
        # @return [void]
        def validate_confirmation!(confirmation, operation)
          expected = expected_confirmation(operation)

          if confirmation.nil? || confirmation.strip.empty?
            raise PgSqlTriggers::KillSwitchError,
                  "Confirmation text required. Expected: '#{expected}'"
          end

          return if confirmation.strip == expected

          raise PgSqlTriggers::KillSwitchError,
                "Invalid confirmation text. Expected: '#{expected}', got: '#{confirmation.strip}'"
        end

        private

        # Checks if kill switch is globally enabled in configuration
        def kill_switch_enabled?
          return true unless PgSqlTriggers.respond_to?(:kill_switch_enabled)

          # Default to true (fail-safe) if not configured
          value = PgSqlTriggers.kill_switch_enabled
          value.nil? || value
        end

        # Checks if the given environment is protected by the kill switch
        def protected_environment?(environment)
          return false if environment.nil?

          protected_envs = if PgSqlTriggers.respond_to?(:kill_switch_environments)
                             value = PgSqlTriggers.kill_switch_environments
                             value.nil? ? %i[production staging] : value
                           else
                             %i[production staging]
                           end

          protected_envs = Array(protected_envs).map(&:to_s)
          protected_envs.include?(environment.to_s)
        end

        # Detects the current environment
        def detect_environment(environment)
          return environment.to_s if environment.present?

          # Try Rails environment
          return Rails.env.to_s if defined?(Rails) && Rails.respond_to?(:env)

          # Try PgSqlTriggers default_environment
          if PgSqlTriggers.respond_to?(:default_environment) && PgSqlTriggers.default_environment.respond_to?(:call)
            begin
              return PgSqlTriggers.default_environment.call.to_s
            rescue NameError, NoMethodError # rubocop:disable Lint/ShadowedException
              # Fall through to next option if default_environment proc references undefined constants
            end
          end

          # Fall back to RAILS_ENV or RACK_ENV
          ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
        end

        # Checks if thread-local override is active
        def thread_override_active?
          Thread.current[OVERRIDE_KEY] == true
        end

        # Checks if ENV override is active
        def env_override_active?
          ENV["KILL_SWITCH_OVERRIDE"]&.downcase == "true"
        end

        # Checks if confirmation is required for overrides
        def confirmation_required?
          return true unless PgSqlTriggers.respond_to?(:kill_switch_confirmation_required)

          # Default to true (safer) if not configured
          value = PgSqlTriggers.kill_switch_confirmation_required
          value.nil? || value
        end

        # Generates the expected confirmation text for an operation
        def expected_confirmation(operation)
          if PgSqlTriggers.respond_to?(:kill_switch_confirmation_pattern) &&
             PgSqlTriggers.kill_switch_confirmation_pattern.respond_to?(:call)
            PgSqlTriggers.kill_switch_confirmation_pattern.call(operation)
          else
            # Default pattern
            "EXECUTE #{operation.to_s.upcase}"
          end
        end

        # Returns the configured logger
        def logger
          if PgSqlTriggers.respond_to?(:kill_switch_logger)
            PgSqlTriggers.kill_switch_logger
          elsif defined?(Rails) && Rails.respond_to?(:logger)
            Rails.logger
          end
        end

        # Logs an allowed operation
        def log_allowed(operation:, environment:, actor:, reason:)
          actor_info = format_actor(actor)
          logger&.info "[KILL_SWITCH] ALLOWED: operation=#{operation} environment=#{environment} " \
                       "actor=#{actor_info} reason=#{reason}"
        end

        # Logs an overridden operation
        def log_override(operation:, environment:, actor:, source:, confirmation: nil)
          actor_info = format_actor(actor)
          conf_info = confirmation ? " confirmation=#{confirmation}" : ""
          logger&.warn "[KILL_SWITCH] OVERRIDDEN: operation=#{operation} environment=#{environment} " \
                       "actor=#{actor_info} source=#{source}#{conf_info}"
        end

        # Logs a blocked operation
        def log_blocked(operation:, environment:, actor:)
          actor_info = format_actor(actor)
          logger&.error "[KILL_SWITCH] BLOCKED: operation=#{operation} environment=#{environment} actor=#{actor_info}"
        end

        # Formats actor information for logging
        def format_actor(actor)
          return "unknown" if actor.nil?
          return actor.to_s unless actor.is_a?(Hash)

          "#{actor[:type] || 'unknown'}:#{actor[:id] || 'unknown'}"
        end

        # Raises a kill switch error with helpful message
        def raise_blocked_error(operation:, environment:)
          expected = expected_confirmation(operation)

          message = <<~ERROR
            Kill switch is active for #{environment} environment.
            Operation '#{operation}' has been blocked for safety.

            To override this protection, you must provide confirmation.

            For CLI/rake tasks, use:
              KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="#{expected}" rake your:task

            For console operations, use:
              PgSqlTriggers::SQL::KillSwitch.override(confirmation: "#{expected}") do
                # your dangerous operation here
              end

            For UI operations, enter the confirmation text: #{expected}

            This protection prevents accidental destructive operations in production.
            Make sure you understand the implications before proceeding.
          ERROR

          raise PgSqlTriggers::KillSwitchError, message
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
