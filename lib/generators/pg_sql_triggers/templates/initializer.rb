# frozen_string_literal: true

PgSqlTriggers.configure do |config|
  # ========== Kill Switch Configuration ==========
  # The Kill Switch is a safety mechanism that prevents accidental destructive operations
  # in protected environments (production, staging, etc.)

  # Enable or disable the kill switch globally
  # Default: true (recommended for safety)
  config.kill_switch_enabled = true

  # Specify which environments should be protected by the kill switch
  # Default: %i[production staging]
  config.kill_switch_environments = %i[production staging]

  # Require confirmation text for kill switch overrides
  # When true, users must type a specific confirmation text to proceed
  # Default: true (recommended for maximum safety)
  config.kill_switch_confirmation_required = true

  # Custom confirmation pattern generator
  # Takes an operation symbol and returns the required confirmation text
  # Default: "EXECUTE <OPERATION_NAME>"
  config.kill_switch_confirmation_pattern = ->(operation) { "EXECUTE #{operation.to_s.upcase}" }

  # Logger for kill switch events
  # Default: Rails.logger
  config.kill_switch_logger = Rails.logger

  # Enable audit trail for kill switch events (optional enhancement)
  # When enabled, all kill switch events are logged to a database table
  # Default: false (can be enabled later)
  # config.kill_switch_audit_trail_enabled = false

  # Time-window auto-lock configuration (optional enhancement)
  # Automatically enable kill switch during specific time windows
  # Default: false
  # config.kill_switch_auto_lock_enabled = false
  # config.kill_switch_auto_lock_window = 30.minutes
  # config.kill_switch_auto_lock_after = -> { Time.current.hour.between?(22, 6) } # Night hours

  # Set the default environment detection
  # By default, uses Rails.env
  config.default_environment = -> { Rails.env }

  # Set a custom permission checker
  # This should return true/false based on the actor, action, and environment
  # Example:
  # config.permission_checker = ->(actor, action, environment) {
  #   # Your custom permission logic here
  #   # e.g., check if actor has required role for the action
  #   true
  # }
  config.permission_checker = nil

  # Tables to exclude from listing in the UI
  # Default excluded tables: ar_internal_metadata, schema_migrations, pg_sql_triggers_registry, trigger_migrations
  # Add additional tables you want to exclude:
  # config.excluded_tables = %w[audit_logs temporary_data]
  config.excluded_tables = []
end
