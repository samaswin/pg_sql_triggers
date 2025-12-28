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

## Quick Start

### Installation

```ruby
# Gemfile
gem 'pg_sql_triggers'
```

```bash
bundle install
rails generate pg_sql_triggers:install
rails db:migrate
```

### Define a Trigger

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

### Create and Run Migration

```bash
rails generate trigger:migration add_email_validation
rake trigger:migrate
```

### Access the Web UI

Navigate to `http://localhost:3000/pg_sql_triggers` to manage triggers visually.

## Screenshots

### Dashboard
<img width="3360" height="2506" alt="Dashboard" src="https://github.com/user-attachments/assets/a7f5904b-1172-41fc-ba3f-c05587cb1fe8" />

### Trigger Generator
<img width="3360" height="3420" alt="Generator" src="https://github.com/user-attachments/assets/fc9e53f2-f540-489d-8e41-6075dab8d731" />

## Documentation

Comprehensive documentation is available in the [docs](docs/) directory:

- **[Getting Started](docs/getting-started.md)** - Installation and basic setup
- **[Usage Guide](docs/usage-guide.md)** - DSL syntax, migrations, and drift detection
- **[Web UI](docs/web-ui.md)** - Using the web dashboard
- **[Kill Switch](docs/kill-switch.md)** - Production safety features
- **[Configuration](docs/configuration.md)** - Complete configuration reference
- **[API Reference](docs/api-reference.md)** - Console API and programmatic access

## Key Features

### Trigger DSL
Define triggers using a Rails-native Ruby DSL with versioning and environment control.

### Migration System
Manage trigger functions and definitions with a migration system similar to Rails schema migrations.

### Drift Detection
Automatically detect when database triggers drift from your DSL definitions.

### Production Kill Switch
Multi-layered safety mechanism preventing accidental destructive operations in production environments.

### Web Dashboard
Visual interface for managing triggers, running migrations, and executing SQL capsules.

### Permissions
Three-tier permission system (Viewer, Operator, Admin) with customizable authorization.

## Examples

For working examples and complete demonstrations, check out the [example repository](https://github.com/samaswin87/pg_triggers_example).

## Core Principles

- **Rails-native**: Works seamlessly with Rails conventions
- **Explicit over magic**: No automatic execution
- **Safe by default**: Requires explicit confirmation for destructive actions
- **Power with guardrails**: Emergency SQL escape hatches with safety checks

## Development

After checking out the repo, run `bin/setup` to install dependencies. Run `rake spec` to run tests. Run `bin/console` for an interactive prompt.

To install this gem locally, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/samaswin87/pg_sql_triggers.

## License

See [LICENSE](LICENSE) file for details.
