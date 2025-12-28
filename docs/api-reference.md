# API Reference

Complete reference for using PgSqlTriggers programmatically from the Rails console or within your application code.

## Table of Contents

- [Registry API](#registry-api)
- [Migrator API](#migrator-api)
- [Kill Switch API](#kill-switch-api)
- [DSL API](#dsl-api)
- [TriggerRegistry Model](#triggerregistry-model)

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
  version 1
  enabled false
  when_env :production
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
- `events` (Symbols): One or more of `:insert`, `:update`, `:delete`

#### `function(function_name)`

Specifies the PostgreSQL function to execute.

```ruby
function :validate_user_email
```

**Parameters**:
- `function_name` (Symbol): Function name

#### `version(number)`

Sets the trigger version.

```ruby
version 1
version 2
```

**Parameters**:
- `number` (Integer): Version number

#### `enabled(state)`

Sets the initial enabled state.

```ruby
enabled true
enabled false
```

**Parameters**:
- `state` (Boolean): Initial state

#### `when_env(*environments)`

Restricts trigger to specific environments.

```ruby
when_env :production
when_env :production, :staging
```

**Parameters**:
- `environments` (Symbols): One or more environment names

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
trigger.enabled            # => false
trigger.environments       # => ["production"]
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

#### `drop!(confirmation: nil)`

Drops the trigger from the database.

```ruby
trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "users_email_validation")
trigger.drop!(confirmation: "EXECUTE TRIGGER_DROP")
```

**Parameters**:
- `confirmation` (String, optional): Kill switch confirmation text

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
drift = PgSqlTriggers::Registry.diff
puts "Drifted triggers: #{drift[:drifted].count}"

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
# Generate a drift report
drift = PgSqlTriggers::Registry.diff

puts "=== Drift Report ==="
puts "In Sync: #{drift[:in_sync].count}"
puts "Drifted: #{drift[:drifted].count}"
puts "Manual Override: #{drift[:manual_override].count}"
puts "Disabled: #{drift[:disabled].count}"
puts "Dropped: #{drift[:dropped].count}"
puts "Unknown: #{drift[:unknown].count}"

# List all triggers with details
triggers = PgSqlTriggers::Registry.list

puts "\n=== Trigger Inventory ==="
triggers.each do |trigger|
  puts "#{trigger.trigger_name}:"
  puts "  Table: #{trigger.table_name}"
  puts "  Function: #{trigger.function_name}"
  puts "  Events: #{trigger.events.join(', ')}"
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

## Next Steps

- [Usage Guide](usage-guide.md) - Learn the DSL and migration system
- [Kill Switch](kill-switch.md) - Production safety features
- [Configuration](configuration.md) - Configure advanced settings
