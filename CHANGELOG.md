# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2025-12-28

- Production kill switch for safety (blocks destructive operations in production by default)
  - Core kill switch module with environment detection, confirmation validation, and thread-safe overrides
  - CLI integration: All rake tasks protected (`trigger:migrate`, `trigger:rollback`, `trigger:migrate:up`, `trigger:migrate:down`, `trigger:migrate:redo`, `db:migrate:with_triggers`, `db:rollback:with_triggers`, `db:migrate:up:with_triggers`, `db:migrate:down:with_triggers`, `db:migrate:redo:with_triggers`)
  - Console integration: Kill switch checks in `TriggerRegistry#enable!`, `TriggerRegistry#disable!`, `Migrator.run_up`, and `Migrator.run_down` methods
  - UI integration: Kill switch enforcement in `MigrationsController` (up/down/redo actions) and `GeneratorController#create` action
  - Configuration options: `kill_switch_enabled`, `kill_switch_environments`, `kill_switch_confirmation_required`, `kill_switch_confirmation_pattern`, `kill_switch_logger`
  - ENV variable override support: `KILL_SWITCH_OVERRIDE` and `CONFIRMATION_TEXT` for emergency overrides
  - Comprehensive logging and audit trail for all operations
  - Confirmation modal UI component with client-side and server-side validation
  - Kill switch status indicator in web UI
  
### Fixed
- Added missing `mattr_accessor` declarations for kill switch configuration attributes (`kill_switch_environments`, `kill_switch_confirmation_required`, `kill_switch_confirmation_pattern`, `kill_switch_logger`) to ensure proper configuration access

## [1.0.0] - 2025-12-27

### Added
- Initial gem structure
- PostgreSQL trigger DSL for defining triggers with version and environment support
- Trigger registry system for tracking trigger metadata (trigger_name, table_name, version, enabled, checksum, source, environment)
- Drift detection between DSL definitions and database state (Managed & In Sync, Managed & Drifted, Manual Override, Disabled, Dropped, Unknown)
- Permission system with three levels (Viewer, Operator, Admin)
- Mountable Rails Engine with web UI for trigger management
- Console introspection APIs (list, enabled, disabled, for_table, diff, validate!)
- Migration system for registry table
- Install generator (`rails generate pg_sql_triggers:install`)
- Trigger migration system similar to Rails schema migrations
  - Generate trigger migrations
  - Run pending migrations (`rake trigger:migrate`)
  - Rollback migrations (`rake trigger:rollback`)
  - Migration status and individual migration controls
- Combined schema and trigger migration tasks (`rake db:migrate:with_triggers`)
- Web UI for trigger migrations (up/down/redo)
  - Apply all pending migrations from dashboard
  - Rollback last migration
  - Redo last migration
  - Individual migration actions (up/down/redo) for each migration
  - Flash messages for success, error, warning, and info states
- Database introspection for trigger state detection
- SQL execution support with safety checks
- Trigger generator with form and service layer
- Testing utilities for safe execution and syntax validation

### Changed
- Initial release

### Deprecated
- Nothing yet

### Removed
- Nothing yet

### Fixed
- Initial release

### Security
- Production kill switch prevents destructive operations in production environments
  - Blocks all destructive operations (migrations, trigger enable/disable) in production and staging by default
  - Requires explicit confirmation text matching operation-specific patterns
  - Thread-safe override mechanism for programmatic control
  - ENV variable override support for emergency scenarios (`KILL_SWITCH_OVERRIDE`)
  - Comprehensive logging of all kill switch checks and overrides
  - Protection enforced across CLI (rake tasks), UI (controller actions), and Console (model/migrator methods)
- Permission system enforces role-based access control (Viewer, Operator, Admin)
