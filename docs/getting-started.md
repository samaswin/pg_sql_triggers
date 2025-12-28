# Getting Started with PgSqlTriggers

This guide will help you install and set up PgSqlTriggers in your Rails application.

## Installation

### 1. Add the Gem

Add this line to your application's Gemfile:

```ruby
gem 'pg_sql_triggers'
```

### 2. Install Dependencies

Execute the bundle command:

```bash
bundle install
```

### 3. Run the Installer

Run the installation generator:

```bash
rails generate pg_sql_triggers:install
rails db:migrate
```

This will:
1. Create an initializer at `config/initializers/pg_sql_triggers.rb`
2. Create migrations for the registry table
3. Mount the engine at `/pg_sql_triggers`

## Verify Installation

After installation, you should have:

- **Initializer**: `config/initializers/pg_sql_triggers.rb` with default configuration
- **Registry Table**: `pg_sql_triggers_registry` table in your database
- **Web UI**: Accessible at `http://localhost:3000/pg_sql_triggers`
- **Trigger Directory**: `db/triggers/` for storing trigger migrations

## Quick Start Example

### 1. Create Your First Trigger Definition

Create a trigger definition file:

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

### 2. Generate a Migration

Create a trigger migration to implement the function:

```bash
rails generate trigger:migration add_email_validation
```

Edit the generated migration in `db/triggers/`:

```ruby
# db/triggers/YYYYMMDDHHMMSS_add_email_validation.rb
class AddEmailValidation < PgSqlTriggers::Migration
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

### 3. Run the Migration

Apply the trigger migration:

```bash
rake trigger:migrate
```

### 4. Access the Web UI

Open your browser and navigate to:

```
http://localhost:3000/pg_sql_triggers
```

You should see your trigger listed in the dashboard.

## Next Steps

- [Usage Guide](usage-guide.md) - Learn about the DSL and migration system
- [Web UI Documentation](web-ui.md) - Explore the web dashboard features
- [Kill Switch](kill-switch.md) - Understand production safety features
- [Configuration](configuration.md) - Configure advanced settings
- [API Reference](api-reference.md) - Console commands and programmatic access

## Examples Repository

For working examples and a complete demonstration of PgSqlTriggers in action, check out the [example repository](https://github.com/samaswin87/pg_triggers_example).
