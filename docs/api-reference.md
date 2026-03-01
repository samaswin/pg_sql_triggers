# API Reference

Complete reference for using PgSqlTriggers programmatically from the Rails console or within your application code.

## Table of Contents

- [Registry API](#registry-api)
- [Migrator API](#migrator-api)
- [Kill Switch API](#kill-switch-api)
- [DSL API](#dsl-api)
- [TriggerRegistry Model](#triggerregistry-model)
- [Audit Log API](#audit-log-api)

> **Removed in 1.4.0**: `SQL::Capsule` and `SQL::Executor` have been removed. See [CHANGELOG](../CHANGELOG.md) for details.

## Registry API

The Registry API provides methods for inspecting and managing triggers.

### `PgSqlTriggers::Registry.list`

Returns all registered triggers.

```ruby
triggers = PgSqlTriggers::Registry.list
# => [#<PgSqlTriggers::TriggerRegistry...>, ...]

triggers.each do |trigger|
  puts "#{trigger.trigger_name} - #{trigger.status}"
end
```

**Returns**: Array of `TriggerRegistry` records

### `PgSqlTriggers::Registry.enabled`

Returns only enabled triggers.

```ruby
enabled_triggers = PgSqlTriggers::Registry.enabled
# => [#<PgSqlTriggers::TriggerRegistry...>, ...]

puts "Enabled triggers: #{enabled_triggers.count}"
```

**Returns**: Array of `TriggerRegistry` records

### `PgSqlTriggers::Registry.disabled`

Returns only disabled triggers.

```ruby
disabled_triggers = PgSqlTriggers::Registry.disabled
# => [#<PgSqlTriggers::TriggerRegistry...>, ...]

disabled_triggers.each do |trigger|
  puts "Disabled: #{trigger.trigger_name}"
end
```

**Returns**: Array of `TriggerRegistry` records

### `PgSqlTriggers::Registry.for_table(table_name)`

Returns triggers for a specific table.

```ruby
user_triggers = PgSqlTriggers::Registry.for_table(:users)
# => [#<PgSqlTriggers::TriggerRegistry...>, ...]

user_triggers.each do |trigger|
  puts trigger.trigger_name
end
```

**Parameters**:
- `table_name` (Symbol or String): The table name

**Returns**: Array of `TriggerRegistry` records

### `PgSqlTriggers::Registry.diff`

Checks for drift between DSL definitions and database state.

```ruby
drift_info = PgSqlTriggers::Registry.diff
# => {
#   in_sync: [...],
#   drifted: [...],
#   manual_override: [...],
#   disabled: [...],
#   dropped: [...],
#   unknown: [...]
# }

drift_info[:drifted].each do |trigger|
  puts "Drifted: #{trigger.trigger_name}"
end
```

**Returns**: Hash with drift categories

### `PgSqlTriggers::Registry.drifted`

Returns all triggers that have drifted from their expected state.

```ruby
drifted_triggers = PgSqlTriggers::Registry.drifted
# => [
#   { state: "drifted", trigger_name: "users_email_validation", ... },
#   ...
# ]

drifted_triggers.each do |trigger|
  puts "Drifted: #{trigger[:trigger_name]}"
end
```

**Returns**: Array of drift result hashes for drifted triggers

### `PgSqlTriggers::Registry.in_sync`

Returns all triggers that are in sync with their expected state.

```ruby
in_sync_triggers = PgSqlTriggers::Registry.in_sync
# => [
#   { state: "in_sync", trigger_name: "billing_trigger", ... },
#   ...
# ]

puts "In sync triggers: #{in_sync_triggers.count}"
```

**Returns**: Array of drift result hashes for in-sync triggers

### `PgSqlTriggers::Registry.unknown_triggers`

Returns all unknown (external) triggers not managed by this gem.

```ruby
unknown = PgSqlTriggers::Registry.unknown_triggers
# => [
#   { state: "unknown", trigger_name: "external_trigger", ... },
#   ...
# ]

unknown.each do |trigger|
  puts "External trigger: #{trigger[:trigger_name]}"
end
```

**Returns**: Array of drift result hashes for unknown triggers

### `PgSqlTriggers::Registry.dropped`

Returns all triggers that have been dropped from the database.

```ruby
dropped_triggers = PgSqlTriggers::Registry.dropped
# => [
#   { state: "dropped", trigger_name: "old_trigger", ... },
#   ...
# ]

dropped_triggers.each do |trigger|
  puts "Dropped: #{trigger[:trigger_name]}"
end
```

**Returns**: Array of drift result hashes for dropped triggers

### `PgSqlTriggers::Registry.validate!`

Validates all triggers and raises an error if any are invalid.

```ruby
begin
  PgSqlTriggers::Registry.validate!
  puts "All triggers valid"
rescue PgSqlTriggers::ValidationError => e
  puts "Validation failed: #{e.message}"
end
```

**Raises**: `PgSqlTriggers::ValidationError` if validation fails

**Returns**: `true` if all triggers are valid

### `PgSqlTriggers::Registry.enable(trigger_name, actor:, confirmation: nil)`

Enables a trigger with permission and kill switch checks.

```ruby
# Enable trigger
PgSqlTriggers::Registry.enable(
  "users_email_validation",
  actor: { type: "user", id: "admin@example.com" },
  confirmation: "EXECUTE TRIGGER_ENABLE"
)

# With current user as actor
actor = { type: "user", id: current_user.email }
PgSqlTriggers::Registry.enable("billing_trigger", actor: actor, confirmation: "EXECUTE TRIGGER_ENABLE")
```

**Parameters**:
- `trigger_name` (String): The name of the trigger to enable
- `actor` (Hash): Information about who is performing the operation (requires `:type` and `:id` keys)
- `confirmation` (String, optional): Kill switch confirmation text

**Raises**: `PgSqlTriggers::PermissionError`, `PgSqlTriggers::KillSwitchError`, `ArgumentError`

**Returns**: `true` on success

### `PgSqlTriggers::Registry.disable(trigger_name, actor:, confirmation: nil)`

Disables a trigger with permission and kill switch checks.

```ruby
# Disable trigger
PgSqlTriggers::Registry.disable(
  "users_email_validation",
  actor: { type: "user", id: "admin@example.com" },
  confirmation: "EXECUTE TRIGGER_DISABLE"
)
```

**Parameters**:
- `trigger_name` (String): The name of the trigger to disable
- `actor` (Hash): Information about who is performing the operation
- `confirmation` (String, optional): Kill switch confirmation text

**Raises**: `PgSqlTriggers::PermissionError`, `PgSqlTriggers::KillSwitchError`, `ArgumentError`

**Returns**: `true` on success

### `PgSqlTriggers::Registry.drop(trigger_name, actor:, reason:, confirmation: nil)`

Drops a trigger from the database and removes it from the registry.

```ruby
# Drop trigger
PgSqlTriggers::Registry.drop(
  "old_trigger",
  actor: { type: "user", id: "admin@example.com" },
  reason: "No longer needed in production",
  confirmation: "EXECUTE TRIGGER_DROP"
)
```

**Parameters**:
- `trigger_name` (String): The name of the trigger to drop
- `actor` (Hash): Information about who is performing the operation (Admin permission required)
- `reason` (String): Required explanation for why the trigger is being dropped (logged for audit)
- `confirmation` (String, optional): Kill switch confirmation text

**Raises**: `PgSqlTriggers::PermissionError`, `PgSqlTriggers::KillSwitchError`, `ArgumentError`

**Returns**: `true` on success

### `PgSqlTriggers::Registry.re_execute(trigger_name, actor:, reason:, confirmation: nil)`

Re-executes a trigger by dropping and recreating it from the registry definition. Useful for fixing drifted triggers.

```ruby
# Re-execute drifted trigger
PgSqlTriggers::Registry.re_execute(
  "drifted_trigger",
  actor: { type: "user", id: "admin@example.com" },
  reason: "Fix drift detected in production",
  confirmation: "EXECUTE TRIGGER_RE_EXECUTE"
)
```

**Parameters**:
- `trigger_name` (String): The name of the trigger to re-execute
- `actor` (Hash): Information about who is performing the operation (Admin permission required)
- `reason` (String): Required explanation for why the trigger is being re-executed (logged for audit)
- `confirmation` (String, optional): Kill switch confirmation text

**Raises**: `PgSqlTriggers::PermissionError`, `PgSqlTriggers::KillSwitchError`, `ArgumentError`

**Returns**: `true` on success

## Migrator API

The Migrator API manages trigger migrations programmatically.

### `PgSqlTriggers::Migrator.run_up(version = nil, confirmation: nil)`

Applies pending migrations.

```ruby
# Apply all pending migrations
PgSqlTriggers::Migrator.run_up

# Apply up to a specific version
PgSqlTriggers::Migrator.run_up(20231215120000)

# With kill switch override
PgSqlTriggers::Migrator.run_up(nil, confirmation: "EXECUTE MIGRATOR_RUN_UP")
```

**Parameters**:
- `version` (Integer, optional): Target version to migrate to
- `confirmation` (String, optional): Kill switch confirmation text

**Returns**: Array of applied migration versions

### `PgSqlTriggers::Migrator.run_down(version = nil, confirmation: nil)`

Rolls back migrations.

```ruby
# Rollback last migration
PgSqlTriggers::Migrator.run_down

# Rollback to a specific version
PgSqlTriggers::Migrator.run_down(20231215120000)

# With kill switch override
PgSqlTriggers::Migrator.run_down(nil, confirmation: "EXECUTE MIGRATOR_RUN_DOWN")
```

**Parameters**:
- `version` (Integer, optional): Target version to rollback to
- `confirmation` (String, optional): Kill switch confirmation text

**Returns**: Array of rolled back migration versions

### `PgSqlTriggers::Migrator.redo(confirmation: nil)`

Rolls back and re-applies the last migration.

```ruby
# Redo last migration
PgSqlTriggers::Migrator.redo

# With kill switch override
PgSqlTriggers::Migrator.redo(confirmation: "EXECUTE MIGRATOR_REDO")
```

**Parameters**:
- `confirmation` (String, optional): Kill switch confirmation text

**Returns**: Migration version that was redone

### `PgSqlTriggers::Migrator.pending_migrations`

Returns list of pending migrations.

```ruby
pending = PgSqlTriggers::Migrator.pending_migrations
# => [#<PgSqlTriggers::Migration...>, ...]

pending.each do |migration|
  puts "Pending: #{migration.name} (#{migration.version})"
end
```

**Returns**: Array of pending migration objects

### `PgSqlTriggers::Migrator.migration_status`

Returns status of all migrations.

```ruby
status = PgSqlTriggers::Migrator.migration_status
# => [
#   { version: 20231215120000, name: "AddValidationTrigger", status: :up },
#   { version: 20231216130000, name: "AddBillingTrigger", status: :down },
#   ...
# ]

status.each do |migration|
  puts "#{migration[:version]} - #{migration[:name]}: #{migration[:status]}"
end
```

**Returns**: Array of hashes with migration information

### `PgSqlTriggers::Migrator.current_version`

Returns the current migration version.

```ruby
version = PgSqlTriggers::Migrator.current_version
# => 20231215120000

puts "Current version: #{version}"
```

**Returns**: Integer (migration timestamp) or `nil` if no migrations applied

## Kill Switch API

The Kill Switch API provides methods for checking and overriding production protections.

### `PgSqlTriggers::SQL::KillSwitch.active?`

Checks if kill switch is currently active.

```ruby
if PgSqlTriggers::SQL::KillSwitch.active?
  puts "Kill switch is enabled for this environment"
else
  puts "Kill switch is not active"
end
```

**Returns**: Boolean

### `PgSqlTriggers::SQL::KillSwitch.protected_environment?`

Checks if current environment is protected.

```ruby
if PgSqlTriggers::SQL::KillSwitch.protected_environment?
  puts "Current environment is protected"
else
  puts "Current environment is not protected"
end
```

**Returns**: Boolean

### `PgSqlTriggers::SQL::KillSwitch.environment`

Returns the current environment.

```ruby
env = PgSqlTriggers::SQL::KillSwitch.environment
# => "production"

puts "Current environment: #{env}"
```

**Returns**: String

### `PgSqlTriggers::SQL::KillSwitch.check!(operation:, actor:, confirmation: nil)`

Checks if an operation is allowed and raises an error if blocked.

```ruby
begin
  PgSqlTriggers::SQL::KillSwitch.check!(
    operation: :trigger_migrate,
    actor: { type: 'console', user: 'admin@example.com' },
    confirmation: "EXECUTE TRIGGER_MIGRATE"
  )
  # Operation is allowed
  puts "Operation allowed"
rescue PgSqlTriggers::KillSwitchError => e
  puts "Operation blocked: #{e.message}"
end
```

**Parameters**:
- `operation` (Symbol): The operation being performed
- `actor` (Hash): Information about who is performing the operation
- `confirmation` (String, optional): Confirmation text for override

**Raises**: `PgSqlTriggers::KillSwitchError` if operation is blocked

**Returns**: `true` if operation is allowed

### `PgSqlTriggers::SQL::KillSwitch.override(confirmation:, &block)`

Executes a block with kill switch override.

```ruby
PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE BATCH_ENABLE") do
  # Operations in this block bypass kill switch
  trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
  trigger.enable!

  puts "Trigger enabled"
end
```

**Parameters**:
- `confirmation` (String): Confirmation text
- `block`: Code to execute with override

**Raises**: `PgSqlTriggers::KillSwitchError` if confirmation is invalid

**Returns**: Result of the block

## DSL API

The DSL API is used to define triggers in your application.

### `PgSqlTriggers::DSL.pg_sql_trigger(name, &block)`

Defines a trigger.

```ruby
PgSqlTriggers::DSL.pg_sql_trigger "users_email_validation" do
  table :users
  on :insert, :update
  function :validate_user_email
  self.version = 1
  self.enabled = true
  timing :before
  for_each_row
end
```

**Parameters**:
- `name` (String): Unique trigger name
- `block`: DSL block defining the trigger

### DSL Methods

#### `table(table_name)`

Specifies the table for the trigger.

```ruby
table :users
```

**Parameters**:
- `table_name` (Symbol): Table name

#### `on(*events)`

Specifies trigger events.

```ruby
on :insert
on :insert, :update
on :insert, :update, :delete
```

**Parameters**:
- `events` (Symbols): One or more of `:insert`, `:update`, `:delete`, `:truncate`

#### `function(function_name)`

Specifies the PostgreSQL function to execute.

```ruby
function :validate_user_email
```

**Parameters**:
- `function_name` (Symbol): Function name

#### `self.version = number`

Sets the trigger version.

```ruby
self.version = 1  # Increment when trigger logic changes
self.version = 2
```

**Parameters**:
- `number` (Integer): Version number

#### `self.enabled = state`

Sets the initial enabled state. Defaults to `true`.

```ruby
self.enabled = true   # Trigger is active (default)
self.enabled = false  # Trigger is inactive
```

**Parameters**:
- `state` (Boolean): Initial state

#### `for_each_row` / `for_each_statement`

Specifies PostgreSQL execution granularity. Defaults to `for_each_row`.

```ruby
for_each_row       # FOR EACH ROW (default)
for_each_statement # FOR EACH STATEMENT
```

Stored in the `for_each` column on the registry table and included in checksum calculation.

#### `when_env(*environments)`

**Deprecated.** Restricts trigger to specific environments. Emits a deprecation warning on every call and will be removed in a future major version. Use application-level configuration to gate trigger behaviour by environment instead.

```ruby
when_env :production           # Deprecated — avoid in new code
when_env :production, :staging # Deprecated — avoid in new code
```

**Parameters**:
- `environments` (Symbols): One or more environment names

#### `timing(timing_value)`

Specifies when the trigger fires relative to the event.

```ruby
timing :before  # Trigger fires before constraint checks (default)
timing :after   # Trigger fires after constraint checks
```

**Parameters**:
- `timing_value` (Symbol or String): Either `:before` or `:after`

## TriggerRegistry Model

The `TriggerRegistry` ActiveRecord model represents a trigger in the registry.

### Attributes

```ruby
trigger = PgSqlTriggers::TriggerRegistry.first

trigger.trigger_name       # => "users_email_validation"
trigger.table_name         # => "users"
trigger.function_name      # => "validate_user_email"
trigger.events             # => ["insert", "update"]
trigger.version            # => 1
trigger.enabled            # => true
trigger.timing             # => "before" or "after"
trigger.for_each           # => "row" or "statement"
trigger.environments       # => [] (when_env is deprecated)
trigger.condition          # => "NEW.status = 'active'" or nil
trigger.created_at         # => 2023-12-15 12:00:00 UTC
trigger.updated_at         # => 2023-12-15 12:00:00 UTC
```

### Instance Methods

#### `enable!(confirmation: nil)`

Enables the trigger.

```ruby
trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
trigger.enable!

# With kill switch override
trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
```

**Parameters**:
- `confirmation` (String, optional): Kill switch confirmation text

**Returns**: `true` on success

#### `disable!(confirmation: nil)`

Disables the trigger.

```ruby
trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
trigger.disable!

# With kill switch override
trigger.disable!(confirmation: "EXECUTE TRIGGER_DISABLE")
```

**Parameters**:
- `confirmation` (String, optional): Kill switch confirmation text

**Returns**: `true` on success

#### `drop!(reason:, confirmation: nil, actor: nil)`

Drops the trigger from the database and removes it from the registry.

```ruby
trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "old_trigger")

# Drop with reason (required)
trigger.drop!(
  reason: "No longer needed in production",
  confirmation: "EXECUTE TRIGGER_DROP",
  actor: { type: "user", id: "admin@example.com" }
)
```

**Parameters**:
- `reason` (String, required): Explanation for why the trigger is being dropped (logged for audit trail)
- `confirmation` (String, optional): Kill switch confirmation text
- `actor` (Hash, optional): Information about who is performing the operation

**Raises**: `ArgumentError` if reason is blank, `PgSqlTriggers::KillSwitchError`

**Returns**: `true` on success

#### `re_execute!(reason:, confirmation: nil, actor: nil)`

Re-executes the trigger by dropping and recreating it from the registry definition. Useful for fixing drifted triggers.

```ruby
trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "drifted_trigger")

# Re-execute to fix drift
trigger.re_execute!(
  reason: "Fix drift detected after manual database changes",
  confirmation: "EXECUTE TRIGGER_RE_EXECUTE",
  actor: { type: "user", id: "admin@example.com" }
)
```

**Parameters**:
- `reason` (String, required): Explanation for why the trigger is being re-executed (logged for audit trail)
- `confirmation` (String, optional): Kill switch confirmation text
- `actor` (Hash, optional): Information about who is performing the operation

**Raises**: `ArgumentError` if reason is blank, `PgSqlTriggers::KillSwitchError`, `StandardError`

**Returns**: `true` on success

#### `drift_status`

Returns the drift status of the trigger.

```ruby
trigger = PgSqlTriggers::TriggerRegistry.first
status = trigger.drift_status
# => :in_sync, :drifted, :manual_override, :disabled, :dropped, or :unknown

case status
when :in_sync
  puts "Trigger is synchronized"
when :drifted
  puts "Trigger has drifted from DSL"
when :manual_override
  puts "Trigger was manually modified"
end
```

**Returns**: Symbol representing drift state

#### `apply!(confirmation: nil)`

Applies the trigger definition from DSL to the database.

```ruby
trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
trigger.apply!(confirmation: "EXECUTE TRIGGER_APPLY")
```

**Parameters**:
- `confirmation` (String, optional): Kill switch confirmation text

**Returns**: `true` on success

### Class Methods

#### `PgSqlTriggers::TriggerRegistry.find_by_name(name)`

Finds a trigger by name.

```ruby
trigger = PgSqlTriggers::TriggerRegistry.find_by_name("users_email_validation")
# => #<PgSqlTriggers::TriggerRegistry...>
```

**Parameters**:
- `name` (String): Trigger name

**Returns**: `TriggerRegistry` record or `nil`

#### `PgSqlTriggers::TriggerRegistry.for_environment(env)`

Returns triggers applicable to a specific environment.

```ruby
prod_triggers = PgSqlTriggers::TriggerRegistry.for_environment("production")
# => [#<PgSqlTriggers::TriggerRegistry...>, ...]
```

**Parameters**:
- `env` (String or Symbol): Environment name

**Returns**: Array of `TriggerRegistry` records

## Usage Examples

### Complete Workflow

```ruby
# 1. Check pending migrations
pending = PgSqlTriggers::Migrator.pending_migrations
puts "#{pending.count} pending migrations"

# 2. Apply migrations with override
PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE MIGRATOR_RUN_UP") do
  PgSqlTriggers::Migrator.run_up
end

# 3. List all triggers
triggers = PgSqlTriggers::Registry.list
puts "Total triggers: #{triggers.count}"

# 4. Check for drift
drifted = PgSqlTriggers::Registry.drifted
in_sync = PgSqlTriggers::Registry.in_sync
unknown = PgSqlTriggers::Registry.unknown_triggers
dropped = PgSqlTriggers::Registry.dropped

puts "Drifted: #{drifted.count}, In Sync: #{in_sync.count}, Unknown: #{unknown.count}, Dropped: #{dropped.count}"

# 5. Enable specific trigger
trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE") if trigger

# 6. Validate all triggers
begin
  PgSqlTriggers::Registry.validate!
  puts "All triggers valid"
rescue PgSqlTriggers::ValidationError => e
  puts "Validation error: #{e.message}"
end
```

### Batch Operations

```ruby
# Enable all disabled triggers
PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE BATCH_ENABLE") do
  disabled_triggers = PgSqlTriggers::Registry.disabled

  disabled_triggers.each do |trigger|
    trigger.enable!
    puts "Enabled: #{trigger.trigger_name}"
  end
end

# Disable all triggers for a specific table
PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE BATCH_DISABLE") do
  user_triggers = PgSqlTriggers::Registry.for_table(:users)

  user_triggers.each do |trigger|
    trigger.disable!
    puts "Disabled: #{trigger.trigger_name}"
  end
end
```

### Inspection and Reporting

```ruby
# Generate a drift report using dedicated query methods
puts "=== Drift Report ==="
puts "In Sync: #{PgSqlTriggers::Registry.in_sync.count}"
puts "Drifted: #{PgSqlTriggers::Registry.drifted.count}"
puts "Dropped: #{PgSqlTriggers::Registry.dropped.count}"
puts "Unknown: #{PgSqlTriggers::Registry.unknown_triggers.count}"

# Or get the full categorised hash
drift = PgSqlTriggers::Registry.diff
puts "Manual Override: #{drift[:manual_override].count}"

# List all triggers with details
triggers = PgSqlTriggers::Registry.list

puts "\n=== Trigger Inventory ==="
triggers.each do |trigger|
  puts "#{trigger.trigger_name}:"
  puts "  Table: #{trigger.table_name}"
  puts "  Function: #{trigger.function_name}"
  puts "  Events: #{trigger.events.join(', ')}"
  puts "  Timing: #{trigger.timing}"
  puts "  For Each: #{trigger.for_each}"
  puts "  Version: #{trigger.version}"
  puts "  Enabled: #{trigger.enabled}"
  puts "  Drift: #{trigger.drift_status}"
  puts ""
end
```

### Error Handling

```ruby
begin
  # Attempt operation without proper confirmation
  trigger = PgSqlTriggers::TriggerRegistry.first
  trigger.enable!
rescue PgSqlTriggers::KillSwitchError => e
  puts "Kill switch blocked operation: #{e.message}"
  # Extract required confirmation from error message
  # Re-attempt with proper confirmation
  trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
  puts e.backtrace.first(5)
end
```

## Audit Log API

The Audit Log API provides methods for querying and managing audit log entries.

### `PgSqlTriggers::AuditLog`

The `AuditLog` model provides methods for querying audit log entries.

#### Class Methods

##### `AuditLog.for_trigger_name(trigger_name)`

Get audit log entries for a specific trigger.

**Parameters:**
- `trigger_name` (String): The trigger name to query

**Returns:** `ActiveRecord::Relation` - Audit log entries for the trigger, ordered by most recent first

**Example:**
```ruby
# Get all audit log entries for a specific trigger
entries = PgSqlTriggers::AuditLog.for_trigger_name("users_email_validation")
entries.each do |entry|
  puts "#{entry.operation}: #{entry.status} at #{entry.created_at}"
end
```

##### `AuditLog.log_success(...)`

Log a successful operation to the audit log.

**Parameters:**
- `operation:` (Symbol, String): The operation being performed (e.g., `:trigger_enable`)
- `trigger_name:` (String, nil): The trigger name (if applicable)
- `actor:` (Hash): Information about who performed the action (e.g., `{ type: "UI", id: "123" }`)
- `environment:` (String, nil): The environment
- `reason:` (String, nil): Reason for the operation
- `confirmation_text:` (String, nil): Confirmation text used
- `before_state:` (Hash, nil): State before operation
- `after_state:` (Hash, nil): State after operation
- `diff:` (String, nil): Diff information

**Returns:** `AuditLog` instance or `nil` if logging fails

**Example:**
```ruby
PgSqlTriggers::AuditLog.log_success(
  operation: :trigger_enable,
  trigger_name: "users_email_validation",
  actor: { type: "Console", id: "admin@example.com" },
  environment: "production",
  before_state: { enabled: false },
  after_state: { enabled: true }
)
```

##### `AuditLog.log_failure(...)`

Log a failed operation to the audit log.

**Parameters:**
- `operation:` (Symbol, String): The operation being performed
- `trigger_name:` (String, nil): The trigger name (if applicable)
- `actor:` (Hash): Information about who performed the action
- `environment:` (String, nil): The environment
- `error_message:` (String): Error message (required)
- `reason:` (String, nil): Reason for the operation (if provided before failure)
- `confirmation_text:` (String, nil): Confirmation text used
- `before_state:` (Hash, nil): State before operation

**Returns:** `AuditLog` instance or `nil` if logging fails

**Example:**
```ruby
PgSqlTriggers::AuditLog.log_failure(
  operation: :trigger_enable,
  trigger_name: "users_email_validation",
  actor: { type: "UI", id: "user_123" },
  environment: "production",
  error_message: "Trigger does not exist in database",
  before_state: { enabled: false }
)
```

#### Scopes

The `AuditLog` model provides several useful scopes:

- `AuditLog.for_trigger(trigger_name)` - Filter by trigger name
- `AuditLog.for_operation(operation)` - Filter by operation type
- `AuditLog.for_environment(env)` - Filter by environment
- `AuditLog.successful` - Only successful operations
- `AuditLog.failed` - Only failed operations
- `AuditLog.recent` - Order by most recent first

**Example:**
```ruby
# Get all failed operations in production
failed_ops = PgSqlTriggers::AuditLog
  .failed
  .for_environment("production")
  .recent
  .limit(10)

# Get all enable operations for a trigger
enable_ops = PgSqlTriggers::AuditLog
  .for_trigger("users_email_validation")
  .for_operation("trigger_enable")
  .recent
```

## Next Steps

- [Usage Guide](usage-guide.md) - Learn the DSL and migration system
- [Kill Switch](kill-switch.md) - Production safety features
- [Configuration](configuration.md) - Configure advanced settings
