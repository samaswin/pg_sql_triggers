## 1. Problem Statement

Rails teams use PostgreSQL triggers for:
- data integrity
- performance
- billing logic

But triggers today are:
- managed manually
- invisible to Rails
- unsafe to deploy
- easy to drift

This gem brings triggers into the Rails ecosystem with:
- lifecycle management
- safe deploys
- versioning
- UI control
- emergency SQL escape hatches

---

## 2. Core Philosophy

- Rails-native
- Explicit over magic
- Safe by default
- Power with guardrails

This gem **manages lifecycle**, not business logic.

---

## 3. Supported Capabilities (MUST IMPLEMENT)

### A. Trigger Declaration (DSL) ✅

Developers declare triggers using Ruby DSL:

```ruby
pg_sql_trigger "users_email_validation" do
  table :users
  on :insert, :update
  function :validate_user_email

  version 3
  enabled true

  when_env :production
end
```

Rules:
- ~~DSL generates metadata, NOT raw SQL~~
- ~~Every trigger has a version~~
- ~~Triggers are environment-aware~~
- ~~Triggers can be enabled or disabled~~

---

### B. Trigger Generation ✅

The gem must generate triggers safely.

Generators create:
1. ~~Trigger DSL file~~
2. ~~Function stub (PL/pgSQL)~~
3. ~~Manifest metadata~~

Rules:
- ~~Generated triggers are **disabled by default**~~
- ~~Nothing executes automatically~~
- ~~Developers must explicitly apply~~

---

### C. Trigger Registry (Source of Truth) ✅

All triggers must be tracked in a registry table.

Registry tracks:
- ~~trigger_name~~
- ~~table_name~~
- ~~version~~
- ~~enabled~~
- ~~checksum~~ (✅ fully implemented - consistent field-concatenation algorithm)
- ~~source (dsl / generated / manual_sql)~~
- ~~environment~~
- ~~installed_at~~
- ~~last_verified_at~~

Rails must always know:
- ~~what exists~~
- ~~how it was created~~
- ✅ whether it drifted (drift detection fully implemented)

---

### D. Safe Apply & Deploy ⚠️ (partially implemented via migrations)

Applying triggers must:
- ✅ Run in a transaction (migrations run in transactions)
- ❌ Diff expected vs actual (not implemented - no pre-apply comparison)
- ⚠️ Never blindly DROP + CREATE (migrations handle this, but no explicit safety validation)
- ✅ Support rollback on failure (migration rollback exists)
- ✅ Update registry atomically (registry updated during migration execution)

**Status:** Core functionality works through migration system, but lacks explicit "safe apply" method with pre-flight checks and diff validation.

---

### E. Drift Detection ✅ (fully implemented)

System must detect:
- ✅ Missing triggers (implemented via DROPPED state)
- ✅ Version mismatch (implemented via checksum comparison)
- ✅ Function body drift (implemented via checksum comparison)
- ✅ Manual SQL overrides (implemented via MANUAL_OVERRIDE state)
- ✅ Unknown external triggers (implemented via UNKNOWN state)

Drift states:
1. ✅ Managed & In Sync (fully implemented)
2. ✅ Managed & Drifted (fully implemented)
3. ✅ Manual Override (fully implemented)
4. ✅ Disabled (fully implemented)
5. ✅ Dropped (Recorded) (fully implemented)
6. ✅ Unknown (External) (fully implemented)

---

### F. Rails Console Introspection ✅

Provide console APIs:

~~PgSqlTriggers::Registry.list~~ (note: namespace differs slightly from goal)
~~PgSqlTriggers::Registry.enabled~~
~~PgSqlTriggers::Registry.disabled~~
~~PgSqlTriggers::Registry.for_table(:users)~~
~~PgSqlTriggers::Registry.diff~~ (✅ fully working with drift detection)
~~PgSqlTriggers::Registry.validate!~~

~~No raw SQL required by users.~~

---

## 4. Free-Form SQL Execution (MANDATORY) ❌ (routes defined but no implementation)

The gem MUST support free-form SQL execution.

This is required for:
- emergency fixes
- complex migrations
- DB-owner workflows

### SQL Capsules

Free-form SQL is wrapped in **named SQL capsules**:

- ❌ Must be named (routes defined in `config/routes.rb`, no controller exists)
- ❌ Must declare environment (not implemented)
- ❌ Must declare purpose (not implemented)
- ❌ Must be applied explicitly (not implemented)

Rules:
- ❌ Runs in a transaction (not implemented)
- ❌ Checksum verified (not implemented)
- ❌ Registry updated (not implemented)
- ❌ Marked as `source = manual_sql` (not implemented)

**Status:** Routes exist for `sql_capsules#new`, `sql_capsules#create`, `sql_capsules#show`, and `sql_capsules#execute`, but no controller, views, or logic implemented. Autoload reference exists in `lib/pg_sql_triggers/sql.rb` but file does not exist.

---

## 5. Permissions Model v1 ⚠️ (structure exists, not enforced)

Three permission levels:

### Viewer
- ~~Read-only~~ (structure exists)
- ~~View triggers~~
- ~~View diffs~~

### Operator
- ~~Enable / Disable triggers~~ (structure exists)
- ~~Apply generated triggers~~
- ~~Re-execute triggers in non-prod~~
- ~~Dry-run SQL~~

### Admin
- ~~Drop triggers~~ (structure exists)
- ~~Execute free-form SQL~~
- ~~Re-execute triggers in any env~~
- ~~Override drift~~

Permissions enforced in:
- ❌ UI (not enforced)
- ❌ CLI (not enforced)
- ❌ Console (not enforced)

---

## 6. Kill Switch for Production SQL (MANDATORY) ✅

Production mutations must be gated.

### Levels:
1. ~~Global disable (default)~~ ✅ (fully implemented)
2. ~~Runtime ENV override~~ ✅ (implemented via KILL_SWITCH_OVERRIDE and CONFIRMATION_TEXT)
3. ~~Explicit confirmation text~~ ✅ (implemented with customizable patterns)
4. ❌ Optional time-window auto-lock (not implemented - optional feature)

Kill switch must:
- ~~Block UI~~ ✅ (implemented in MigrationsController and GeneratorController)
- ~~Block CLI~~ ✅ (implemented in all rake tasks)
- ~~Block console~~ ✅ (implemented in TriggerRegistry and Migrator)
- ~~Always log attempts~~ ✅ (comprehensive logging with operation, environment, actor, and status)

### Implementation Details:

**Core Module**: `lib/pg_sql_triggers/sql/kill_switch.rb`
- Thread-safe override mechanism using thread-local storage
- Configuration-driven with sensible defaults
- Operation-specific confirmation patterns
- Comprehensive logging and audit trail

**Protected Operations**:
- CLI: All trigger migration tasks (migrate, rollback, up, down, redo)
- CLI: Combined db:migrate:with_triggers tasks
- Console: TriggerRegistry#enable!, TriggerRegistry#disable!
- Console: Migrator.run_up, Migrator.run_down
- UI: Migration up/down/redo actions
- UI: Trigger generation

**Configuration**: `config/initializers/pg_sql_triggers.rb`
- kill_switch_enabled: Global enable/disable (default: true)
- kill_switch_environments: Protected environments (default: [:production, :staging])
- kill_switch_confirmation_required: Require confirmation text (default: true)
- kill_switch_confirmation_pattern: Custom confirmation pattern lambda
- kill_switch_logger: Logger for events (default: Rails.logger)

**Usage Examples**:
```bash
# CLI with confirmation
KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE TRIGGER_MIGRATE" rake trigger:migrate
```

```ruby
# Console with override block
PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE TRIGGER_ENABLE") do
  trigger.enable!
end

# Console with direct confirmation
trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
```

**Tests**: Comprehensive test suite at `spec/pg_sql_triggers/sql/kill_switch_spec.rb` covering:
- Environment detection
- Confirmation validation
- Override mechanisms (thread-local, ENV, explicit)
- Thread safety
- Logging
- Custom configuration

---

## 8. UI (Mountable Rails Engine)

UI is operational, not decorative.

### Dashboard ✅ (implemented, drift display pending)
- ✅ Trigger name
- ✅ Table
- ✅ Version
- ✅ Status (enabled/disabled)
- ✅ Source
- ⚠️ Drift state (UI shows drift count but drift detection logic not implemented)
- ✅ Environment
- ❌ Last applied (installed_at exists in registry but not displayed in dashboard)

### Trigger Detail Page ⚠️ (partial - shown in tables/show but not dedicated)
- ⚠️ Summary panel (trigger info shown in tables/show view but no dedicated detail route/page)
- ❌ SQL diff (expected vs actual comparison)
- ⚠️ Registry state (basic info shown, but not comprehensive state display)

### Actions (State-Based) ⚠️ (backend methods exist, UI actions missing)
- ⚠️ Enable (console method `TriggerRegistry#enable!` exists with kill switch protection, but no UI buttons)
- ⚠️ Disable (console method `TriggerRegistry#disable!` exists with kill switch protection, but no UI buttons)
- ❌ Drop (not implemented - no method or UI)
- ❌ Re-execute (not implemented - no method or UI)
- ❌ Execute SQL capsule (not implemented - SQL capsules not implemented)

Buttons must:
- ❌ Be permission-aware (permissions defined but not enforced in UI)
- ❌ Be env-aware (not implemented)
- ✅ Respect kill switch (kill switch fully implemented - see Section 6)

---

## 9. Drop & Re-Execute Flow (CRITICAL) ❌ (not implemented)

Re-execute must:
1. ❌ Show diff (not implemented)
2. ❌ Require reason (not implemented)
3. ❌ Require typed confirmation (not implemented)
4. ❌ Execute transactionally (not implemented)
5. ❌ Update registry (not implemented)

No silent operations allowed.

---

## 10. What This Gem Is NOT

- Not a raw SQL editor
- Not a trigger playground
- Not auto-executing
- Not unsafe
- Not magic

---

## 11. Non-Negotiable Constraints

- No silent prod changes
- No hidden state
- No bypassing registry
- No bypassing permissions

---

## 12. Final Framing (VERY IMPORTANT)

This gem must be described as:

> **A PostgreSQL Trigger Control Plane for Rails**

---

## 13. Implementation Status & Improvements Needed

### 📊 Quick Status Summary

**Fully Implemented:**
- ✅ Trigger Declaration DSL (Section 3.A)
- ✅ Trigger Generation (Section 3.B)
- ✅ Trigger Registry (Section 3.C) - with consistent field-concatenation checksum algorithm
- ✅ Drift Detection (Section 3.E) - fully implemented with all 6 drift states
- ✅ Rails Console Introspection (Section 3.F) - including working diff method
- ✅ Kill Switch for Production Safety (Section 6) - fully implemented
- ✅ Basic UI Dashboard (Section 8) - migration management, tables view, generator

**Partially Implemented:**
- ⚠️ Safe Apply & Deploy (Section 3.D) - works via migrations but lacks explicit safe apply method with pre-flight checks
- ⚠️ UI (Section 8) - dashboard and tables view exist, but no dedicated trigger detail page, no enable/disable buttons
- ⚠️ Permissions Model (Section 5) - structure exists but not enforced

**Not Implemented (Critical):**
- ❌ SQL Capsules (Section 4) - MANDATORY feature, routes exist but no implementation
- ❌ Drop & Re-Execute Flow (Section 9) - CRITICAL operational requirement

### ✅ Achieved Features

**Core Infrastructure:**
- ✅ Trigger Declaration DSL (`PgSqlTriggers::DSL.pg_sql_trigger`) - Section 3.A
- ✅ Trigger Registry model and table with all required fields - Section 3.C
- ✅ Trigger Generation (form-based wizard, DSL + migration files) - Section 3.B
- ✅ Database Introspection (tables, triggers, columns) - Supporting infrastructure
- ✅ Trigger Migrations system (rake tasks + UI) - Supporting infrastructure
- ✅ Drift Detection (all 6 states, detector, reporter, console APIs) - Section 3.E
- ✅ Rails Console Introspection APIs (`PgSqlTriggers::Registry.*`) - Section 3.F
- ✅ Enable/Disable trigger methods on TriggerRegistry model - Basic functionality
- ✅ Kill Switch for Production Safety (fully implemented) - Section 6
- ✅ Mountable Rails Engine with routes - Supporting infrastructure
- ✅ Basic UI (Dashboard, Tables view, Generator) - Section 8 (Dashboard partial)

**From Section 3.A (Trigger Declaration DSL):**
- ✅ DSL generates metadata
- ✅ Every trigger has a version
- ✅ Triggers are environment-aware
- ✅ Triggers can be enabled or disabled

**From Section 3.B (Trigger Generation):**
- ✅ Generator creates trigger DSL file
- ✅ Generator creates function stub (PL/pgSQL)
- ✅ Generator creates manifest metadata
- ✅ Generated triggers are disabled by default

**From Section 3.C (Trigger Registry):**
- ✅ Registry tracks: trigger_name, table_name, version, enabled, source, environment, installed_at, last_verified_at
- ✅ Registry tracks checksum (✅ consistent field-concatenation algorithm across all creation paths)
- ✅ Rails knows what exists and how it was created

**From Section 3.E (Drift Detection):**
- ✅ Drift::Detector class with all 6 drift states
- ✅ Drift::Reporter class for formatting drift reports
- ✅ Drift::DbQueries helper for PostgreSQL system catalog queries
- ✅ Detection of missing triggers (DROPPED state)
- ✅ Detection of version/function body drift (DRIFTED state via checksum)
- ✅ Detection of manual SQL overrides (MANUAL_OVERRIDE state)
- ✅ Detection of unknown external triggers (UNKNOWN state)
- ✅ Detection of disabled triggers (DISABLED state)
- ✅ Detection of in-sync triggers (IN_SYNC state)
- ✅ Registry convenience methods (drifted, in_sync, unknown_triggers, dropped)
- ✅ TriggerRegistry instance methods (drift_state, drift_result, drifted?, in_sync?, dropped?)
- ✅ Comprehensive test coverage for Detector and Reporter

**From Section 3.F (Rails Console Introspection):**
- ✅ `PgSqlTriggers::Registry.list` (note: namespace differs slightly from goal)
- ✅ `PgSqlTriggers::Registry.enabled`
- ✅ `PgSqlTriggers::Registry.disabled`
- ✅ `PgSqlTriggers::Registry.for_table(:users)`
- ✅ `PgSqlTriggers::Registry.validate!`
- ✅ `PgSqlTriggers::Registry.diff` (fully working with drift detection)
- ✅ `PgSqlTriggers::Registry.drifted` (returns all drifted triggers)
- ✅ `PgSqlTriggers::Registry.in_sync` (returns all in-sync triggers)
- ✅ `PgSqlTriggers::Registry.unknown_triggers` (returns all external triggers)
- ✅ `PgSqlTriggers::Registry.dropped` (returns all dropped triggers)
- ✅ No raw SQL required by users for basic operations (enable/disable via console methods)

**From Section 5 (Permissions Model):**
- ✅ Permission structure exists (Viewer, Operator, Admin roles defined)
- ✅ Permission model classes exist

**From Section 6 (Kill Switch):**
- ✅ Fully implemented - see Section 6 for details
- ✅ Global disable configuration (default: true)
- ✅ Runtime ENV override support (KILL_SWITCH_OVERRIDE)
- ✅ Explicit confirmation text requirement
- ✅ Comprehensive logging and audit trail
- ✅ UI, CLI, and Console enforcement
- ✅ Thread-safe override mechanism

**From Section 8 (UI):**
- ✅ Dashboard with: Trigger name, Table, Version, Status (enabled/disabled), Source, Environment
- ⚠️ Dashboard displays drift count (UI shows drifted stat, but drift detection logic not implemented, so will be 0 or error)
- ✅ Tables view with table listing and trigger details
- ✅ Tables/show view shows trigger info for a specific table (not a dedicated trigger detail page)
- ✅ Generator UI (form-based wizard for creating triggers)
- ✅ Migration management UI (up/down/redo with kill switch protection)
- ❌ Trigger detail page (no dedicated route/page, only shown in tables/show)

---

### 🔴 HIGH PRIORITY - Critical Missing Features

**Note:** Priorities have been adjusted based on actual implementation status. SQL Capsules (marked MANDATORY in Section 4) moved from MEDIUM to HIGH priority as it's a critical missing feature.

#### 1. SQL Capsules (MANDATORY - Section 4) - CRITICAL
**Priority:** HIGH - Mandatory feature for emergency operations

**Status:** Routes defined, but no implementation

**Missing Files:**
- ❌ `lib/pg_sql_triggers/sql/capsule.rb` - SQL capsule definition class (autoloaded but file doesn't exist)
- ❌ `lib/pg_sql_triggers/sql/executor.rb` - SQL execution with transaction, checksum, registry update
- ❌ `app/controllers/pg_sql_triggers/sql_capsules_controller.rb` - UI controller (routes reference it but it doesn't exist)
- ❌ SQL capsule views (new, show, create, execute)
- ❌ SQL capsule storage mechanism (could use registry table with `source = manual_sql`)

**Missing Functionality:**
- ❌ Named SQL capsules with environment and purpose declaration
- ❌ Explicit application workflow with confirmation
- ❌ Transactional execution
- ❌ Checksum verification
- ❌ Registry update with `source = manual_sql`
- ❌ Kill switch protection (should block in production)

**Impact:** Critical feature marked as MANDATORY in goal but completely missing. Emergency SQL execution not possible.

#### 2. Drop & Re-Execute Flow (Section 9) - CRITICAL
**Priority:** HIGH - Operational requirements

**Status:** Not implemented

**Missing:**
- ❌ Drop trigger functionality with permission checks, kill switch, reason, typed confirmation
- ❌ Re-execute functionality with diff display, reason, typed confirmation
- ❌ UI for drop/re-execute actions
- ❌ Confirmation dialogs with typed confirmation text
- ❌ Transactional execution and registry update

**Impact:** Cannot safely drop or re-execute triggers. Operational workflows blocked.

#### 3. Safe Apply & Deploy (Section 3.D) - IMPORTANT
**Priority:** MEDIUM-HIGH - Deployment safety enhancement

**Status:** Partially implemented via migrations, but lacks explicit safe apply method

**What Works:**
- ✅ Migrations run in transactions
- ✅ Migration rollback supported
- ✅ Registry updated during migrations

**Missing:**
- ❌ Explicit "safe apply" method with pre-flight validation
- ❌ Diff expected vs actual state before applying (prevent accidental overwrites)
- ❌ Explicit safety checks (never blindly DROP + CREATE without validation)
- ❌ Pre-apply registry state comparison

**Impact:** Migrations work but lack safety validation before applying. Risk of accidental overwrites.

---

### 🟡 MEDIUM PRIORITY - User-Facing Features

#### 4. Trigger Detail Page (Section 8 - UI)
**Priority:** MEDIUM - Usability

**Status:** Partial (shown in tables/show but not dedicated page)

**Missing:**
- ❌ Dedicated trigger detail route and controller action
- ❌ Summary panel with all trigger metadata
- ❌ SQL diff view (expected vs actual)
- ❌ Registry state display
- ❌ Action buttons (Enable/Disable/Drop/Re-execute/Execute SQL capsule)
- ❌ Permission-aware, environment-aware, kill switch-aware button visibility

#### 5. UI Actions (Section 8)
**Priority:** MEDIUM - Usability

**Status:** Backend methods exist, UI buttons missing

**Missing:**
- ❌ Enable/Disable buttons in dashboard and tables/show pages (methods exist: `TriggerRegistry#enable!` and `#disable!`)
- ❌ Drop button (requires drop functionality from Section 9)
- ❌ Re-execute button (requires re-execute functionality from Section 9)
- ❌ Execute SQL capsule button (requires SQL capsules from Section 4)

**What Works:**
- ✅ Kill switch enforcement in UI (fully implemented - see Section 6)
- ✅ Migration actions (up/down/redo) with kill switch protection

#### 6. Permissions Enforcement (Section 5)
**Priority:** MEDIUM - Security

**Status:** Permission structure exists but not enforced

**Missing:**
- ❌ Permission checking in controllers (UI actions should check permissions)
- ❌ Permission checking in UI (hide/disable buttons based on role)
- ❌ Permission checks in `TriggerRegistry#enable!` and `disable!` (currently only kill switch checked)
- ❌ Permission checks in rake tasks
- ❌ Permission checks in console APIs
- ❌ Actor context passing through all operations

**What Exists:**
- ✅ Permission structure (Viewer, Operator, Admin roles defined)
- ✅ Permission model classes (`PgSqlTriggers::Permissions::Checker`)

---

### 🟢 LOW PRIORITY - Polish & Improvements

#### 7. Enhanced Logging & Audit Trail
**Priority:** LOW - Operational polish

**Status:** Kill switch logging is comprehensive; audit trail could be enhanced

**Missing:**
- ✅ Kill switch activation attempts logging (fully implemented)
- ✅ Kill switch overrides logging (fully implemented)
- ⚠️ Comprehensive audit trail table for production operation attempts (optional enhancement - logging exists but structured audit table would be better)

#### 8. Error Handling Consistency
**Priority:** LOW - Code quality

**Status:** Kill switch errors are properly implemented; other error types need consistency

**Missing:**
- ✅ Kill switch violations raise `KillSwitchError` (fully implemented)
- ❌ Permission violations should raise `PermissionError`
- ✅ Drift detection implemented (can be used for error handling)
- ❌ Consistent error handling across all operations

#### 9. Testing Coverage
**Priority:** LOW - Quality assurance

**Status:** Kill switch has comprehensive tests; other areas need coverage

**Missing:**
- ❌ SQL capsules need tests
- ✅ Kill switch has comprehensive tests (fully tested)
- ✅ Drift detection has comprehensive tests (fully tested)
- ❌ Permission enforcement needs tests
- ❌ Drop/re-execute flow needs tests

#### 10. Documentation Updates
**Priority:** LOW - User experience

**Status:** Kill switch is well documented; other areas need documentation

**Missing:**
- ❌ README mentions SQL capsules but no implementation details
- ✅ README includes kill switch documentation with enforcement details (fully documented)
- ❌ Need examples for SQL capsules
- ❌ Need examples for permission configuration
- ✅ Drift detection fully documented in implementation plan

#### 11. Partial Implementation Notes
**Priority:** LOW - Known issues and technical debt

**Known Issues:**
- ⚠️ **Permissions Model** - Structure exists but not enforced in UI/CLI/console
- ✅ **Kill Switch** - Fully implemented (see Section 6 for details)
- ✅ **Checksum** - Fully implemented with consistent field-concatenation algorithm across all creation paths
- ✅ **Drift Detection** - Fully implemented with all 6 drift states, comprehensive tests, and console APIs
- ⚠️ **Dashboard** - `installed_at` exists in registry table but not displayed in UI
- ⚠️ **Trigger Detail Page** - No dedicated route/page, info shown in tables/show view only
- ⚠️ **Enable/Disable UI** - Console methods exist with kill switch protection, but no UI buttons
- ⚠️ **Safe Apply** - Works through migrations but lacks explicit safe apply method with pre-flight checks

---

### 📝 Technical Notes

1. **Console API Naming:** Goal shows `PgSqlTrigger.list` but implementation is `PgSqlTriggers::Registry.list` (current is better, just note the difference)
