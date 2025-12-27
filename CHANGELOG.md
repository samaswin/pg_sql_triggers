# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-27

### Added
- Initial gem structure
- PostgreSQL trigger DSL for defining triggers with version and environment support
- Trigger registry system for tracking trigger metadata (trigger_name, table_name, version, enabled, checksum, source, environment)
- Drift detection between DSL definitions and database state (Managed & In Sync, Managed & Drifted, Manual Override, Disabled, Dropped, Unknown)
- Permission system with three levels (Viewer, Operator, Admin)
- Mountable Rails Engine with web UI for trigger management
- Production kill switch for safety (blocks destructive operations in production by default)
- Console introspection APIs (list, enabled, disabled, for_table, diff, validate!)
- Migration system for registry table
- Install generator (`rails generate pg_triggers:install`)
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
- Permission system enforces role-based access control (Viewer, Operator, Admin)
