# Kill Switch Documentation

The Kill Switch is a centralized safety mechanism that prevents accidental destructive operations in protected environments (production, staging, etc.).

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Configuration](#configuration)
- [CLI Usage](#cli-usage)
- [Console Usage](#console-usage)
- [Web UI Usage](#web-ui-usage)
- [Protected Operations](#protected-operations)
- [Logging and Auditing](#logging-and-auditing)
- [Customization](#customization)

## Overview

The Kill Switch provides multiple layers of protection for dangerous operations:

1. **Environment Detection**: Automatically identifies protected environments
2. **Operation Blocking**: Prevents destructive operations by default
3. **Explicit Confirmation**: Requires typed confirmation text for overrides
4. **Audit Logging**: Records all attempts and overrides

### Key Benefits

- **Prevents Accidents**: Stops unintended operations in production
- **Requires Intent**: Explicit confirmation proves deliberate action
- **Maintains Audit Trail**: All operations are logged for compliance
- **Flexible Control**: Can be configured per environment and operation

## How It Works

The Kill Switch operates on three levels:

### Level 1: Configuration
Environment-based activation via `kill_switch_enabled` and `kill_switch_environments`:

```ruby
config.kill_switch_enabled = true
config.kill_switch_environments = %i[production staging]
```

### Level 2: Runtime Override
ENV variable support for CI/CD and automation:

```bash
KILL_SWITCH_OVERRIDE=true rake trigger:migrate
```

### Level 3: Explicit Confirmation
Typed confirmation text proves intentional action:

```bash
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE TRIGGER_MIGRATE" rake trigger:migrate
```

### Decision Flow

```
┌─────────────────────────────────────┐
│   Operation Requested               │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Is Kill Switch Enabled?             │
└──────────────┬──────────────────────┘
               │ Yes
               ▼
┌─────────────────────────────────────┐
│ Is Environment Protected?           │
└──────────────┬──────────────────────┘
               │ Yes
               ▼
┌─────────────────────────────────────┐
│ Is Override Provided?               │
└──────────────┬──────────────────────┘
               │ Yes
               ▼
┌─────────────────────────────────────┐
│ Is Confirmation Valid?              │
└──────────────┬──────────────────────┘
               │ Yes
               ▼
┌─────────────────────────────────────┐
│ ✓ Operation Allowed                 │
│ (Logged as OVERRIDDEN)              │
└─────────────────────────────────────┘

               │ No at any step
               ▼
┌─────────────────────────────────────┐
│ ✗ Operation Blocked                 │
│ (Logged as BLOCKED)                 │
└─────────────────────────────────────┘
```

## Configuration

Configure the Kill Switch in your initializer:

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  # Enable or disable the kill switch globally (default: true)
  config.kill_switch_enabled = true

  # Specify which environments to protect (default: [:production, :staging])
  config.kill_switch_environments = %i[production staging]

  # Require confirmation text for overrides (default: true)
  config.kill_switch_confirmation_required = true

  # Custom confirmation pattern (default: "EXECUTE <OPERATION>")
  config.kill_switch_confirmation_pattern = ->(operation) {
    "EXECUTE #{operation.to_s.upcase}"
  }

  # Logger for kill switch events (default: Rails.logger)
  config.kill_switch_logger = Rails.logger
end
```

### Configuration Options

#### `kill_switch_enabled`
- **Type**: Boolean
- **Default**: `true`
- **Description**: Master toggle for the entire kill switch system

```ruby
config.kill_switch_enabled = false  # Disable kill switch completely
```

#### `kill_switch_environments`
- **Type**: Array of Symbols
- **Default**: `[:production, :staging]`
- **Description**: List of environments where kill switch is active

```ruby
config.kill_switch_environments = [:production]  # Only protect production
config.kill_switch_environments = [:production, :staging, :demo]  # Multiple environments
```

#### `kill_switch_confirmation_required`
- **Type**: Boolean
- **Default**: `true`
- **Description**: Whether confirmation text is required for overrides

```ruby
config.kill_switch_confirmation_required = false  # Only ENV override needed
```

#### `kill_switch_confirmation_pattern`
- **Type**: Lambda/Proc
- **Default**: `->(operation) { "EXECUTE #{operation.to_s.upcase}" }`
- **Description**: Generates the required confirmation text

```ruby
config.kill_switch_confirmation_pattern = ->(operation) {
  "CONFIRM-#{operation.to_s.upcase}-#{Date.today.strftime('%Y%m%d')}"
}
```

#### `kill_switch_logger`
- **Type**: Logger
- **Default**: `Rails.logger`
- **Description**: Logger for kill switch events

```ruby
config.kill_switch_logger = Logger.new('log/kill_switch.log')
```

## CLI Usage

### Rake Tasks

When running dangerous operations via rake tasks in protected environments, you must provide confirmation.

#### Basic Migration

```bash
# Without override - operation will be blocked in production
rake trigger:migrate
# => Error: Kill switch is active for production environment

# With ENV override and confirmation text
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE TRIGGER_MIGRATE" rake trigger:migrate
# => Success: Migration applied
```

#### Rollback

```bash
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE TRIGGER_ROLLBACK" rake trigger:rollback
```

#### Specific Migration Operations

```bash
# Apply specific migration
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE TRIGGER_MIGRATE_UP" \
  rake trigger:migrate:up VERSION=20231215120000

# Rollback specific migration
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE TRIGGER_MIGRATE_DOWN" \
  rake trigger:migrate:down VERSION=20231215120000

# Redo migration
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE TRIGGER_MIGRATE_REDO" \
  rake trigger:migrate:redo
```

#### Combined Migrations

```bash
# Schema and trigger migrations
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE DB_MIGRATE_WITH_TRIGGERS" \
  rake db:migrate:with_triggers

# Combined rollback
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE DB_ROLLBACK_WITH_TRIGGERS" \
  rake db:rollback:with_triggers
```

### Expected Confirmation Texts

| Operation | Required Confirmation Text |
|-----------|---------------------------|
| `trigger:migrate` | `EXECUTE TRIGGER_MIGRATE` |
| `trigger:rollback` | `EXECUTE TRIGGER_ROLLBACK` |
| `trigger:migrate:up` | `EXECUTE TRIGGER_MIGRATE_UP` |
| `trigger:migrate:down` | `EXECUTE TRIGGER_MIGRATE_DOWN` |
| `trigger:migrate:redo` | `EXECUTE TRIGGER_MIGRATE_REDO` |
| `db:migrate:with_triggers` | `EXECUTE DB_MIGRATE_WITH_TRIGGERS` |
| `db:rollback:with_triggers` | `EXECUTE DB_ROLLBACK_WITH_TRIGGERS` |

## Console Usage

### Using the Override Block

The `override` method provides a safe way to execute protected operations:

```ruby
# Enable a trigger in production
PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE TRIGGER_ENABLE") do
  trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
  trigger.enable!
end

# Disable a trigger
PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE TRIGGER_DISABLE") do
  trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
  trigger.disable!
end

# Run migrations programmatically
PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE MIGRATOR_RUN_UP") do
  PgSqlTriggers::Migrator.run_up
end
```

### Direct Confirmation Parameter

Some methods accept confirmation directly:

```ruby
# Enable/disable with direct confirmation
trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
trigger.disable!(confirmation: "EXECUTE TRIGGER_DISABLE")

# Migrator with direct confirmation
PgSqlTriggers::Migrator.run_up(nil, confirmation: "EXECUTE MIGRATOR_RUN_UP")
PgSqlTriggers::Migrator.run_down(nil, confirmation: "EXECUTE MIGRATOR_RUN_DOWN")
```

### Checking Kill Switch Status

```ruby
# Check if kill switch is active
PgSqlTriggers::SQL::KillSwitch.active?
# => true (in production)

# Check for specific operation
PgSqlTriggers::SQL::KillSwitch.check!(
  operation: :trigger_migrate,
  actor: { type: 'console', user: current_user.email }
)
# => Raises error if blocked, returns true if allowed

# Get current environment
PgSqlTriggers::SQL::KillSwitch.environment
# => "production"

# Check if environment is protected
PgSqlTriggers::SQL::KillSwitch.protected_environment?
# => true
```

### Console Examples

#### Safe Batch Operations

```ruby
# Enable multiple triggers safely
trigger_names = ["users_email_validation", "orders_billing_trigger"]

PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE BATCH_ENABLE") do
  trigger_names.each do |name|
    trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: name)
    trigger.enable!
    puts "Enabled: #{name}"
  end
end
```

#### Migration with Validation

```ruby
PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE TRIGGER_MIGRATE") do
  # Check pending migrations
  pending = PgSqlTriggers::Migrator.pending_migrations
  puts "Pending migrations: #{pending.count}"

  # Apply migrations
  PgSqlTriggers::Migrator.run_up

  # Validate results
  PgSqlTriggers::Registry.validate!
  puts "All triggers validated successfully"
end
```

## Web UI Usage

When accessing the web UI in protected environments, dangerous operations require confirmation.

### Visual Indicators

1. **Kill Switch Badge**: Shows "Protected Environment" banner
2. **Warning Icons**: Yellow/red indicators on dangerous actions
3. **Confirmation Modals**: Pop-ups requiring exact confirmation text

### Workflow

1. Navigate to the desired operation (e.g., "Apply Migration")
2. Click the action button
3. A modal appears showing:
   - Operation description
   - Required confirmation text
   - Warning message
4. Type the exact confirmation text (e.g., "EXECUTE UI_MIGRATION_UP")
5. Click "Confirm"
6. Operation executes if confirmation matches

### UI Confirmation Texts

| Operation | Required Confirmation Text |
|-----------|---------------------------|
| Apply Migration (Up) | `EXECUTE UI_MIGRATION_UP` |
| Rollback Migration (Down) | `EXECUTE UI_MIGRATION_DOWN` |
| Redo Migration | `EXECUTE UI_MIGRATION_REDO` |
| Generate Trigger | `EXECUTE UI_TRIGGER_GENERATE` |
| Enable Trigger | `EXECUTE UI_TRIGGER_ENABLE` |
| Disable Trigger | `EXECUTE UI_TRIGGER_DISABLE` |
| Execute SQL | `EXECUTE UI_SQL` |

### Screenshot Example

![Kill Switch Modal](screenshots/kill-switch-modal.png)

## Protected Operations

### CLI Operations

All rake tasks that modify triggers or migrations:

- `trigger:migrate`
- `trigger:rollback`
- `trigger:migrate:up`
- `trigger:migrate:down`
- `trigger:migrate:redo`
- `db:migrate:with_triggers`
- `db:rollback:with_triggers`

### Console Operations

Registry and migrator methods:

- `TriggerRegistry#enable!`
- `TriggerRegistry#disable!`
- `TriggerRegistry#drop!`
- `Migrator.run_up`
- `Migrator.run_down`
- `Migrator.redo`

### Web UI Operations

All destructive UI actions:

- Migration up/down/redo
- Trigger enable/disable
- Trigger generation and application
- SQL capsule execution

## Logging and Auditing

All kill switch events are logged with comprehensive information.

### Log Format

```
[KILL_SWITCH] STATUS: operation=<operation> environment=<env> actor=<actor> [additional_info]
```

### Log Levels

#### BLOCKED
Operation was prevented:

```
[KILL_SWITCH] BLOCKED: operation=trigger_migrate environment=production actor=CLI:ashwin reason=no_override
```

#### OVERRIDDEN
Operation allowed with valid override:

```
[KILL_SWITCH] OVERRIDDEN: operation=trigger_migrate environment=production actor=CLI:ashwin source=env_with_confirmation confirmation=EXECUTE TRIGGER_MIGRATE
```

#### ALLOWED
Operation allowed (not in protected environment):

```
[KILL_SWITCH] ALLOWED: operation=trigger_migrate environment=development actor=CLI:ashwin reason=not_protected_environment
```

### Audit Information

Each log entry includes:

- **Operation**: The action being performed
- **Environment**: Current Rails environment
- **Actor**: Who is performing the operation
  - CLI: `CLI:username`
  - Console: `Console:user_email`
  - Web UI: `UI:user_id`
- **Status**: BLOCKED, OVERRIDDEN, or ALLOWED
- **Source**: How override was provided (if applicable)
- **Confirmation**: The confirmation text used (if applicable)
- **Reason**: Why it was blocked or allowed

### Custom Logging

Configure a separate log file for kill switch events:

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  kill_switch_logger = Logger.new(Rails.root.join('log', 'kill_switch.log'))
  kill_switch_logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] [#{severity}] #{msg}\n"
  end

  config.kill_switch_logger = kill_switch_logger
end
```

## Customization

### Custom Confirmation Patterns

#### Date-Based Confirmation

```ruby
config.kill_switch_confirmation_pattern = ->(operation) {
  "CONFIRM-#{operation.to_s.upcase}-#{Date.today.strftime('%Y%m%d')}"
}

# Usage:
# CONFIRMATION_TEXT="CONFIRM-TRIGGER_MIGRATE-20231215" rake trigger:migrate
```

#### Include Environment

```ruby
config.kill_switch_confirmation_pattern = ->(operation) {
  env = Rails.env.upcase
  "#{env}-EXECUTE-#{operation.to_s.upcase}"
}

# Usage:
# CONFIRMATION_TEXT="PRODUCTION-EXECUTE-TRIGGER_MIGRATE" rake trigger:migrate
```

#### Random Token (Not Recommended)

```ruby
# Generate a one-time token (store it somewhere accessible)
config.kill_switch_confirmation_pattern = ->(operation) {
  token = SecureRandom.hex(4)
  Rails.cache.write("kill_switch_token_#{operation}", token, expires_in: 5.minutes)
  token
}
```

### Custom Protected Environments

```ruby
# Protect additional environments
config.kill_switch_environments = [:production, :staging, :demo, :qa]

# Protect all non-development environments
config.kill_switch_environments = [:production, :staging, :test, :qa, :uat]
```

### Environment-Specific Configuration

```ruby
PgSqlTriggers.configure do |config|
  config.kill_switch_enabled = true

  # Different rules for different environments
  if Rails.env.production?
    config.kill_switch_confirmation_required = true
    config.kill_switch_confirmation_pattern = ->(op) {
      "PRODUCTION-EXECUTE-#{op.to_s.upcase}-#{Date.today.strftime('%Y%m%d')}"
    }
  elsif Rails.env.staging?
    config.kill_switch_confirmation_required = true
    config.kill_switch_confirmation_pattern = ->(op) { "STAGING-#{op.to_s.upcase}" }
  end
end
```

## Best Practices

1. **Never Disable in Production**: Keep kill switch enabled for production
2. **Use Descriptive Confirmations**: Make confirmation texts clear and intentional
3. **Document Overrides**: Log why you're overriding protection
4. **Review Logs Regularly**: Audit kill switch logs for unexpected activity
5. **Test in Lower Environments**: Verify operations work before production
6. **Automate Safely**: Use kill switch overrides in CI/CD with proper controls
7. **Train Your Team**: Ensure everyone understands the kill switch system

## Troubleshooting

### Error: "Kill switch is active"

**Cause**: Attempting a protected operation without proper override.

**Solution**:
```bash
# Provide both override and confirmation
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE <OPERATION>" rake <task>
```

### Error: "Invalid confirmation text"

**Cause**: Confirmation text doesn't match the expected pattern.

**Solution**: Check the error message for the exact required text and copy it exactly.

### Kill Switch Not Working

**Check**:
1. Is `kill_switch_enabled` set to `true`?
2. Is the current environment in `kill_switch_environments`?
3. Are you testing in a protected environment?

### Logs Not Appearing

**Check**:
1. Is `kill_switch_logger` configured correctly?
2. Does the log file have write permissions?
3. Is the log level appropriate?

## Next Steps

- [Configuration](configuration.md) - Full configuration reference
- [Web UI](web-ui.md) - Using kill switch in the web interface
- [API Reference](api-reference.md) - Programmatic access to kill switch
