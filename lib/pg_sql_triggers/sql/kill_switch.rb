# frozen_string_literal: true

module PgSqlTriggers
  module SQL
    # KillSwitch: three-layer safety gate for dangerous operations.
    #
    # Layer 1 – config:  PgSqlTriggers.kill_switch_enabled / kill_switch_environments
    # Layer 2 – ENV:     KILL_SWITCH_OVERRIDE=true (+ optional confirmation)
    # Layer 3 – explicit: confirmation text passed directly to check!
    #
    # @example
    #   KillSwitch.check!(operation: :migrate_up, environment: Rails.env,
    #                     confirmation: params[:confirmation_text],
    #                     actor: { type: "UI", id: current_user.email })
    module KillSwitch
      OVERRIDE_KEY = :pg_sql_triggers_kill_switch_override

      class << self
        def active?(environment: nil, operation: nil)
          return false unless kill_switch_enabled?

          env    = resolve_environment(environment)
          active = protected_environment?(env)
          logger&.debug "[KILL_SWITCH] Check: operation=#{operation} environment=#{env} active=#{active}" if operation
          active
        end

        def check!(operation:, environment: nil, confirmation: nil, actor: nil)
          env = resolve_environment(environment)

          unless active?(environment: env, operation: operation)
            log(:info, "ALLOWED", operation, env, actor, "reason=not_protected_environment")
            return
          end

          if Thread.current[OVERRIDE_KEY]
            log(:warn, "OVERRIDDEN", operation, env, actor, "source=thread_local")
            return
          end

          if ENV["KILL_SWITCH_OVERRIDE"]&.downcase == "true"
            if confirmation_required?
              validate_confirmation!(confirmation, operation)
              log(:warn, "OVERRIDDEN", operation, env, actor, "source=env_with_confirmation confirmation=#{confirmation}")
            else
              log(:warn, "OVERRIDDEN", operation, env, actor, "source=env_without_confirmation")
            end
            return
          end

          unless confirmation.nil?
            validate_confirmation!(confirmation, operation)
            log(:warn, "OVERRIDDEN", operation, env, actor, "source=explicit_confirmation confirmation=#{confirmation}")
            return
          end

          log(:error, "BLOCKED", operation, env, actor)
          expected = expected_confirmation(operation)
          raise PgSqlTriggers::KillSwitchError.new(
            "Kill switch is active for #{env} environment. Operation '#{operation}' has been blocked.\n\n" \
            "To override: KILL_SWITCH_OVERRIDE=true or provide confirmation text: #{expected}",
            error_code: "KILL_SWITCH_ACTIVE",
            recovery_suggestion: "Provide the confirmation text: #{expected}",
            context: { operation: operation, environment: env, expected_confirmation: expected }
          )
        end

        def override(confirmation: nil)
          raise ArgumentError, "Block required for kill switch override" unless block_given?

          logger&.info "[KILL_SWITCH] Override block initiated with confirmation: #{confirmation}" if confirmation.present?
          previous = Thread.current[OVERRIDE_KEY]
          Thread.current[OVERRIDE_KEY] = true
          begin
            yield
          ensure
            Thread.current[OVERRIDE_KEY] = previous
          end
        end

        def validate_confirmation!(confirmation, operation)
          expected = expected_confirmation(operation)

          if confirmation.nil? || confirmation.strip.empty?
            raise PgSqlTriggers::KillSwitchError.new(
              "Confirmation text required. Expected: '#{expected}'",
              error_code: "KILL_SWITCH_CONFIRMATION_REQUIRED",
              recovery_suggestion: "Provide the confirmation text: #{expected}",
              context: { operation: operation, expected_confirmation: expected }
            )
          end

          return if confirmation.strip == expected

          raise PgSqlTriggers::KillSwitchError.new(
            "Invalid confirmation text. Expected: '#{expected}', got: '#{confirmation.strip}'",
            error_code: "KILL_SWITCH_CONFIRMATION_INVALID",
            recovery_suggestion: "Use the exact confirmation text: #{expected}",
            context: { operation: operation, expected_confirmation: expected, provided_confirmation: confirmation.strip }
          )
        end

        private

        def kill_switch_enabled?
          return true unless PgSqlTriggers.respond_to?(:kill_switch_enabled)

          value = PgSqlTriggers.kill_switch_enabled
          value.nil? || value
        end

        def protected_environment?(env)
          return false if env.nil?

          configured = PgSqlTriggers.respond_to?(:kill_switch_environments) ? PgSqlTriggers.kill_switch_environments : nil
          Array(configured || %i[production staging]).map(&:to_s).include?(env.to_s)
        end

        def resolve_environment(environment)
          return environment.to_s if environment.present?
          return Rails.env.to_s if defined?(Rails) && Rails.respond_to?(:env)

          if PgSqlTriggers.respond_to?(:default_environment) && PgSqlTriggers.default_environment.respond_to?(:call)
            begin
              return PgSqlTriggers.default_environment.call.to_s
            rescue NameError, NoMethodError # rubocop:disable Lint/ShadowedException
            end
          end

          ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
        end

        def confirmation_required?
          return true unless PgSqlTriggers.respond_to?(:kill_switch_confirmation_required)

          value = PgSqlTriggers.kill_switch_confirmation_required
          value.nil? || value
        end

        def expected_confirmation(operation)
          if PgSqlTriggers.respond_to?(:kill_switch_confirmation_pattern) &&
             PgSqlTriggers.kill_switch_confirmation_pattern.respond_to?(:call)
            PgSqlTriggers.kill_switch_confirmation_pattern.call(operation)
          else
            "EXECUTE #{operation.to_s.upcase}"
          end
        end

        def logger
          if PgSqlTriggers.respond_to?(:kill_switch_logger)
            PgSqlTriggers.kill_switch_logger
          elsif defined?(Rails) && Rails.respond_to?(:logger)
            Rails.logger
          end
        end

        def log(level, status, operation, environment, actor, extra = nil)
          actor_str = actor.is_a?(Hash) ? "#{actor[:type] || 'unknown'}:#{actor[:id] || 'unknown'}" : (actor&.to_s || "unknown")
          msg = "[KILL_SWITCH] #{status}: operation=#{operation} environment=#{environment} actor=#{actor_str}"
          msg = "#{msg} #{extra}" if extra
          logger&.public_send(level, msg)
        end
      end
    end
  end
end
