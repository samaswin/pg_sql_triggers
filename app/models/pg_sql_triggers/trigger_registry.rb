# frozen_string_literal: true

module PgSqlTriggers
  # ActiveRecord model representing a trigger in the registry.
  #
  # This model tracks all triggers managed by pg_sql_triggers, including their
  # state, version, checksum, and drift status.
  #
  # @example Query triggers
  #   # Find a trigger
  #   trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
  #
  #   # Check drift status
  #   trigger.drifted?  # => true/false
  #   trigger.in_sync?  # => true/false
  #
  # @example Enable/disable triggers
  #   trigger.enable!(actor: current_user, confirmation: "EXECUTE TRIGGER_ENABLE")
  #   trigger.disable!(actor: current_user, confirmation: "EXECUTE TRIGGER_DISABLE")
  #
  # @example Drop and re-execute triggers
  #   trigger.drop!(reason: "No longer needed", actor: current_user, confirmation: "EXECUTE TRIGGER_DROP")
  #   trigger.re_execute!(reason: "Fix drift", actor: current_user, confirmation: "EXECUTE TRIGGER_RE_EXECUTE")
  # rubocop:disable Metrics/ClassLength -- core AR model: groups lifecycle operations
  # (enable!/disable!/drop!/re_execute!), drift helpers, audit hooks, and SQL builders.
  # Splitting further would fragment tightly-coupled state and audit concerns.
  class TriggerRegistry < PgSqlTriggers::ApplicationRecord
    self.table_name = "pg_sql_triggers_registry"

    # Validations
    validates :trigger_name, presence: true, uniqueness: true
    validates :table_name, presence: true
    validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :checksum, presence: true
    validates :source, presence: true, inclusion: { in: %w[dsl generated manual_sql] }

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :for_table, ->(table_name) { where(table_name: table_name) }
    scope :for_environment, ->(env) { where(environment: [env, nil]) }
    scope :by_source, ->(source) { where(source: source) }

    # Case-insensitive search on trigger name and table name (used by web dashboard).
    scope :matching_search, lambda { |raw|
      query = raw.to_s.strip
      next all if query.blank?

      sanitized = ActiveRecord::Base.sanitize_sql_like(query)
      term = "%#{sanitized}%"
      where("trigger_name ILIKE :term OR table_name ILIKE :term", term: term)
    }

    # Returns the current drift state of this trigger.
    #
    # @return [String] One of: "in_sync", "drifted", "manual_override", "disabled", "dropped", "unknown"
    def drift_state
      result = PgSqlTriggers::Drift.detect(trigger_name)
      result[:state]
    end

    # Returns detailed drift detection result for this trigger.
    #
    # @return [Hash] Drift result with keys: :state, :trigger_name, :expected_sql, :actual_sql, etc.
    def drift_result
      PgSqlTriggers::Drift::Detector.detect(trigger_name)
    end

    # Checks if this trigger has drifted from its expected state.
    #
    # @return [Boolean] true if trigger has drifted, false otherwise
    def drifted?
      drift_state == PgSqlTriggers::DRIFT_STATE_DRIFTED
    end

    # Checks if this trigger is in sync with its expected state.
    #
    # @return [Boolean] true if trigger is in sync, false otherwise
    def in_sync?
      drift_state == PgSqlTriggers::DRIFT_STATE_IN_SYNC
    end

    # Checks if this trigger has been dropped from the database.
    #
    # @return [Boolean] true if trigger has been dropped, false otherwise
    def dropped?
      drift_state == PgSqlTriggers::DRIFT_STATE_DROPPED
    end

    # Enables this trigger in the database and updates the registry.
    #
    # @param confirmation [String, nil] Optional confirmation text for kill switch protection
    # @param actor [Hash, nil] Information about who is performing the action (must have :type and :id keys)
    # @raise [PgSqlTriggers::KillSwitchError] If kill switch blocks the operation
    # @return [PgSqlTriggers::TriggerRegistry] self
    def enable!(confirmation: nil, actor: nil)
      actor ||= { type: "Console", id: "TriggerRegistry#enable!" }
      before_state = capture_state

      # Check kill switch before enabling trigger
      # Use Rails.env for kill switch check, not the trigger's environment field
      PgSqlTriggers::SQL::KillSwitch.check!(
        operation: :trigger_enable,
        environment: Rails.env,
        confirmation: confirmation,
        actor: actor
      )

      # Check if trigger exists in database before trying to enable it
      trigger_exists = false
      begin
        introspection = PgSqlTriggers::DatabaseIntrospection.new
        trigger_exists = introspection.trigger_exists?(trigger_name)
      rescue StandardError => e
        # If checking fails, assume trigger doesn't exist and continue
        Rails.logger.warn("Could not check if trigger exists: #{e.message}") if defined?(Rails.logger)
      end

      if trigger_exists
        begin
          # Enable the trigger in PostgreSQL
          quoted_table = quote_identifier(table_name)
          quoted_trigger = quote_identifier(trigger_name)
          sql = "ALTER TABLE #{quoted_table} ENABLE TRIGGER #{quoted_trigger};"
          ActiveRecord::Base.connection.execute(sql)
        rescue ActiveRecord::StatementInvalid, StandardError => e
          # If trigger doesn't exist or can't be enabled, continue to update registry
          Rails.logger.warn("Could not enable trigger: #{e.message}") if defined?(Rails.logger)
          log_audit_failure(:trigger_enable, actor, e.message, before_state: before_state)
          raise
        end
      end

      # Update the registry record (always update, even if trigger doesn't exist).
      # If persistence fails for any reason, fall back to the in-memory attribute so
      # callers/observers still see a consistent state for this request.
      persist_enabled_state(true)
      after_state = capture_state
      log_audit_success(:trigger_enable, actor, before_state: before_state, after_state: after_state)
    end

    # Disables this trigger in the database and updates the registry.
    #
    # @param confirmation [String, nil] Optional confirmation text for kill switch protection
    # @param actor [Hash, nil] Information about who is performing the action (must have :type and :id keys)
    # @raise [PgSqlTriggers::KillSwitchError] If kill switch blocks the operation
    # @return [PgSqlTriggers::TriggerRegistry] self
    def disable!(confirmation: nil, actor: nil)
      actor ||= { type: "Console", id: "TriggerRegistry#disable!" }
      before_state = capture_state

      # Check kill switch before disabling trigger
      # Use Rails.env for kill switch check, not the trigger's environment field
      PgSqlTriggers::SQL::KillSwitch.check!(
        operation: :trigger_disable,
        environment: Rails.env,
        confirmation: confirmation,
        actor: actor
      )

      # Check if trigger exists in database before trying to disable it
      trigger_exists = false
      begin
        introspection = PgSqlTriggers::DatabaseIntrospection.new
        trigger_exists = introspection.trigger_exists?(trigger_name)
      rescue StandardError => e
        # If checking fails, assume trigger doesn't exist and continue
        Rails.logger.warn("Could not check if trigger exists: #{e.message}") if defined?(Rails.logger)
      end

      if trigger_exists
        begin
          # Disable the trigger in PostgreSQL
          quoted_table = quote_identifier(table_name)
          quoted_trigger = quote_identifier(trigger_name)
          sql = "ALTER TABLE #{quoted_table} DISABLE TRIGGER #{quoted_trigger};"
          ActiveRecord::Base.connection.execute(sql)
        rescue ActiveRecord::StatementInvalid, StandardError => e
          # If trigger doesn't exist or can't be disabled, continue to update registry
          Rails.logger.warn("Could not disable trigger: #{e.message}") if defined?(Rails.logger)
          log_audit_failure(:trigger_disable, actor, e.message, before_state: before_state)
          raise
        end
      end

      # Update the registry record (always update, even if trigger doesn't exist).
      # If persistence fails for any reason, fall back to the in-memory attribute so
      # callers/observers still see a consistent state for this request.
      persist_enabled_state(false)
      after_state = capture_state
      log_audit_success(:trigger_disable, actor, before_state: before_state, after_state: after_state)
    end

    # Drops this trigger from the database and removes it from the registry.
    #
    # @param reason [String] Required reason for dropping the trigger
    # @param confirmation [String, nil] Optional confirmation text for kill switch protection
    # @param actor [Hash, nil] Information about who is performing the action (must have :type and :id keys)
    # @raise [ArgumentError] If reason is missing or empty
    # @raise [PgSqlTriggers::KillSwitchError] If kill switch blocks the operation
    # @return [true] If drop succeeds
    def drop!(reason:, confirmation: nil, actor: nil)
      actor ||= { type: "Console", id: "TriggerRegistry#drop!" }
      before_state = capture_state

      # Check kill switch before dropping trigger
      PgSqlTriggers::SQL::KillSwitch.check!(
        operation: :trigger_drop,
        environment: Rails.env,
        confirmation: confirmation,
        actor: actor
      )

      # Validate reason is provided
      raise ArgumentError, "Reason is required" if reason.nil? || reason.to_s.strip.empty?

      log_drop_attempt(reason)

      # Execute DROP TRIGGER in transaction
      ActiveRecord::Base.transaction do
        drop_trigger_from_database
        destroy!
        log_drop_success
        log_audit_success(:trigger_drop, actor, reason: reason, confirmation_text: confirmation,
                                                before_state: before_state, after_state: { status: "dropped" })
      end
    rescue StandardError => e
      log_audit_failure(:trigger_drop, actor, e.message, reason: reason,
                                                         confirmation_text: confirmation, before_state: before_state)
      raise
    end

    # Re-executes this trigger by dropping and recreating it.
    #
    # @param reason [String] Required reason for re-executing the trigger
    # @param confirmation [String, nil] Optional confirmation text for kill switch protection
    # @param actor [Hash, nil] Information about who is performing the action (must have :type and :id keys)
    # @raise [ArgumentError] If reason is missing or empty
    # @raise [PgSqlTriggers::KillSwitchError] If kill switch blocks the operation
    # @raise [StandardError] If SQL cannot be generated to recreate the trigger
    # @return [PgSqlTriggers::TriggerRegistry] self
    def re_execute!(reason:, confirmation: nil, actor: nil)
      actor ||= { type: "Console", id: "TriggerRegistry#re_execute!" }
      before_state = capture_state
      drift_info = begin
        drift_result
      rescue StandardError
        nil
      end

      # Check kill switch before re-executing trigger
      PgSqlTriggers::SQL::KillSwitch.check!(
        operation: :trigger_re_execute,
        environment: Rails.env,
        confirmation: confirmation,
        actor: actor
      )

      # Validate reason is provided
      raise ArgumentError, "Reason is required" if reason.nil? || reason.to_s.strip.empty?

      log_re_execute_attempt(reason)

      # Execute the trigger creation/update in transaction
      ActiveRecord::Base.transaction do
        drop_existing_trigger_for_re_execute
        recreate_trigger
        update_registry_after_re_execute
        after_state = capture_state
        diff = drift_info ? "#{drift_info[:expected_sql]} -> #{after_state[:function_body]}" : nil
        log_audit_success(:trigger_re_execute, actor, reason: reason, confirmation_text: confirmation,
                                                      before_state: before_state, after_state: after_state, diff: diff)
      end
    rescue StandardError => e
      log_audit_failure(
        :trigger_re_execute, actor, e.message, reason: reason,
                                               confirmation_text: confirmation,
                                               before_state: before_state
      )
      raise
    end

    private

    def quote_identifier(identifier)
      ActiveRecord::Base.connection.quote_table_name(identifier.to_s)
    end

    def calculate_checksum
      deferral = PgSqlTriggers::DeferralChecksum.parts(
        constraint_trigger: constraint_trigger,
        deferrable: deferrable,
        initially: initially
      )
      events_segment = PgSqlTriggers::EventsChecksum.segment_from_definition_json(definition)
      Digest::SHA256.hexdigest([
        trigger_name,
        table_name,
        version,
        function_body || "",
        condition || "",
        timing || "before",
        for_each || "row",
        events_segment,
        *deferral
      ].join)
    end

    def verify!
      update!(last_verified_at: Time.current)
    end

    # Drop trigger helpers
    def log_drop_attempt(reason)
      return unless defined?(Rails.logger)

      Rails.logger.info "[TRIGGER_DROP] Dropping: #{trigger_name} on #{table_name}"
      Rails.logger.info "[TRIGGER_DROP] Reason: #{reason}"
    end

    def log_drop_success
      return unless defined?(Rails.logger)

      Rails.logger.info "[TRIGGER_DROP] Successfully removed from registry"
    end

    def drop_trigger_from_database
      trigger_exists = check_trigger_exists
      return unless trigger_exists

      execute_drop_sql
    end

    def check_trigger_exists
      introspection = PgSqlTriggers::DatabaseIntrospection.new
      introspection.trigger_exists?(trigger_name)
    rescue StandardError => e
      Rails.logger.warn("Could not check trigger existence: #{e.message}") if defined?(Rails.logger)
      false
    end

    def execute_drop_sql
      quoted_table = quote_identifier(table_name)
      quoted_trigger = quote_identifier(trigger_name)
      sql = "DROP TRIGGER IF EXISTS #{quoted_trigger} ON #{quoted_table};"
      ActiveRecord::Base.connection.execute(sql)
      Rails.logger.info "[TRIGGER_DROP] Dropped from database" if defined?(Rails.logger)
    rescue ActiveRecord::StatementInvalid, StandardError => e
      Rails.logger.error("[TRIGGER_DROP] Failed: #{e.message}") if defined?(Rails.logger)
      raise
    end

    # Re-execute trigger helpers
    def log_re_execute_attempt(reason)
      return unless defined?(Rails.logger)

      Rails.logger.info "[TRIGGER_RE_EXECUTE] Re-executing: #{trigger_name} on #{table_name}"
      Rails.logger.info "[TRIGGER_RE_EXECUTE] Reason: #{reason}"
      drift = drift_result
      Rails.logger.info "[TRIGGER_RE_EXECUTE] Current state: #{drift[:state]}"
    end

    def drop_existing_trigger_for_re_execute
      introspection = PgSqlTriggers::DatabaseIntrospection.new
      return unless introspection.trigger_exists?(trigger_name)

      quoted_table = quote_identifier(table_name)
      quoted_trigger = quote_identifier(trigger_name)
      drop_sql = "DROP TRIGGER IF EXISTS #{quoted_trigger} ON #{quoted_table};"
      ActiveRecord::Base.connection.execute(drop_sql)
      Rails.logger.info "[TRIGGER_RE_EXECUTE] Dropped existing" if defined?(Rails.logger)
    rescue StandardError => e
      Rails.logger.warn("[TRIGGER_RE_EXECUTE] Drop failed: #{e.message}") if defined?(Rails.logger)
    end

    def recreate_trigger
      # DSL triggers are recreated from the stored JSON definition (+build_trigger_sql_from_definition+).
      # Other sources may persist a full trigger SQL payload in +function_body+.
      sql = if source == "dsl"
              build_trigger_sql_from_definition
            else
              function_body.presence || build_trigger_sql_from_definition
            end

      raise StandardError, "Cannot re-execute: no SQL could be generated" if sql.blank?

      ActiveRecord::Base.connection.execute(sql)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.info "[TRIGGER_RE_EXECUTE] Re-created trigger"
      end
    rescue ActiveRecord::StatementInvalid, StandardError => e
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.error("[TRIGGER_RE_EXECUTE] Failed: #{e.message}")
      end
      raise
    end

    # Build a CREATE TRIGGER SQL statement from the stored DSL definition JSON.
    # Used by re_execute! when function_body is absent (the normal case for DSL triggers).
    def build_trigger_sql_from_definition
      return nil if definition.blank?

      defn = JSON.parse(definition)
      fn_name = defn["function_name"]
      return nil if fn_name.blank?

      t_name = table_name
      constraint = ActiveModel::Type::Boolean.new.cast(defn["constraint_trigger"])
      timing_kw = if constraint
                    "AFTER"
                  else
                    (defn["timing"] || timing || "before").to_s.upcase
                  end
      events_sql = PgSqlTriggers::EventsChecksum.events_sql_fragment(
        defn,
        quote_column: ->(col) { quote_identifier(col) }
      )
      cond = defn["condition"] || condition
      for_each_kw = (defn["for_each"] || for_each || "row").upcase

      create_kw = constraint ? "CREATE CONSTRAINT TRIGGER" : "CREATE TRIGGER"
      sql = "#{create_kw} #{quote_identifier(trigger_name)} "
      sql += "#{timing_kw} #{events_sql} ON #{quote_identifier(t_name)} "
      deferral = deferral_sql_fragment(defn)
      sql += "#{deferral} " if deferral.present?
      sql += "FOR EACH #{for_each_kw} "
      sql += "WHEN (#{cond}) " if cond.present?
      sql += "EXECUTE FUNCTION #{fn_name}();"
      sql
    rescue JSON::ParserError
      nil
    end

    def deferral_sql_fragment(defn)
      return "" unless ActiveModel::Type::Boolean.new.cast(defn["constraint_trigger"])

      case defn["deferrable"].to_s
      when "not_deferrable"
        "NOT DEFERRABLE"
      when "deferrable"
        case defn["initially"].to_s
        when "deferred"
          "DEFERRABLE INITIALLY DEFERRED"
        when "immediate"
          "DEFERRABLE INITIALLY IMMEDIATE"
        else
          "DEFERRABLE"
        end
      else
        ""
      end
    end

    def update_registry_after_re_execute
      update!(last_executed_at: Time.current)
      if !enabled && ActiveRecord::Base.connection.table_exists?(table_name)
        quoted_table   = quote_identifier(table_name)
        quoted_trigger = quote_identifier(trigger_name)
        ActiveRecord::Base.connection.execute(
          "ALTER TABLE #{quoted_table} DISABLE TRIGGER #{quoted_trigger};"
        )
      end
      Rails.logger.info "[TRIGGER_RE_EXECUTE] Updated registry" if defined?(Rails.logger)
    end

    # Audit logging helpers
    def capture_state
      {
        enabled: enabled,
        version: version,
        checksum: checksum,
        table_name: table_name,
        source: source,
        environment: environment,
        installed_at: installed_at&.iso8601,
        function_body: function_body
      }
    end

    def log_audit_success(operation, actor, **options)
      return unless defined?(PgSqlTriggers::AuditLog)

      PgSqlTriggers::AuditLog.log_success(
        operation: operation,
        trigger_name: trigger_name,
        actor: actor,
        environment: Rails.env,
        **options
      )
    rescue StandardError => e
      Rails.logger.error("Failed to log audit entry: #{e.message}") if defined?(Rails.logger)
    end

    def log_audit_failure(operation, actor, error_message, **options)
      return unless defined?(PgSqlTriggers::AuditLog)

      PgSqlTriggers::AuditLog.log_failure(
        operation: operation,
        trigger_name: trigger_name,
        actor: actor,
        environment: Rails.env,
        error_message: error_message,
        **options
      )
    rescue StandardError => e
      Rails.logger.error("Failed to log audit entry: #{e.message}") if defined?(Rails.logger)
    end

    # Persist the +enabled+ flag, with an in-memory fallback if the DB write fails.
    # Returns true when the update was persisted, false when only the in-memory value changed.
    def persist_enabled_state(value)
      update!(enabled: value)
      true
    rescue ActiveRecord::StatementInvalid, StandardError => e
      Rails.logger.warn("Could not persist enabled=#{value} on registry: #{e.message}") if defined?(Rails.logger)
      self.enabled = value
      false
    end
  end
  # rubocop:enable Metrics/ClassLength
end
