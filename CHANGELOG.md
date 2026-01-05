# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-01-05

### Added
- **Enhanced Console API**: Added missing drift query methods to Registry API for consistency
  - `PgSqlTriggers::Registry.drifted` - Returns all drifted triggers
  - `PgSqlTriggers::Registry.in_sync` - Returns all in-sync triggers
  - `PgSqlTriggers::Registry.unknown_triggers` - Returns all unknown (external) triggers
  - `PgSqlTriggers::Registry.dropped` - Returns all dropped triggers
  - All console APIs now follow consistent naming conventions (query methods vs action methods)

- **Controller Concerns**: Extracted common controller functionality into reusable concerns
  - `KillSwitchProtection` concern - Handles kill switch checking and confirmation helpers
  - `PermissionChecking` concern - Handles permission checks and actor management
  - `ErrorHandling` concern - Handles error formatting and flash message helpers
  - All controllers now inherit from `ApplicationController` which includes these concerns
  - Improved code organization and maintainability

- **YARD Documentation**: Comprehensive YARD documentation added to all public APIs
  - `PgSqlTriggers::Registry` module - All public methods fully documented
  - `PgSqlTriggers::TriggerRegistry` model - All public methods fully documented
  - `PgSqlTriggers::Generator::Service` - All public class methods fully documented
  - `PgSqlTriggers::SQL::Executor` - Already had documentation (verified)
  - All documentation includes parameter types, return values, and examples

### Added
- **Complete UI Action Buttons**: All trigger operations now accessible via web UI
  - Enable/Disable buttons in dashboard and table detail views
  - Drop trigger button with confirmation modal (Admin permission required)
  - Re-execute trigger button with drift diff display (Admin permission required)
  - All buttons respect permission checks and show/hide based on user role
  - Kill switch integration with confirmation modals for all actions
  - Buttons styled with environment-aware colors (warning colors for production)

- **Enhanced Dashboard**:
  - "Last Applied" column showing `installed_at` timestamps in human-readable format
  - Tooltips with exact timestamps on hover
  - Default sorting by `installed_at` (most recent first)
  - Drop and Re-execute buttons in dashboard table (Admin only)
  - Permission-aware button visibility throughout

- **Trigger Detail Page Enhancements**:
  - Breadcrumb navigation (Dashboard → Tables → Table → Trigger)
  - Enhanced `installed_at` display with relative time formatting
  - `last_verified_at` timestamp display
  - All action buttons (enable/disable/drop/re-execute) accessible from detail page

- **Comprehensive Audit Logging System**:
  - New `pg_sql_triggers_audit_log` table for tracking all operations
  - `AuditLog` model with logging methods (`log_success`, `log_failure`)
  - Audit logging integrated into all trigger operations:
    - `enable!` - logs success/failure with before/after state
    - `disable!` - logs success/failure with before/after state  
    - `drop!` - logs success/failure with reason and state changes
    - `re_execute!` - logs success/failure with drift diff information
  - All operations track actor (who performed the action)
  - Complete state capture (before/after) for all operations
  - Error messages logged for failed operations
  - Environment and confirmation text tracking

- **Enhanced Actor Tracking**:
  - All trigger operations now accept `actor` parameter
  - Console APIs updated to pass actor information
  - UI controllers pass `current_actor` to all operations
  - Actor information stored in audit logs for complete audit trail

- **Permissions Enforcement System**:
  - Permission checks enforced across all controllers (Viewer, Operator, Admin)
  - `PermissionsHelper` module for view-level permission checks
  - Permission helper methods in `ApplicationController` for consistent authorization
  - All UI buttons and actions respect permission levels
  - Console APIs (`Registry.enable/disable/drop/re_execute`, `SQL::Executor.execute`) check permissions
  - Permission errors raise `PermissionError` with clear messages
  - Configurable permission checker via `permission_checker` configuration option

- **Enhanced Error Handling System**:
  - Comprehensive error hierarchy with base `Error` class and specialized error types
  - Error classes: `PermissionError`, `KillSwitchError`, `DriftError`, `ValidationError`, `ExecutionError`, `UnsafeMigrationError`, `NotFoundError`
  - Error codes for programmatic handling (e.g., `PERMISSION_DENIED`, `KILL_SWITCH_ACTIVE`, `DRIFT_DETECTED`)
  - Standardized error messages with recovery suggestions
  - Enhanced error display in UI with user-friendly formatting
  - Context information included in all errors for better debugging
  - Error handling helpers in `ApplicationController` for consistent error formatting

- **Comprehensive Documentation**:
  - New `ui-guide.md` - Quick start guide for web interface
  - New `permissions.md` - Complete guide to configuring and using permissions
  - New `audit-trail.md` - Guide to viewing and exporting audit logs
  - New `troubleshooting.md` - Common issues and solutions with error code reference
  - Updated documentation index with links to all new guides

- **Audit Log UI**:
  - Web interface for viewing audit log entries (`/audit_logs`)
  - Filterable by trigger name, operation, status, and environment
  - Sortable by date (ascending/descending)
  - Pagination support (default 50 entries per page, max 200)
  - CSV export functionality with applied filters
  - Comprehensive view showing operation details, actor information, status, and error messages
  - Links to trigger detail pages from audit log entries
  - Navigation menu integration

- **Enhanced Database Tables & Triggers Page**:
  - Pagination support for tables list (default 20 per page, configurable up to 100)
  - Filter functionality to view:
    - All tables
    - Tables with triggers only
    - Tables without triggers only
  - Enhanced statistics dashboard showing:
    - Count of tables with triggers
    - Count of tables without triggers
    - Total tables count
  - Filter controls with visual indicators for active filter
  - Pagination controls preserve filter selection when navigating pages
  - Context-aware empty state messages based on selected filter

### Changed
- **Code Organization**: Refactored `ApplicationController` to use concerns instead of inline methods
  - Reduced code duplication across controllers
  - Improved separation of concerns
  - Better testability and maintainability

- **Service Object Patterns**: Standardized service object patterns across all service classes
  - All service objects follow consistent class method patterns
  - Consistent stateless service object conventions

- **Goal.md**: Updated to reflect actual implementation status
  - Added technical notes documenting improvements
  - Updated console API section with all implemented methods
  - Documented code organization improvements

- Dashboard default sorting changed to `installed_at` (most recent first) instead of `created_at`
- Trigger detail page breadcrumbs improved navigation flow
- All trigger action buttons use consistent styling and permission checks

### Fixed
- Actor tracking now properly passed through all operation methods
- Improved error handling with audit log integration

### Security
- All operations now tracked in audit log for compliance and debugging
- Actor information captured for all operations (UI, Console, CLI)
- Complete state change tracking for audit trail
- Permission enforcement ensures only authorized users can perform operations
- Permission checks enforced at controller, API, and view levels

## [1.2.0] - 2026-01-02

### Added
- **SQL Capsules**: Emergency SQL execution feature for critical operations
  - Named SQL capsules with environment declaration and purpose description
  - Capsule class for creating and managing SQL capsules
  - Executor class for safe, transactional SQL execution
  - Permission checks (Admin role required for execution)
  - Kill switch protection for all executions
  - Checksum calculation and storage in registry
  - Comprehensive logging of all operations
  - Web UI for creating, viewing, and executing SQL capsules
  - Console API: `PgSqlTriggers::SQL::Executor.execute(capsule, actor:, confirmation:)`

- **Drop & Re-Execute Flow**: Operational controls for trigger lifecycle management
  - `TriggerRegistry#drop!` method for safely dropping triggers
    - Admin permission required
    - Kill switch protection
    - Reason field (required and logged)
    - Typed confirmation required in protected environments
    - Transactional execution
    - Removes trigger from database and registry
  - `TriggerRegistry#re_execute!` method for fixing drifted triggers
    - Admin permission required
    - Kill switch protection
    - Shows drift diff before execution
    - Reason field (required and logged)
    - Typed confirmation required in protected environments
    - Transactional execution
    - Drops and re-creates trigger from registry definition
  - Web UI buttons for drop and re-execute on trigger detail page
  - Controller actions with proper permission checks and error handling
  - Interactive modals with reason input and confirmation fields
  - Drift comparison shown before re-execution

- **Enhanced Permissions Enforcement**:
  - Console APIs with permission checks:
    - `PgSqlTriggers::Registry.enable(trigger_name, actor:, confirmation:)`
    - `PgSqlTriggers::Registry.disable(trigger_name, actor:, confirmation:)`
    - `PgSqlTriggers::Registry.drop(trigger_name, actor:, reason:, confirmation:)`
    - `PgSqlTriggers::Registry.re_execute(trigger_name, actor:, reason:, confirmation:)`
  - Permission checks enforced at console API level
  - Rake tasks already protected by kill switch
  - Clear error messages for permission violations

### Fixed
- Improved error handling for trigger enable/disable operations
- Better logging for drop and re-execute operations
- Fixed rubocop linting issues

### Security
- All destructive operations (drop, re-execute, SQL capsule execution) require Admin permissions
- Kill switch protection enforced across all new features
- Typed confirmation required in protected environments
- Comprehensive audit logging for all operations

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
