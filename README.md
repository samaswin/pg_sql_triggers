# PgSqlTriggers

> **A PostgreSQL Trigger Control Plane for Rails**

Production-grade PostgreSQL trigger management for Rails with lifecycle management, safe deploys, versioning, drift detection, and a mountable UI.

## Why PgSqlTriggers?

Rails teams use PostgreSQL triggers for data integrity, performance, and billing logic. But triggers today are:

- Managed manually
- Invisible to Rails
- Unsafe to deploy
- Easy to drift

**PgSqlTriggers** brings triggers into the Rails ecosystem with:

- Lifecycle management
- Safe deploys
- Versioning
- UI control
- Emergency SQL escape hatches

## Examples

For working examples and a complete demonstration of PgSqlTriggers in action, check out the [example repository](https://github.com/samaswin87/pg_triggers_example).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'pg_sql_triggers'
```

And then execute:

```bash
$ bundle install
```

Run the installer:

```bash
$ rails generate pg_sql_triggers:install
$ rails db:migrate
```

This will:
1. Create an initializer at `config/initializers/pg_sql_triggers.rb`
2. Create migrations for registry table
3. Mount the engine at `/pg_sql_triggers`

## Usage

### 1. Declaring Triggers

Create trigger definitions using the Ruby DSL:

```ruby
# app/triggers/users_email_validation.rb
PgSqlTriggers::DSL.pg_sql_trigger "users_email_validation" do
  table :users
  on :insert, :update
  function :validate_user_email

  version 1
  enabled false

  when_env :production
end
```

### 2. Trigger Migrations

Generate and run trigger migrations similar to Rails schema migrations:

```bash
# Generate a new trigger migration
rails generate trigger:migration add_validation_trigger

# Run pending trigger migrations
rake trigger:migrate

# Rollback last trigger migration
rake trigger:rollback

# Rollback multiple steps
rake trigger:rollback STEP=3

# Check migration status
rake trigger:migrate:status

# Run a specific migration up
rake trigger:migrate:up VERSION=20231215120000

# Run a specific migration down
rake trigger:migrate:down VERSION=20231215120000

# Redo last migration
rake trigger:migrate:redo
```

**Web UI Migration Management:**

You can also manage migrations directly from the web dashboard:

- **Apply All Pending Migrations**: Click the "Apply All Pending Migrations" button to run all pending migrations at once
- **Rollback Last Migration**: Use the "Rollback Last Migration" button to undo the most recent migration
- **Redo Last Migration**: Click "Redo Last Migration" to rollback and re-apply the last migration
- **Individual Migration Actions**: Each migration in the status table has individual "Up", "Down", or "Redo" buttons for granular control

All migration actions include confirmation dialogs and provide feedback via flash messages.

Trigger migrations are stored in `db/triggers/` and follow the same naming convention as Rails migrations (`YYYYMMDDHHMMSS_name.rb`).

Example trigger migration:

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

### 3. Combined Schema and Trigger Migrations

Run both schema and trigger migrations together:

```bash
# Run both schema and trigger migrations
rake db:migrate:with_triggers

# Rollback both (rolls back the most recent migration)
rake db:rollback:with_triggers

# Check status of both
rake db:migrate:status:with_triggers

# Get versions of both
rake db:version:with_triggers
```

### 4. Console Introspection

Access trigger information from the Rails console:

```ruby
# List all triggers
PgSqlTriggers::Registry.list

# List enabled triggers
PgSqlTriggers::Registry.enabled

# List disabled triggers
PgSqlTriggers::Registry.disabled

# Get triggers for a specific table
PgSqlTriggers::Registry.for_table(:users)

# Check for drift
PgSqlTriggers::Registry.diff

# Validate all triggers
PgSqlTriggers::Registry.validate!
```

### 5. Web UI

Access the web UI at `http://localhost:3000/pg_sql_triggers` to:

- View all triggers and their status
- Enable/disable triggers
- View drift states
- Execute SQL capsules
- Manage trigger lifecycle
- **Run trigger migrations** (up/down/redo) directly from the dashboard
  - Apply all pending migrations with a single click
  - Rollback the last migration
  - Redo the last migration
  - Individual migration controls for each migration in the status table

<img width="3360" height="2506" alt="screencapture-localhost-3000-pg-triggers-2025-12-27-17_04_29" src="https://github.com/user-attachments/assets/a7f5904b-1172-41fc-ba3f-c05587cb1fe8" />

<img width="3360" height="3420" alt="screencapture-localhost-3000-pg-triggers-generator-new-2025-12-27-17_04_49" src="https://github.com/user-attachments/assets/fc9e53f2-f540-489d-8e41-6075dab8d731" />


### 6. Permissions

PgSqlTriggers supports three permission levels:

- **Viewer**: Read-only access (view triggers, diffs)
- **Operator**: Can enable/disable triggers, apply generated triggers
- **Admin**: Full access including dropping triggers and executing SQL

Configure custom permission checking:

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  config.permission_checker = ->(actor, action, environment) {
    # Your custom permission logic
    user = User.find(actor[:id])
    user.has_permission?(action)
  }
end
```

### 7. Drift Detection

PgSqlTriggers automatically detects drift between your DSL definitions and the actual database state:

- **Managed & In Sync**: Trigger matches DSL definition
- **Managed & Drifted**: Trigger exists but doesn't match DSL
- **Manual Override**: Trigger was modified outside of PgSqlTriggers
- **Disabled**: Trigger is disabled
- **Dropped**: Trigger was dropped but still in registry
- **Unknown**: Trigger exists in DB but not in registry

### 8. Production Kill Switch

By default, PgSqlTriggers blocks destructive operations in production:

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  # Enable production kill switch (default: true)
  config.kill_switch_enabled = true
end
```

Override for specific operations:

```ruby
PgSqlTriggers::SQL.override_kill_switch do
  # Dangerous operation here
end
```

## Configuration

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  # Kill switch for production (default: true)
  config.kill_switch_enabled = true

  # Environment detection (default: -> { Rails.env })
  config.default_environment = -> { Rails.env }

  # Custom permission checker
  config.permission_checker = ->(actor, action, environment) {
    # Return true/false based on your authorization logic
    true
  }
end
```

## Core Principles

- **Rails-native**: Works seamlessly with Rails conventions
- **Explicit over magic**: No automatic execution
- **Safe by default**: Requires explicit confirmation for destructive actions
- **Power with guardrails**: Emergency SQL escape hatches with safety checks

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/samaswin87/pg_sql_triggers.
