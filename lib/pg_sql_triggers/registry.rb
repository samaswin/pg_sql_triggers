# frozen_string_literal: true

module PgSqlTriggers
  # Registry module provides a unified API for querying and managing triggers.
  #
  # @example Query triggers
  #   # List all triggers
  #   triggers = PgSqlTriggers::Registry.list
  #
  #   # Get enabled/disabled triggers
  #   enabled = PgSqlTriggers::Registry.enabled
  #   disabled = PgSqlTriggers::Registry.disabled
  #
  #   # Get triggers for a specific table
  #   user_triggers = PgSqlTriggers::Registry.for_table(:users)
  #
  #   # Check for drift
  #   drift_info = PgSqlTriggers::Registry.diff
  #
  # @example Manage triggers
  #   # Enable a trigger
  #   PgSqlTriggers::Registry.enable("users_email_validation",
  #                                   actor: current_user,
  #                                   confirmation: "EXECUTE TRIGGER_ENABLE")
  #
  #   # Disable a trigger
  #   PgSqlTriggers::Registry.disable("users_email_validation",
  #                                    actor: current_user,
  #                                    confirmation: "EXECUTE TRIGGER_DISABLE")
  #
  #   # Drop a trigger
  #   PgSqlTriggers::Registry.drop("old_trigger",
  #                                 actor: current_user,
  #                                 reason: "No longer needed",
  #                                 confirmation: "EXECUTE TRIGGER_DROP")
  #
  #   # Re-execute a trigger
  #   PgSqlTriggers::Registry.re_execute("drifted_trigger",
  #                                       actor: current_user,
  #                                       reason: "Fix drift",
  #                                       confirmation: "EXECUTE TRIGGER_RE_EXECUTE")
  module Registry
    autoload :Manager, "pg_sql_triggers/registry/manager"
    autoload :Validator, "pg_sql_triggers/registry/validator"

    # Registers a trigger definition in the registry.
    #
    # @param definition [PgSqlTriggers::DSL::TriggerDefinition] The trigger definition to register
    # @return [PgSqlTriggers::TriggerRegistry] The registered trigger record
    def self.register(definition)
      Manager.register(definition)
    end

    # Returns all registered triggers.
    #
    # @return [ActiveRecord::Relation<PgSqlTriggers::TriggerRegistry>] All trigger records
    def self.list
      Manager.list
    end

    # Returns only enabled triggers.
    #
    # @return [ActiveRecord::Relation<PgSqlTriggers::TriggerRegistry>] Enabled trigger records
    def self.enabled
      Manager.enabled
    end

    # Returns only disabled triggers.
    #
    # @return [ActiveRecord::Relation<PgSqlTriggers::TriggerRegistry>] Disabled trigger records
    def self.disabled
      Manager.disabled
    end

    # Returns triggers for a specific table.
    #
    # @param table_name [String, Symbol] The table name to filter by
    # @return [ActiveRecord::Relation<PgSqlTriggers::TriggerRegistry>] Triggers for the specified table
    def self.for_table(table_name)
      Manager.for_table(table_name)
    end

    # Checks for drift between DSL definitions and database state.
    #
    # @param trigger_name [String, nil] Optional trigger name to check specific trigger, or nil for all triggers
    # @return [Hash] Drift information with keys: :in_sync, :drifted, :manual_override, :disabled, :dropped, :unknown
    def self.diff(trigger_name = nil)
      Manager.diff(trigger_name)
    end

    # Returns all triggers that have drifted from their expected state.
    #
    # @return [Array<Hash>] Array of drift result hashes for drifted triggers
    def self.drifted
      Manager.drifted
    end

    # Returns all triggers that are in sync with their expected state.
    #
    # @return [Array<Hash>] Array of drift result hashes for in-sync triggers
    def self.in_sync
      Manager.in_sync
    end

    # Returns all unknown (external) triggers not managed by this gem.
    #
    # @return [Array<Hash>] Array of drift result hashes for unknown triggers
    def self.unknown_triggers
      Manager.unknown_triggers
    end

    # Returns all triggers that have been dropped from the database.
    #
    # @return [Array<Hash>] Array of drift result hashes for dropped triggers
    def self.dropped
      Manager.dropped
    end

    # Validates all triggers in the registry.
    #
    # @raise [PgSqlTriggers::ValidationError] If validation fails
    # @return [true] If validation passes
    def self.validate!
      Validator.validate!
    end

    # Enables a trigger by name.
    #
    # @param trigger_name [String] The name of the trigger to enable
    # @param actor [Hash] Information about who is performing the action (must have :type and :id keys)
    # @param confirmation [String, nil] Optional confirmation text for kill switch protection
    # @raise [PgSqlTriggers::PermissionError] If actor lacks permission
    # @raise [PgSqlTriggers::KillSwitchError] If kill switch blocks the operation
    # @raise [PgSqlTriggers::NotFoundError] If trigger not found
    # @return [PgSqlTriggers::TriggerRegistry] The updated trigger record
    def self.enable(trigger_name, actor:, confirmation: nil)
      check_permission!(actor, :enable_trigger)
      trigger = find_trigger!(trigger_name)
      trigger.enable!(confirmation: confirmation, actor: actor)
    end

    # Disables a trigger by name.
    #
    # @param trigger_name [String] The name of the trigger to disable
    # @param actor [Hash] Information about who is performing the action (must have :type and :id keys)
    # @param confirmation [String, nil] Optional confirmation text for kill switch protection
    # @raise [PgSqlTriggers::PermissionError] If actor lacks permission
    # @raise [PgSqlTriggers::KillSwitchError] If kill switch blocks the operation
    # @raise [PgSqlTriggers::NotFoundError] If trigger not found
    # @return [PgSqlTriggers::TriggerRegistry] The updated trigger record
    def self.disable(trigger_name, actor:, confirmation: nil)
      check_permission!(actor, :disable_trigger)
      trigger = find_trigger!(trigger_name)
      trigger.disable!(confirmation: confirmation, actor: actor)
    end

    # Drops a trigger by name.
    #
    # @param trigger_name [String] The name of the trigger to drop
    # @param actor [Hash] Information about who is performing the action (must have :type and :id keys)
    # @param reason [String] Required reason for dropping the trigger
    # @param confirmation [String, nil] Optional confirmation text for kill switch protection
    # @raise [PgSqlTriggers::PermissionError] If actor lacks permission
    # @raise [PgSqlTriggers::KillSwitchError] If kill switch blocks the operation
    # @raise [PgSqlTriggers::NotFoundError] If trigger not found
    # @raise [ArgumentError] If reason is missing or empty
    # @return [true] If drop succeeds
    def self.drop(trigger_name, actor:, reason:, confirmation: nil)
      check_permission!(actor, :drop_trigger)
      trigger = find_trigger!(trigger_name)
      trigger.drop!(reason: reason, confirmation: confirmation, actor: actor)
    end

    # Re-executes a trigger by name (drops and recreates it).
    #
    # @param trigger_name [String] The name of the trigger to re-execute
    # @param actor [Hash] Information about who is performing the action (must have :type and :id keys)
    # @param reason [String] Required reason for re-executing the trigger
    # @param confirmation [String, nil] Optional confirmation text for kill switch protection
    # @raise [PgSqlTriggers::PermissionError] If actor lacks permission
    # @raise [PgSqlTriggers::KillSwitchError] If kill switch blocks the operation
    # @raise [PgSqlTriggers::NotFoundError] If trigger not found
    # @raise [ArgumentError] If reason is missing or empty
    # @return [PgSqlTriggers::TriggerRegistry] The updated trigger record
    def self.re_execute(trigger_name, actor:, reason:, confirmation: nil)
      check_permission!(actor, :drop_trigger) # Re-execute requires same permission as drop
      trigger = find_trigger!(trigger_name)
      trigger.re_execute!(reason: reason, confirmation: confirmation, actor: actor)
    end

    # Private helper methods

    def self.find_trigger!(trigger_name)
      PgSqlTriggers::TriggerRegistry.find_by!(trigger_name: trigger_name)
    rescue ActiveRecord::RecordNotFound
      raise PgSqlTriggers::NotFoundError.new(
        "Trigger '#{trigger_name}' not found in registry",
        error_code: "TRIGGER_NOT_FOUND",
        recovery_suggestion: "Verify the trigger name or create the trigger first using the generator or DSL.",
        context: { trigger_name: trigger_name }
      )
    end
    private_class_method :find_trigger!

    def self.check_permission!(actor, action)
      PgSqlTriggers::Permissions.check!(actor, action)
    end
    private_class_method :check_permission!
  end
end
