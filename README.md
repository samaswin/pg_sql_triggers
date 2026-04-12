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

## Requirements

- **Ruby 3.0+**
- **Rails 6.1+**
- **PostgreSQL** (any supported version)

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

Schema migrations bundled with the gem are listed in [Getting Started — Gem schema migrations](docs/getting-started.md#gem-schema-migrations) (ordered `db/migrate/*.rb` filenames).

### Define a Trigger

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

### Generate and Run Migration

```bash
# Generate a DSL stub + migration in one command
rails generate pg_sql_triggers:trigger users_email_validation users insert update --timing before --function validate_user_email

rake trigger:migrate
```

### Access the Web UI

Navigate to `http://localhost:3000/pg_sql_triggers` to manage triggers visually.

Screenshots are available in the [docs/screenshots](docs/screenshots/) directory.

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
Define triggers using a Rails-native Ruby DSL with versioning, row/statement-level granularity, and timing control.

### CLI Generator
Scaffold a DSL stub and migration in one command:
```bash
rails generate pg_sql_triggers:trigger TRIGGER_NAME TABLE_NAME [EVENTS...] [--timing before|after] [--function fn_name]
```
Files land in `app/triggers/` and `db/triggers/` for code review like any other source change.

### Migration System
Manage trigger functions and definitions with a migration system similar to Rails schema migrations.

### schema.rb, structure.sql, and trigger snapshots

`db:schema:dump` does not capture PostgreSQL triggers. This gem addresses that in three ways:

1. **Comments in `schema.rb`** — When using the default Ruby schema format, `rails db:schema:dump` appends a short note listing managed triggers and pointing to `trigger:migrate` / `trigger:load`. Disable with `PgSqlTriggers.append_trigger_notes_to_schema_dump = false`.
2. **`db/trigger_structure.sql`** — Run `rails trigger:dump` to write `CREATE FUNCTION` / `CREATE TRIGGER` statements for registered triggers (or all non-internal triggers in `public` if the registry table is absent). Apply on a fresh DB with `rails trigger:load` (runs arbitrary SQL; kill switch applies in protected environments). Override the path with `FILE=...` or `TRIGGER_STRUCTURE_SQL=...`, or set `PgSqlTriggers.trigger_structure_sql_path`.
3. **`db:schema:load`** — After loading `schema.rb`, `trigger:migrate` runs automatically so pending trigger migrations apply. Opt out with `SKIP_TRIGGER_MIGRATE_AFTER_SCHEMA_LOAD=1` or `PgSqlTriggers.migrate_triggers_after_schema_load = false`.

For a single SQL artifact that includes tables and triggers, set `config.active_record.schema_format = :sql` and use Rails’ `structure.sql` workflow; keep `db/triggers` migrations as the source of truth and refresh `db/trigger_structure.sql` when you want a portable trigger-only snapshot.

### Drift Detection
Automatically detect when database triggers drift from your DSL definitions. N+1-free bulk detection across all triggers.

### Production Kill Switch
Multi-layered safety mechanism preventing accidental destructive operations in production environments.

### Web Dashboard
Visual interface for managing triggers and running migrations. Includes:
- **Quick Actions**: Enable/disable, drop, and re-execute triggers from dashboard
- **Last Applied Tracking**: See when triggers were last applied with human-readable timestamps
- **Breadcrumb Navigation**: Easy navigation between dashboard, tables, and triggers
- **Permission-Aware UI**: Buttons show/hide based on user role

### Audit Logging
Comprehensive audit trail for all trigger operations:
- Track who performed each operation (actor tracking)
- Before and after state capture (including function body)
- Success/failure logging with error messages
- Reason tracking for drop and re-execute operations

### Drop & Re-Execute Flow
Operational controls for trigger lifecycle management with drop and re-execute capabilities, drift comparison, and required reason logging.

### Permissions
Three-tier permission system (Viewer, Operator, Admin) with customizable authorization. A startup warning is emitted in production when no `permission_checker` is configured.

## Console API

PgSqlTriggers provides a comprehensive console API for managing triggers programmatically:

```ruby
# Query triggers
triggers = PgSqlTriggers::Registry.list
enabled = PgSqlTriggers::Registry.enabled
disabled = PgSqlTriggers::Registry.disabled
user_triggers = PgSqlTriggers::Registry.for_table(:users)

# Check drift status
drift_info = PgSqlTriggers::Registry.diff
drifted = PgSqlTriggers::Registry.drifted
in_sync = PgSqlTriggers::Registry.in_sync
unknown = PgSqlTriggers::Registry.unknown_triggers
dropped = PgSqlTriggers::Registry.dropped

# Enable/disable triggers
PgSqlTriggers::Registry.enable("users_email_validation", actor: current_user, confirmation: "EXECUTE TRIGGER_ENABLE")
PgSqlTriggers::Registry.disable("users_email_validation", actor: current_user, confirmation: "EXECUTE TRIGGER_DISABLE")

# Drop and re-execute triggers
PgSqlTriggers::Registry.drop("old_trigger", actor: current_user, reason: "No longer needed", confirmation: "EXECUTE TRIGGER_DROP")
PgSqlTriggers::Registry.re_execute("drifted_trigger", actor: current_user, reason: "Fix drift", confirmation: "EXECUTE TRIGGER_RE_EXECUTE")
```

See the [API Reference](docs/api-reference.md) for complete documentation of all console APIs.

## Examples

For working examples and complete demonstrations, check out the [example repository](https://github.com/samaswin/pg_triggers_example).

## Core Principles

- **Rails-native**: Works seamlessly with Rails conventions
- **Explicit over magic**: No automatic execution
- **Safe by default**: Requires explicit confirmation for destructive actions
- **Code review first**: Generator produces files into working tree; no server-side file writes

## Development

After checking out the repo, run `bin/setup` to install dependencies. Run `rake spec` to run tests. Run `bin/console` for an interactive prompt.

To install this gem locally, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and run `bundle exec rake release`.

## Test Coverage

See [COVERAGE.md](COVERAGE.md) for detailed coverage information.

**Total Coverage: 84.97%**

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/samaswin/pg_sql_triggers.

## License

See [LICENSE](LICENSE) file for details.
