# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Drift alerting** — Configurable `PgSqlTriggers.drift_notifier` for external notification when
  drift detection finds drifted, dropped, or unknown triggers; `PgSqlTriggers::Alerting` module;
  `PgSqlTriggers::Drift.check_and_notify`; Rake task `trigger:check_drift` with optional
  `FAIL_ON_DRIFT=1`; `ActiveSupport::Notifications` event `pg_sql_triggers.drift_check`.
  The gem’s root `Rakefile` loads `rakelib/pg_sql_triggers_environment.rake` and
  `lib/tasks/trigger_migrations.rake` so `bundle exec rake trigger:*` works when developing the
  gem (not only from a host app).
  ([lib/pg_sql_triggers/alerting.rb](lib/pg_sql_triggers/alerting.rb),
  [lib/tasks/trigger_migrations.rake](lib/tasks/trigger_migrations.rake),
  [lib/pg_sql_triggers/rake_development_boot.rb](lib/pg_sql_triggers/rake_development_boot.rb),
  [docs/configuration.md](docs/configuration.md))

## [1.4.0] - 2026-03-01

### Added

- **[Feature 4.1] `FOR EACH ROW` / `FOR EACH STATEMENT` DSL support** — Every PostgreSQL trigger
  requires a row-level or statement-level execution granularity, but the gem previously hard-coded
  `FOR EACH ROW` with no way for callers to change it. Two new DSL methods, `for_each_row` and
  `for_each_statement`, let trigger definitions declare the desired granularity explicitly. The
  value defaults to `"row"` so all existing definitions continue to produce `FOR EACH ROW` triggers
  without modification. The field is stored in a new `for_each` column on the registry table
  (migration `20260228162233_add_for_each_to_pg_sql_triggers_registry.rb`), included in all three
  checksum computations (`TriggerRegistry#calculate_checksum`, `Registry::Manager#calculate_checksum`,
  and `Drift::Detector#calculate_db_checksum`), extracted from live trigger definitions via a new
  `extract_trigger_for_each` helper, and validated by `Registry::Validator` (only `"row"` and
  `"statement"` are accepted). The SQL reconstructed by `TriggerRegistry#build_trigger_sql_from_definition`
  during `re_execute!` now honours the stored `for_each` value.
  ([lib/pg_sql_triggers/dsl/trigger_definition.rb](lib/pg_sql_triggers/dsl/trigger_definition.rb),
  [lib/pg_sql_triggers/registry/manager.rb](lib/pg_sql_triggers/registry/manager.rb),
  [lib/pg_sql_triggers/registry/validator.rb](lib/pg_sql_triggers/registry/validator.rb),
  [lib/pg_sql_triggers/drift/detector.rb](lib/pg_sql_triggers/drift/detector.rb),
  [app/models/pg_sql_triggers/trigger_registry.rb](app/models/pg_sql_triggers/trigger_registry.rb),
  [db/migrate/20260228162233_add_for_each_to_pg_sql_triggers_registry.rb](db/migrate/20260228162233_add_for_each_to_pg_sql_triggers_registry.rb))

### Changed

- **[Refactor 5.1] `SQL::KillSwitch` reduced from 329 to 166 lines** — The module was inflated by
  four separate single-purpose log helpers (`log_allowed`, `log_override`, `log_blocked`,
  `format_actor`), a `raise_blocked_error` method whose two heredocs (`message` and `recovery`)
  duplicated each other across 30 lines, verbose per-method comments, and a
  `rubocop:disable Metrics/ModuleLength` suppressor. Collapsed the four log helpers into one
  private `log(level, status, op, env, actor, extra = nil)` method; inlined `raise_blocked_error`
  as a concise 5-line `raise` call; removed all comment padding; renamed `detect_environment` →
  `resolve_environment` for clarity. All three-layer semantics (config → ENV override → explicit
  confirmation), public API (`active?`, `check!`, `override`, `validate_confirmation!`), log
  message formats, and error message content are unchanged — all existing specs continue to pass.
  ([lib/pg_sql_triggers/sql/kill_switch.rb](lib/pg_sql_triggers/sql/kill_switch.rb))

- **[Design] Eliminated N+1 queries in drift detection** — `Drift::Detector.detect_all` and
  `detect_for_table` previously called `detect(trigger_name)` per registry entry, which issued a
  `TriggerRegistry.find_by` and a `DbQueries.find_trigger` DB query for every row (N+1 pattern).
  These methods now build an `index_by` hash from the bulk-fetched result of `DbQueries.all_triggers`
  and map over pre-loaded registry entries, eliminating all per-entry lookups. A new private method
  `detect_with_preloaded(registry_entry, db_trigger)` performs state computation with zero
  additional queries.
  ([lib/pg_sql_triggers/drift/detector.rb](lib/pg_sql_triggers/drift/detector.rb))

- **[Design] Thread-safe registry cache** — `Registry::Manager._registry_cache` was stored in a
  class-level instance variable mutated without synchronisation, creating a race condition on
  multi-threaded Puma servers. A `REGISTRY_CACHE_MUTEX = Mutex.new` constant now guards all reads
  and writes to `@_registry_cache` via `REGISTRY_CACHE_MUTEX.synchronize`.
  ([lib/pg_sql_triggers/registry/manager.rb](lib/pg_sql_triggers/registry/manager.rb))

- **[Design] Configurable PostgreSQL schema** — Every SQL query in `Drift::DbQueries` hard-coded
  `n.nspname = 'public'`, making the gem unusable in applications that manage triggers in
  non-public schemas. A new configuration attribute `PgSqlTriggers.db_schema` (default: `"public"`)
  replaces all hard-coded schema literals; the value is passed as a bind parameter via a private
  `schema_name` helper. Override in an initialiser:
  `PgSqlTriggers.db_schema = "app"`.
  ([lib/pg_sql_triggers.rb](lib/pg_sql_triggers.rb),
  [lib/pg_sql_triggers/drift/db_queries.rb](lib/pg_sql_triggers/drift/db_queries.rb))

- **[Design] Idiomatic DSL accessor methods** — `TriggerDefinition#version`, `#enabled`, and
  `#timing` used a dual-purpose getter/setter pattern (`def version(v = nil)`) that silently
  returned the current value when called with no argument, making typos invisible. Replaced with
  standard `attr_accessor :version, :enabled` and a custom `timing=(val)` writer that converts to
  string, matching the Ruby/Rails `attr_accessor` convention. DSL block syntax changes from
  `version 1` to `self.version = 1` and `enabled true` to `self.enabled = true`.
  ([lib/pg_sql_triggers/dsl/trigger_definition.rb](lib/pg_sql_triggers/dsl/trigger_definition.rb))

- **[Design] `capture_state` now includes `function_body`** — The audit snapshot captured by
  `TriggerRegistry#capture_state` (used in before/after diffs for all audit log entries) omitted
  `function_body`, making it impossible to see the actual function content in audit trail diffs.
  The field is now included in all captured state hashes.
  ([app/models/pg_sql_triggers/trigger_registry.rb](app/models/pg_sql_triggers/trigger_registry.rb))

- **[Design 5.4] `Migrator#run_migration` reduced from three migration instances to two** —
  `run_migration` previously instantiated the migration class three times: once for
  `SafetyValidator`, once for `PreApplyComparator`, and once for actual execution. This meant
  the migration code ran twice before execution, making the behaviour unpredictable if the
  migration had side effects that escaped the `execute` override. A new private
  `capture_migration_sql(instance, direction)` helper (wrapped in a rolled-back transaction)
  captures SQL once from a single inspection instance. `SafetyValidator.validate_sql!` and
  `PreApplyComparator.compare_sql` are new entry points that accept pre-captured SQL directly,
  avoiding a second run of the migration code. Execution still uses a fresh instance. The
  existing `validate!` and `compare` instance-based APIs are retained for backward compatibility
  with specs.
  ([lib/pg_sql_triggers/migrator.rb](lib/pg_sql_triggers/migrator.rb),
  [lib/pg_sql_triggers/migrator/safety_validator.rb](lib/pg_sql_triggers/migrator/safety_validator.rb),
  [lib/pg_sql_triggers/migrator/pre_apply_comparator.rb](lib/pg_sql_triggers/migrator/pre_apply_comparator.rb))

### Deprecated

- **`DSL::TriggerDefinition#when_env`** — Environment-specific trigger declarations cause schema
  drift between environments and make triggers impossible to test fully outside production.
  `when_env` now emits a `warn`-level deprecation message on every call and will be removed in a
  future major version. Use application-level configuration to gate trigger behaviour by
  environment instead.
  ([lib/pg_sql_triggers/dsl/trigger_definition.rb](lib/pg_sql_triggers/dsl/trigger_definition.rb))

### Removed

- **[Refactor 5.3] Web UI trigger generator removed; replaced with Rails CLI generator** —
  `GeneratorController` provided a browser form for generating trigger DSL files and migrations
  at runtime, writing files directly to the server's filesystem. This is a security and
  auditability concern in production (server-side file writes, no code review gate). The
  controller, its two views (`new`, `preview`), the `/generator` routes, `Generator::Service`,
  `Generator::Form`, and all related specs have been removed. Code generation is now a local,
  CLI-driven action via a new `pg_sql_triggers:trigger` Rails generator:
  ```
  rails generate pg_sql_triggers:trigger TRIGGER_NAME TABLE_NAME [EVENTS...] [--timing before|after] [--function fn_name]
  ```
  The generator produces `app/triggers/TRIGGER_NAME.rb` (DSL stub) and
  `db/triggers/TIMESTAMP_TRIGGER_NAME.rb` (migration with function + trigger SQL) directly into
  the working tree, where they go through version control and code review like any other source
  file. The `autoload :Generator` entry is also removed from `PgSqlTriggers`.
  ([lib/generators/pg_sql_triggers/trigger_generator.rb](lib/generators/pg_sql_triggers/trigger_generator.rb),
  [config/routes.rb](config/routes.rb))

- **[Refactor 5.2] `SQL::Capsule` and `SQL::Executor` removed** — These classes implemented a
  named-SQL-snippet execution system ("SQL capsules") for emergency operations. The feature is a
  general-purpose dangerous-SQL runner that has nothing specifically to do with trigger management;
  bundling it in this gem conflated concerns and enlarged the web UI's attack surface. Removed:
  `lib/pg_sql_triggers/sql/capsule.rb`, `lib/pg_sql_triggers/sql/executor.rb`,
  `app/controllers/pg_sql_triggers/sql_capsules_controller.rb`, the two associated views, the
  `/sql_capsules` routes, and all related specs. `SQL::KillSwitch` is retained — it continues to
  gate trigger re-execution and migration operations. The `PgSqlTriggers::SQL.execute_capsule`
  convenience method is also removed.
  ([lib/pg_sql_triggers/sql.rb](lib/pg_sql_triggers/sql.rb),
  [config/routes.rb](config/routes.rb))

- **Duplicate `trigger:migration` generator namespace** — Two generator namespaces existed for the
  same task: `rails g pg_sql_triggers:trigger_migration` and `rails g trigger:migration`. The
  `Trigger::Generators::MigrationGenerator` (`lib/generators/trigger/`) has been removed; use
  `rails g pg_sql_triggers:trigger_migration` exclusively.
  ([lib/generators/trigger/migration_generator.rb](lib/generators/trigger/migration_generator.rb))

### Security

- **[High] Production warning when no `permission_checker` is configured** — The gem's default
  behaviour is to allow all actions (including admin-level operations such as `drop_trigger`,
  `execute_sql`, and `override_drift`) when no `permission_checker` is set. A newly deployed
  application with no extra configuration silently granted every actor full admin access.
  The engine now emits a `Rails.logger.warn` at startup when the app boots in production and
  `PgSqlTriggers.permission_checker` is still `nil`, making the misconfiguration visible in
  production logs immediately on deploy.
  ([lib/pg_sql_triggers/engine.rb](lib/pg_sql_triggers/engine.rb))

- **[High] `Registry::Validator` was a no-op stub** — `Validator.validate!` returned `true`
  unconditionally, meaning malformed DSL definitions (missing `table_name`, empty or invalid
  `events`, missing `function_name`, unrecognised `timing` values) silently passed validation
  and were written to the registry. Replaced the stub with real validation: every `source: "dsl"`
  entry in the registry has its stored `definition` JSON parsed and checked against required
  fields and allowed values (`insert / update / delete / truncate` for events;
  `before / after / instead_of` for timing). All errors are collected across all triggers and
  surfaced in a single `ValidationError` listing every violation. Non-DSL entries are not
  validated. Unparseable JSON is treated as an empty definition, which itself fails validation.
  ([lib/pg_sql_triggers/registry/validator.rb](lib/pg_sql_triggers/registry/validator.rb))

### Fixed
- **[High] `enabled: false` DSL option was cosmetic — trigger still fired in PostgreSQL** —
  The `enabled` field was stored in the registry and surfaced in drift reports, but no
  `ALTER TABLE … DISABLE TRIGGER` was ever issued across three code paths, so the trigger
  continued to fire regardless of the DSL flag.

  *Gap 1 — `Registry::Manager#register`*: A new private `sync_postgresql_enabled_state` helper
  is called after every create or update that affects the `enabled` field. On **create**, the
  helper fires only when `definition.enabled` is falsy (a newly created PostgreSQL trigger is
  always enabled by default). On **update**, `enabled_changed` is captured before the `update!`
  call so the comparison is always against the old value; the sync fires only when `enabled`
  actually flipped. The helper checks `DatabaseIntrospection#trigger_exists?` before issuing
  any SQL, making it safe to call at app boot before migrations have run, and rescues any error
  with a `Rails.logger.warn` so a transient DB issue cannot crash the registration path.

  *Gap 2 — `Migrator#run_migration` (`:up`)*: `CREATE TRIGGER` always leaves the trigger
  enabled in PostgreSQL. A new private `enforce_disabled_triggers` method is called after each
  `:up` migration transaction commits; it iterates over all `TriggerRegistry.disabled` entries
  and issues `ALTER TABLE … DISABLE TRIGGER` for any that exist in the database. A per-iteration
  `rescue` ensures one failure does not block the rest.

  *Gap 3 — `TriggerRegistry#update_registry_after_re_execute`*: `re_execute!` drops and
  recreates the trigger, leaving it always enabled in PostgreSQL. The method previously also
  forced `enabled: true` into the registry `update!` call, overwriting any previously stored
  `false` value. The `enabled: true` is removed from the `update!` so the stored state is
  preserved; if `enabled` is `false`, an `ALTER TABLE … DISABLE TRIGGER` is issued immediately
  after the registry update, within the same transaction.

  Spec coverage added for all three gaps:
  - `registry_spec.rb` — four cases in a new `"with PostgreSQL enabled state sync"` context:
    create with `enabled: false` when trigger exists in DB, create when trigger not yet in DB
    (no SQL, no error), update `true → false`, and update `false → true`.
  - `trigger_registry_spec.rb` — new `"when registry entry has enabled: false"` context inside
    `#re_execute!`: verifies `enabled` is not flipped to `true` and that `DISABLE TRIGGER` SQL
    is issued after recreation.
  - `migrator_spec.rb` — new `".run_migration with enforce_disabled_triggers"` describe block:
    runs a real migration that creates a trigger, confirms `tgenabled = 'D'` in `pg_trigger`
    afterward.

  ([lib/pg_sql_triggers/registry/manager.rb](lib/pg_sql_triggers/registry/manager.rb),
  [lib/pg_sql_triggers/migrator.rb](lib/pg_sql_triggers/migrator.rb),
  [app/models/pg_sql_triggers/trigger_registry.rb](app/models/pg_sql_triggers/trigger_registry.rb),
  [spec/pg_sql_triggers/registry_spec.rb](spec/pg_sql_triggers/registry_spec.rb),
  [spec/pg_sql_triggers/trigger_registry_spec.rb](spec/pg_sql_triggers/trigger_registry_spec.rb),
  [spec/pg_sql_triggers/migrator_spec.rb](spec/pg_sql_triggers/migrator_spec.rb))

- **[Medium] `enabled` defaulted to `false` in the DSL** — Every newly declared trigger had
  `@enabled = false`, meaning triggers were silently disabled unless the author explicitly added
  `self.enabled = true`. Deployments that omitted the flag would register a disabled trigger that
  appears in the registry but never fires, with no warning. Changed the default to `true` so
  triggers are active unless explicitly disabled.
  ([lib/pg_sql_triggers/dsl/trigger_definition.rb](lib/pg_sql_triggers/dsl/trigger_definition.rb))

- **[Critical] Drift detector checksum excluded `timing` field** — `Drift::Detector#calculate_db_checksum`
  was hashing without the `timing` attribute, while `TriggerRegistry#calculate_checksum` and
  `Registry::Manager#calculate_checksum` both include it. Any trigger with a non-default timing
  value (`"after"`) permanently showed as `DRIFTED` even when fully in sync.
  ([lib/pg_sql_triggers/drift/detector.rb](lib/pg_sql_triggers/drift/detector.rb))

- **[Critical] `extract_function_body` returned the full `CREATE FUNCTION` statement** —
  `pg_get_functiondef()` returns the complete DDL including the `CREATE OR REPLACE FUNCTION`
  header and language clause. The detector was hashing that entire string while the registry
  stores only the PL/pgSQL body, so checksums never matched and every trigger appeared `DRIFTED`.
  Fixed by extracting only the content between dollar-quote delimiters (`$$` / `$function$`).
  ([lib/pg_sql_triggers/drift/detector.rb](lib/pg_sql_triggers/drift/detector.rb))

- **[Critical] DSL triggers stored `"placeholder"` as checksum causing permanent false drift** —
  `Registry::Manager#calculate_checksum` returned the literal string `"placeholder"` whenever
  `function_body` was blank (the normal case for DSL-defined triggers). The drift detector then
  computed a real SHA256 hash and compared it to `"placeholder"`, so all DSL triggers always
  appeared `DRIFTED`. Fixed by computing a real checksum using `""` for `function_body`, and
  teaching the detector to also use `""` for `function_body` when the registry source is `"dsl"`.
  ([lib/pg_sql_triggers/registry/manager.rb](lib/pg_sql_triggers/registry/manager.rb),
  [lib/pg_sql_triggers/drift/detector.rb](lib/pg_sql_triggers/drift/detector.rb))

- **[Critical] `re_execute!` always raised for DSL-defined triggers** —
  `TriggerRegistry#re_execute!` raised `StandardError` immediately when `function_body` was
  blank, which is always the case for DSL triggers (the primary use path). Added a
  `build_trigger_sql_from_definition` private helper that reconstructs a valid `CREATE TRIGGER`
  SQL statement from the stored DSL definition JSON (`function_name`, `timing`, `events`,
  `condition`). `re_execute!` now falls back to this reconstructed SQL when `function_body` is
  absent, making the method functional for DSL triggers.
  ([app/models/pg_sql_triggers/trigger_registry.rb](app/models/pg_sql_triggers/trigger_registry.rb))

- **[High] `SafetyValidator#capture_sql` executed migration side effects during capture** —
  `capture_sql` monkey-patched only the `execute` method, so any ActiveRecord migration helpers
  (`add_column`, `create_table`, etc.) called by the migration ran for real as a side effect of
  the safety check. Wrapped the migration invocation in
  `ActiveRecord::Base.transaction { …; raise ActiveRecord::Rollback }` so all schema changes
  are rolled back after SQL capture.
  ([lib/pg_sql_triggers/migrator/safety_validator.rb](lib/pg_sql_triggers/migrator/safety_validator.rb))

- **[Low] Dead `trigger_name` expression in `drop!`** — A bare `trigger_name` expression inside
  the `drop!` transaction block was a no-op whose return value was silently discarded. Removed.
  ([app/models/pg_sql_triggers/trigger_registry.rb](app/models/pg_sql_triggers/trigger_registry.rb))

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
