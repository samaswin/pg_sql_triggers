# frozen_string_literal: true

module PgSqlTriggers
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

    # Drift states
    def drift_state
      # This will be implemented by the Drift::Detector
      PgSqlTriggers::Drift.detect(trigger_name)
    end

    def enable!(confirmation: nil)
      # Check kill switch before enabling trigger
      # Use Rails.env for kill switch check, not the trigger's environment field
      PgSqlTriggers::SQL::KillSwitch.check!(
        operation: :trigger_enable,
        environment: Rails.env,
        confirmation: confirmation,
        actor: { type: "Console", id: "TriggerRegistry#enable!" }
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
          sql = "ALTER TABLE #{quote_identifier(table_name)} ENABLE TRIGGER #{quote_identifier(trigger_name)};"
          ActiveRecord::Base.connection.execute(sql)
        rescue ActiveRecord::StatementInvalid => e
          # If trigger doesn't exist or can't be enabled, continue to update registry
          Rails.logger.warn("Could not enable trigger: #{e.message}") if defined?(Rails.logger)
        end
      end

      # Update the registry record (always update, even if trigger doesn't exist)
      update!(enabled: true)
    end

    def disable!(confirmation: nil)
      # Check kill switch before disabling trigger
      # Use Rails.env for kill switch check, not the trigger's environment field
      PgSqlTriggers::SQL::KillSwitch.check!(
        operation: :trigger_disable,
        environment: Rails.env,
        confirmation: confirmation,
        actor: { type: "Console", id: "TriggerRegistry#disable!" }
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
          sql = "ALTER TABLE #{quote_identifier(table_name)} DISABLE TRIGGER #{quote_identifier(trigger_name)};"
          ActiveRecord::Base.connection.execute(sql)
        rescue ActiveRecord::StatementInvalid => e
          # If trigger doesn't exist or can't be disabled, continue to update registry
          Rails.logger.warn("Could not disable trigger: #{e.message}") if defined?(Rails.logger)
        end
      end

      # Update the registry record (always update, even if trigger doesn't exist)
      update!(enabled: false)
    end

    private

    def quote_identifier(identifier)
      ActiveRecord::Base.connection.quote_table_name(identifier.to_s)
    end

    def calculate_checksum
      Digest::SHA256.hexdigest([trigger_name, table_name, version, function_body, condition].join)
    end

    def verify!
      update!(last_verified_at: Time.current)
    end
  end
end
