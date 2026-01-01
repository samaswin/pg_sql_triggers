# frozen_string_literal: true

module PermissionHelpers
  # Configures permissions for testing
  # @param permission_map [Hash] Hash mapping actions to allowed status (true/false)
  #   Example: { enable_trigger: true, disable_trigger: true, drop_trigger: false }
  # @yield Block to execute with the permission configuration
  # @return [void]
  def with_permission_checker(permission_map = {})
    original_checker = PgSqlTriggers.permission_checker

    # Create a permission checker that uses the permission_map
    PgSqlTriggers.permission_checker = lambda do |_actor, action, _environment|
      action_sym = action.to_sym
      # Default to true if not specified (allow all by default in tests)
      permission_map.fetch(action_sym, true)
    end

    yield
  ensure
    PgSqlTriggers.permission_checker = original_checker
  end

  # Configures permissions to allow all actions
  # @yield Block to execute with all permissions allowed
  # @return [void]
  def with_all_permissions_allowed(&block)
    with_permission_checker({}, &block)
  end

  # Configures permissions to deny a specific action
  # @param action [Symbol] The action to deny
  # @yield Block to execute with the action denied
  # @return [void]
  def with_permission_denied(action, &block)
    with_permission_checker({ action => false }, &block)
  end

  # Configures kill switch for testing
  # @param enabled [Boolean] Whether kill switch is enabled
  # @param environments [Array<Symbol, String>] Environments to protect
  # @param confirmation_required [Boolean] Whether confirmation is required
  # @param confirmation_pattern [Proc, nil] Custom confirmation pattern
  # @yield Block to execute with the kill switch configuration
  # @return [void]
  def with_kill_switch(enabled: true, environments: [], confirmation_required: false, confirmation_pattern: nil)
    original_enabled = PgSqlTriggers.kill_switch_enabled
    original_environments = PgSqlTriggers.kill_switch_environments
    original_confirmation_required = PgSqlTriggers.kill_switch_confirmation_required
    original_confirmation_pattern = PgSqlTriggers.kill_switch_confirmation_pattern

    PgSqlTriggers.kill_switch_enabled = enabled
    PgSqlTriggers.kill_switch_environments = Array(environments).map(&:to_sym)
    PgSqlTriggers.kill_switch_confirmation_required = confirmation_required
    PgSqlTriggers.kill_switch_confirmation_pattern = confirmation_pattern if confirmation_pattern

    yield
  ensure
    PgSqlTriggers.kill_switch_enabled = original_enabled
    PgSqlTriggers.kill_switch_environments = original_environments
    PgSqlTriggers.kill_switch_confirmation_required = original_confirmation_required
    PgSqlTriggers.kill_switch_confirmation_pattern = original_confirmation_pattern
  end

  # Configures kill switch to be disabled (allows all operations)
  # @yield Block to execute with kill switch disabled
  # @return [void]
  def with_kill_switch_disabled(&block)
    with_kill_switch(enabled: false, &block)
  end

  # Configures kill switch to protect a specific environment
  # @param environment [Symbol, String] The environment to protect
  # @param confirmation_required [Boolean] Whether confirmation is required
  # @yield Block to execute with the kill switch configuration
  # @return [void]
  def with_kill_switch_protecting(environment, confirmation_required: true, &block)
    with_kill_switch(
      enabled: true,
      environments: [environment],
      confirmation_required: confirmation_required, &block
    )
  end
end

RSpec.configure do |config|
  config.include PermissionHelpers
end
