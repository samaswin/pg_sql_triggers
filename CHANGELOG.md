# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2025-12-31

### Changed
- Updated git username in repository metadata

## [1.1.0] - 2025-12-29

### Added
- Trigger timing support (BEFORE/AFTER) in generator and registry
  - Added `timing` field to generator form with "before" and "after" options
  - Added `timing` column to `pg_sql_triggers_registry` table (defaults to "before")
  - Timing is now included in DSL generation, migration generation, and registry storage
  - Timing is included in checksum calculation for drift detection
  - Preview page now displays trigger timing and condition information
  - Comprehensive test coverage for both "before" and "after" timing scenarios
- Enhanced preview page UI for better testing and editing
  - Timing and condition fields are now editable directly in the preview page
  - Real-time DSL preview updates when timing or condition changes
  - Improved visual layout with clear distinction between editable and read-only fields
  - Better user experience for testing different timing and condition combinations before generating files
  - JavaScript-powered dynamic preview that updates automatically as you type

### Performance
- Optimized `Registry::Manager.register` to prevent N+1 queries when loading multiple trigger files
  - Added request-level caching for registry lookups to avoid redundant database queries
  - Added `preload_triggers` method for batch loading triggers into cache
  - Cache is automatically populated during registration and can be manually cleared
  - Significantly reduces database queries when multiple trigger files are loaded during request processing

### Added
- Safety validation for trigger migrations (prevents unsafe DROP + CREATE operations)
  - `Migrator::SafetyValidator` class that detects unsafe DROP + CREATE patterns in migrations
  - Blocks migrations that would drop existing database objects (triggers/functions) and recreate them without validation
  - Only flags as unsafe if the object actually exists in the database
  - Configuration option `allow_unsafe_migrations` (default: false) for global override
  - Environment variable `ALLOW_UNSAFE_MIGRATIONS=true` for per-migration override
  - Provides clear error messages explaining unsafe operations and how to proceed if override is needed
  - New error class `PgSqlTriggers::UnsafeMigrationError` for safety validation failures
- Pre-apply comparison for trigger migrations (diff expected vs actual)
  - `Migrator::PreApplyComparator` class that extracts expected SQL from migrations and compares with database state
  - `Migrator::PreApplyDiffReporter` class for formatting comparison results into human-readable diff reports
  - Automatic pre-apply comparison before executing migrations to show what will change
  - Comparison reports show new objects (will be created), modified objects (will be overwritten), and unchanged objects
  - Detailed diff output for functions and triggers including expected vs actual SQL
  - Summary output in verbose mode or when called from console
  - Non-blocking: shows differences but doesn't prevent migration execution (warns only)
- Complete drift detection system implementation
  - `Drift::Detector` class with all 6 drift states (IN_SYNC, DRIFTED, DISABLED, DROPPED, UNKNOWN, MANUAL_OVERRIDE)
  - `Drift::Reporter` class for formatting drift reports and summaries
  - `Drift::DbQueries` helper module for PostgreSQL system catalog queries
  - Dashboard integration: drift count now calculated from actual detection results
  - Console API: `PgSqlTriggers::Registry.diff` now fully functional with drift detection
  - Comprehensive test coverage for all drift detection components (>90% coverage)

### Added
- Comprehensive test coverage for generator components (>90% coverage)
  - Added extensive test cases for `Generator::Service` covering all edge cases:
    - Function name quoting (special characters vs simple patterns)
    - Multiple environments handling
    - Condition escaping with quotes
    - Single and multiple event combinations
    - All event types (insert, update, delete, truncate)
    - Blank events and environments filtering
    - Migration number generation edge cases (no existing migrations, timestamp collisions, multiple migrations)
    - Standalone gem context (without Rails)
    - Error handling and logging
    - Checksum calculation with nil values
  - Added test coverage for generator classes:
    - `TriggerMigrationGenerator` - migration number generation, file naming, template usage
    - `MigrationGenerator` (Trigger::Generators) - migration number generation, file naming, class name generation
    - `InstallGenerator` - initializer creation, migration copying, route mounting, readme display

### Fixed
- Fixed form data persistence when navigating between preview and edit pages
  - Form data (including edits to condition, timing, and function_body) is now preserved when clicking "Back to Edit" from preview page
  - Implemented session-based storage to maintain form state across page navigation
  - All form fields are restored when returning to edit page: trigger_name, table_name, function_name, function_body, events, version, enabled, timing, condition, and environments
  - Session data is automatically cleared after successful trigger creation
  - Comprehensive test coverage added for session persistence functionality
- Fixed checksum calculation consistency across all code paths (field-concatenation algorithm)
- Fixed `Registry::Manager.diff` method to use drift detection
- Fixed dashboard controller to display actual drifted trigger count
- Fixed SQL parameter handling in `DbQueries.execute_query` method
- Fixed generator service to properly handle function body whitespace stripping
- Fixed generator service to handle standalone gem context (without Rails.root)

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
- Fixed debug info display issues
- Fixed README documentation formatting
- Fixed Rails 6.1 compatibility issues
- Fixed BigDecimal dependency issues
- Fixed gemlock file conflicts
- Fixed RuboCop linting issues
- Fixed spec test issues

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
