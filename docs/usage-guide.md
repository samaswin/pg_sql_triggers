# Usage Guide

This guide covers the core features of PgSqlTriggers: trigger definitions using the DSL, migration management, and drift detection.

## Table of Contents

- [Declaring Triggers](#declaring-triggers)
- [Trigger Migrations](#trigger-migrations)
- [Combined Schema and Trigger Migrations](#combined-schema-and-trigger-migrations)
- [Drift Detection](#drift-detection)

## Declaring Triggers

PgSqlTriggers provides a Ruby DSL for defining triggers. Trigger definitions are declarative and separate from their implementation.

### Basic Trigger Definition

Create trigger definition files in `app/triggers/` (or scaffold them with the CLI generator — see below):

```ruby
# app/triggers/users_email_validation.rb
PgSqlTriggers::DSL.pg_sql_trigger "users_email_validation" do
  table :users
  on :insert, :update
  function :validate_user_email

  self.version = 1
  self.enabled = true
  timing :before
end
```

### DSL Reference

#### `table`
Specifies which table the trigger is attached to:

```ruby
table :users
```

#### `on`
Defines when the trigger fires (one or more events):

```ruby
on :insert              # Single event
on :insert, :update     # Multiple events
on :delete              # Delete operations
```

#### `function`
The PostgreSQL function that the trigger executes:

```ruby
function :validate_user_email
```

#### `version`
Version number for tracking changes:

```ruby
self.version = 1  # Increment when trigger logic changes
```

#### `enabled`
Initial state of the trigger (defaults to `true`):

```ruby
self.enabled = true   # Trigger is active (default)
self.enabled = false  # Trigger is inactive
```

#### `for_each_row` / `for_each_statement`
PostgreSQL execution granularity (defaults to row-level):

```ruby
for_each_row       # FOR EACH ROW (default)
for_each_statement # FOR EACH STATEMENT
```

#### `when_env`
**Deprecated.** Environment-specific trigger declarations cause schema drift between environments.
Use application-level configuration to gate trigger behaviour by environment instead.
Calling `when_env` emits a deprecation warning and will be removed in a future major version.

#### `timing`
Specifies when the trigger fires relative to the event (BEFORE or AFTER):

```ruby
timing :before  # Trigger fires before constraint checks (default)
timing :after   # Trigger fires after constraint checks
```

#### `on_update_of`
Declares a **column-level** trigger that fires only when specific columns change
(PostgreSQL `UPDATE OF col1, col2`). This is a common performance optimisation for audit
triggers: they run only when the columns you care about are modified.

```ruby
on_update_of :email, :status   # Sets event to UPDATE and records columns
```

Notes:
- `on_update_of` sets the event to `update` and stores the column list; calling `on(...)` again
  clears the column list.
- Column names must be simple SQL identifiers (`[a-zA-Z_][a-zA-Z0-9_]*`). The gem quotes them
  in generated SQL, so pass them unquoted.
- The column list is included in the checksum, so changing the list is detected as drift.

#### `constraint_trigger!` / `deferrable` / `initially`
Declares a **constraint trigger** (`CREATE CONSTRAINT TRIGGER`) with optional deferral. Constraint
triggers must be `AFTER` triggers, cannot use `TRUNCATE`, and are the only triggers that can be
deferred.

```ruby
PgSqlTriggers::DSL.pg_sql_trigger "orders_integrity_check" do
  table :orders
  on :insert, :update
  function :check_orders_referential_integrity

  constraint_trigger!         # Emits CREATE CONSTRAINT TRIGGER, forces timing :after
  self.deferrable = :deferrable
  self.initially  = :deferred # Evaluate at transaction commit
end
```

Valid combinations:

| `deferrable`        | `initially`                | SQL clause                          |
|---------------------|----------------------------|-------------------------------------|
| `:deferrable`       | `:deferred`                | `DEFERRABLE INITIALLY DEFERRED`     |
| `:deferrable`       | `:immediate` (or `nil`)    | `DEFERRABLE INITIALLY IMMEDIATE`    |
| `:not_deferrable`   | (must be `nil`)            | `NOT DEFERRABLE`                    |
| `nil`               | `nil`                      | (no deferral clause)                |

`Registry::Validator` rejects `deferrable`/`initially` unless `constraint_trigger!` is set,
and rejects constraint triggers that use `:before` timing or `TRUNCATE` events. Drift detection
reads deferral state from `pg_trigger.tgdeferrable` / `tginitdeferred` so changes made outside
the gem are surfaced as drift.

#### `depends_on`
Declares an **ordering hint** relative to another trigger on the same table. PostgreSQL fires
same-kind triggers in alphabetical order by name; `depends_on` captures the intended order so the
registry validator can verify that naming matches dependency declarations.

```ruby
PgSqlTriggers::DSL.pg_sql_trigger "log_user_change" do
  table :users
  on :insert, :update
  function :log_user_change
  timing :after

  depends_on "validate_user_email"   # Must exist on same table, same timing/FOR EACH, overlapping events
end
```

Run `rake trigger:validate_order` (or `PgSqlTriggers::Registry.validate!`) to enforce:

- Referenced prerequisite triggers exist and are on the same table.
- Prerequisites share timing (`before`/`after`), `FOR EACH` granularity, and have at least one
  overlapping event with the dependent.
- There are no circular dependencies.
- Names sort alphabetically in the required order (the prerequisite's name must sort before
  the dependent's).

The trigger detail page in the web UI displays prerequisites and dependents for DSL triggers.

### Complete Example

```ruby
# app/triggers/orders_billing_trigger.rb
PgSqlTriggers::DSL.pg_sql_trigger "orders_billing_trigger" do
  table :orders
  on :insert, :update
  function :calculate_order_total

  self.version = 2
  self.enabled = true
  timing :after
  for_each_row
end
```

## Trigger Generator

PgSqlTriggers provides a CLI generator that scaffolds a DSL definition and migration together from the command line.

### CLI Generator

```bash
rails generate pg_sql_triggers:trigger TRIGGER_NAME TABLE_NAME [EVENTS...] [--timing before|after] [--function fn_name]
```

Example:

```bash
rails generate pg_sql_triggers:trigger users_email_validation users insert update --timing before --function validate_user_email
```

This creates:
- `app/triggers/users_email_validation.rb` — DSL stub
- `db/triggers/TIMESTAMP_users_email_validation.rb` — migration with function + trigger SQL

Files are written directly into the working tree and go through version control and code review like any other source file.

### Migration-Only Generator

To generate a standalone trigger migration without a DSL stub:

```bash
rails generate pg_sql_triggers:trigger_migration add_user_validation
```

This creates a timestamped file in `db/triggers/` that you can edit to add your trigger logic.

## Trigger Migrations

Trigger migrations work similarly to Rails schema migrations but are specifically for PostgreSQL triggers and functions.

### Generating Migrations

Create a new trigger migration:

```bash
rails generate pg_sql_triggers:trigger_migration add_validation_trigger
```

This creates a timestamped file in `db/triggers/`:

```
db/triggers/20231215120000_add_validation_trigger.rb
```

### Migration Structure

Migrations have `up` and `down` methods:

```ruby
# db/triggers/20231215120000_add_validation_trigger.rb
class AddValidationTrigger < PgSqlTriggers::Migration
  def up
    execute <<-SQL
      CREATE OR REPLACE FUNCTION validate_user_email()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
          RAISE EXCEPTION 'Invalid email format';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER user_email_validation
      BEFORE INSERT OR UPDATE ON users
      FOR EACH ROW
      EXECUTE FUNCTION validate_user_email();
    SQL
  end

  def down
    execute <<-SQL
      DROP TRIGGER IF EXISTS user_email_validation ON users;
      DROP FUNCTION IF EXISTS validate_user_email();
    SQL
  end
end
```

### Running Migrations

#### Apply All Pending Migrations

```bash
rake trigger:migrate
```

#### Rollback Last Migration

```bash
rake trigger:rollback
```

#### Rollback Multiple Steps

```bash
rake trigger:rollback STEP=3
```

#### Check Migration Status

```bash
rake trigger:migrate:status
```

Output example:
```
Status   Migration ID    Migration Name
--------------------------------------------------
   up    20231215120000  Add validation trigger
   up    20231216130000  Add billing trigger
  down   20231217140000  Add audit trigger
```

#### Run Specific Migration Up

```bash
rake trigger:migrate:up VERSION=20231215120000
```

#### Run Specific Migration Down

```bash
rake trigger:migrate:down VERSION=20231215120000
```

#### Redo Last Migration

```bash
rake trigger:migrate:redo
```

This rolls back and re-applies the last migration.

### Migration Best Practices

1. **Always Provide Down Method**: Ensure migrations are reversible
2. **Use Idempotent SQL**: Use `CREATE OR REPLACE FUNCTION` and `DROP ... IF EXISTS`
3. **Test in Development**: Verify migrations work before applying to production
4. **Version Control**: Commit migration files to git
5. **Incremental Changes**: Keep migrations small and focused

### Complex Migration Example

```ruby
# db/triggers/20231218150000_add_order_audit.rb
class AddOrderAudit < PgSqlTriggers::Migration
  def up
    execute <<-SQL
      -- Create audit table
      CREATE TABLE IF NOT EXISTS order_audits (
        id SERIAL PRIMARY KEY,
        order_id INTEGER NOT NULL,
        operation VARCHAR(10) NOT NULL,
        old_data JSONB,
        new_data JSONB,
        changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      -- Create audit function
      CREATE OR REPLACE FUNCTION audit_order_changes()
      RETURNS TRIGGER AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          INSERT INTO order_audits (order_id, operation, old_data)
          VALUES (OLD.id, 'DELETE', row_to_json(OLD));
          RETURN OLD;
        ELSIF TG_OP = 'UPDATE' THEN
          INSERT INTO order_audits (order_id, operation, old_data, new_data)
          VALUES (NEW.id, 'UPDATE', row_to_json(OLD), row_to_json(NEW));
          RETURN NEW;
        ELSIF TG_OP = 'INSERT' THEN
          INSERT INTO order_audits (order_id, operation, new_data)
          VALUES (NEW.id, 'INSERT', row_to_json(NEW));
          RETURN NEW;
        END IF;
      END;
      $$ LANGUAGE plpgsql;

      -- Create trigger
      CREATE TRIGGER order_audit_trigger
      AFTER INSERT OR UPDATE OR DELETE ON orders
      FOR EACH ROW
      EXECUTE FUNCTION audit_order_changes();
    SQL
  end

  def down
    execute <<-SQL
      DROP TRIGGER IF EXISTS order_audit_trigger ON orders;
      DROP FUNCTION IF EXISTS audit_order_changes();
      DROP TABLE IF EXISTS order_audits;
    SQL
  end
end
```

## Combined Schema and Trigger Migrations

For convenience, PgSqlTriggers provides rake tasks that run both schema and trigger migrations together.

### Run Both Migrations

```bash
rake db:migrate:with_triggers
```

This runs:
1. `rake db:migrate` (Rails schema migrations)
2. `rake trigger:migrate` (Trigger migrations)

### Rollback Both

```bash
rake db:rollback:with_triggers
```

This rolls back:
1. The most recent trigger migration
2. The most recent schema migration

### Check Status of Both

```bash
rake db:migrate:status:with_triggers
```

Shows status of both schema and trigger migrations.

### Get Versions of Both

```bash
rake db:version:with_triggers
```

Displays current versions of both migration types.

## Drift Detection

PgSqlTriggers automatically detects when the actual database state differs from your DSL definitions.

### Drift States

#### Managed & In Sync
The trigger exists in the database and matches the DSL definition exactly.

```
Status: ✓ Managed & In Sync
```

#### Managed & Drifted
The trigger exists but its definition doesn't match the DSL (e.g., function modified outside PgSqlTriggers).

```
Status: ⚠ Managed & Drifted
```

**Actions:**
- Review the differences
- Update the DSL to match the database
- Re-apply the migration to restore the DSL definition

#### Manual Override
The trigger was modified outside of PgSqlTriggers (e.g., via direct SQL).

```
Status: ⚠ Manual Override
```

**Actions:**
- Document the manual changes
- Update the DSL to reflect the changes
- Create a new migration if needed

#### Disabled
The trigger is disabled via PgSqlTriggers.

```
Status: ○ Disabled
```

**Actions:**
- Enable via console or Web UI
- Verify the trigger is needed

#### Dropped
The trigger was dropped but still exists in the registry.

```
Status: ✗ Dropped
```

**Actions:**
- Re-apply the migration
- Remove from registry if no longer needed

#### Unknown
The trigger exists in the database but not in the PgSqlTriggers registry.

```
Status: ? Unknown
```

**Actions:**
- Add a DSL definition for the trigger
- Create a migration to bring it under management
- Drop it if it's no longer needed

### Checking for Drift

#### Via Console

```ruby
# Get drift information for all triggers
PgSqlTriggers::Registry.diff
```

#### Via Web UI

Navigate to the dashboard at `/pg_sql_triggers` to see drift status visually.

### Resolving Drift

1. **Review the Drift**: Understand what changed and why
2. **Choose Resolution**:
   - Update DSL to match database
   - Re-apply migration to match DSL
   - Create new migration for intentional changes
3. **Verify**: Check that drift is resolved

Example:

```ruby
# Check current state
drift = PgSqlTriggers::Registry.diff

# Review specific trigger
trigger = PgSqlTriggers::Registry.find_by(trigger_name: "users_email_validation")
trigger.drift_status # => "drifted"

# Re-apply migration to fix drift
rake trigger:migrate:redo
```

## Next Steps

- [Web UI Documentation](web-ui.md) - Manage triggers through the web interface
- [Kill Switch](kill-switch.md) - Production safety features
- [API Reference](api-reference.md) - Console commands and programmatic access
