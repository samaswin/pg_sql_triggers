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
- ~~checksum~~ (⚠️ partially - uses placeholder in registry manager)
- ~~source (dsl / generated / manual_sql)~~
- ~~environment~~
- ~~installed_at~~
- ~~last_verified_at~~

Rails must always know:
- ~~what exists~~
- ~~how it was created~~
- ⚠️ whether it drifted (drift detection not fully implemented)

---

### D. Safe Apply & Deploy ❌ (not implemented)

Applying triggers must:
- ⚠️ Run in a transaction (migrations use transactions, but no explicit "apply" method)
- ❌ Diff expected vs actual (not implemented)
- ⚠️ Never blindly DROP + CREATE (migrations handle this, but no explicit safety checks)
- ⚠️ Support rollback on failure (migration rollback exists, but not explicit apply rollback)
- ⚠️ Update registry atomically (registry updated but not in explicit apply method)

---

### E. Drift Detection ⚠️ (autoloaded but implementation missing)

System must detect:
- ❌ Missing triggers (not implemented)
- ❌ Version mismatch (not implemented)
- ❌ Function body drift (not implemented)
- ❌ Manual SQL overrides (not implemented)
- ❌ Unknown external triggers (not implemented)

Drift states:
1. ❌ Managed & In Sync (constants defined, logic missing)
2. ❌ Managed & Drifted (constants defined, logic missing)
3. ❌ Manual Override (constants defined, logic missing)
4. ❌ Disabled (constants defined, logic missing)
5. ❌ Dropped (Recorded) (constants defined, logic missing)
6. ❌ Unknown (External) (constants defined, logic missing)

---

### F. Rails Console Introspection ✅

Provide console APIs:

~~PgSqlTriggers::Registry.list~~ (note: namespace differs slightly from goal)
~~PgSqlTriggers::Registry.enabled~~
~~PgSqlTriggers::Registry.disabled~~
~~PgSqlTriggers::Registry.for_table(:users)~~
~~PgSqlTriggers::Registry.diff~~ (⚠️ calls drift detection which is not fully implemented)
~~PgSqlTriggers::Registry.validate!~~

~~No raw SQL required by users.~~

---

## 4. Free-Form SQL Execution (MANDATORY) ❌ (routes exist but implementation missing)

The gem MUST support free-form SQL execution.

This is required for:
- emergency fixes
- complex migrations
- DB-owner workflows

### SQL Capsules

Free-form SQL is wrapped in **named SQL capsules**:

- ❌ Must be named (routes exist, implementation missing)
- ❌ Must declare environment (not implemented)
- ❌ Must declare purpose (not implemented)
- ❌ Must be applied explicitly (not implemented)

Rules:
- ❌ Runs in a transaction (not implemented)
- ❌ Checksum verified (not implemented)
- ❌ Registry updated (not implemented)
- ❌ Marked as `source = manual_sql` (not implemented)

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

### Dashboard ✅ (partial)
- ~~Trigger name~~
- ~~Table~~
- ~~Version~~
- ~~Status~~
- ~~Source~~
- ⚠️ Drift state (displayed but drift detection not fully implemented)
- ~~Environment~~
- ⚠️ Last applied (installed_at exists but not displayed)

### Trigger Detail Page ❌ (not implemented)
- ❌ Summary panel (trigger info shown in tables/show but no dedicated page)
- ❌ SQL diff
- ❌ Registry state

### Actions (State-Based) ⚠️ (structure exists, not fully implemented)
- ⚠️ Enable (method exists but no UI buttons/flow)
- ⚠️ Disable (method exists but no UI buttons/flow)
- ❌ Drop (not implemented)
- ❌ Re-execute (not implemented)
- ❌ Execute SQL capsule (not implemented)

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

### ✅ Achieved Features

**Core Infrastructure:**
- ✅ Trigger Declaration DSL (`PgSqlTriggers::DSL.pg_sql_trigger`) - Section 3.A
- ✅ Trigger Registry model and table with all required fields - Section 3.C
- ✅ Trigger Generation (form-based wizard, DSL + migration files) - Section 3.B
- ✅ Database Introspection (tables, triggers, columns) - Supporting infrastructure
- ✅ Trigger Migrations system (rake tasks + UI) - Supporting infrastructure
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
- ✅ Registry tracks checksum (⚠️ partially - uses placeholder in registry manager)
- ✅ Rails knows what exists and how it was created

**From Section 3.F (Rails Console Introspection):**
- ✅ `PgSqlTriggers::Registry.list` (note: namespace differs slightly from goal)
- ✅ `PgSqlTriggers::Registry.enabled`
- ✅ `PgSqlTriggers::Registry.disabled`
- ✅ `PgSqlTriggers::Registry.for_table(:users)`
- ✅ `PgSqlTriggers::Registry.validate!`
- ✅ No raw SQL required by users for basic operations

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
- ✅ Dashboard with: Trigger name, Table, Version, Status, Source, Environment
- ✅ Dashboard displays drift state (⚠️ drift detection not fully implemented)

---

### 🔴 HIGH PRIORITY - Critical Missing Features

#### 1. Drift Detection (Section 3.E)
**Priority:** HIGH - Core functionality

**Status:** Autoloaded but implementation files missing

**Missing Files:**
- ❌ `lib/pg_sql_triggers/drift/detector.rb` - Drift detection logic
- ❌ `lib/pg_sql_triggers/drift/reporter.rb` - Drift reporting

**Missing Functionality:**
- ❌ Detection of missing triggers
- ❌ Version mismatch detection
- ❌ Function body drift detection
- ❌ Manual SQL override detection
- ❌ Unknown external trigger detection
- ❌ All 6 drift states properly implemented (Managed & In Sync, Managed & Drifted, Manual Override, Disabled, Dropped (Recorded), Unknown (External))

#### 2. Safe Apply & Deploy (Section 3.D)
**Priority:** HIGH - Deployment safety

**Status:** Not implemented

**Missing:**
- ❌ Safe apply method that runs in a transaction
- ❌ Diff expected vs actual state before applying
- ❌ Explicit safety checks (never blindly DROP + CREATE)
- ❌ Rollback on failure with registry rollback
- ❌ Atomic registry update
- ❌ Integration with migrations and generator service

#### 3. Drop & Re-Execute Flow (CRITICAL - Section 9)
**Priority:** HIGH - Operational requirements

**Status:** Not implemented

**Missing:**
- ❌ Drop trigger functionality with permission checks, kill switch, reason, typed confirmation
- ❌ Re-execute functionality with diff display, reason, typed confirmation
- ❌ UI for drop/re-execute actions
- ❌ Confirmation dialogs with typed confirmation text
- ❌ Transactional execution and registry update

---

### 🟡 MEDIUM PRIORITY - User-Facing Features

#### 4. SQL Capsules (MANDATORY - Section 4)
**Priority:** MEDIUM - Emergency operations

**Status:** Routes exist but implementation missing

**Missing Files:**
- ❌ `lib/pg_sql_triggers/sql/capsule.rb` - SQL capsule definition class
- ❌ `lib/pg_sql_triggers/sql/executor.rb` - SQL execution with transaction, checksum, registry update
- ❌ `app/controllers/pg_sql_triggers/sql_capsules_controller.rb` - UI controller
- ❌ SQL capsule views (new, show, create)
- ❌ SQL capsule storage mechanism

**Requirements to implement:**
- Named SQL capsules with environment and purpose declaration
- Explicit application workflow
- Transactional execution
- Checksum verification
- Registry update with `source = manual_sql`

#### 5. Trigger Detail Page (Section 8 - UI)
**Priority:** MEDIUM - Usability

**Status:** Partial (shown in tables/show but not dedicated page)

**Missing:**
- ❌ Dedicated trigger detail route and controller action
- ❌ Summary panel with all trigger metadata
- ❌ SQL diff view (expected vs actual)
- ❌ Registry state display
- ❌ Action buttons (Enable/Disable/Drop/Re-execute/Execute SQL capsule)
- ❌ Permission-aware, environment-aware, kill switch-aware button visibility

#### 6. UI Actions & Permissions Enforcement (Section 8)
**Priority:** MEDIUM - Usability & security

**Status:** Structure exists but not fully enforced

**Missing:**
- ❌ Enable/Disable buttons in dashboard and detail pages
- ❌ Drop button (Admin only)
- ❌ Re-execute button with flow
- ❌ Execute SQL capsule button (Admin only)
- ❌ Permission checking in controllers
- ❌ Permission checking in UI (hide/disable buttons)
- ✅ Kill switch enforcement in UI (fully implemented - see Section 6)
- ❌ Environment awareness in UI actions

---

### 🟢 LOW PRIORITY - Polish & Improvements

#### 8. Console/CLI Permission Enforcement (Section 5)
**Priority:** LOW - Security polish

**Status:** Not enforced

**Missing:**
- ❌ Permission checks in `TriggerRegistry#enable!` and `disable!`
- ❌ Permission checks in rake tasks
- ❌ Permission checks in console APIs
- ❌ Actor context passing through all operations

#### 9. Checksum Implementation Consistency
**Priority:** LOW - Technical debt

**Status:** Partially implemented

**Issues:**
- ⚠️ Registry manager uses "placeholder" checksum instead of calculating real checksum
- ✅ Generator service calculates checksum correctly
- ⚠️ Need consistent checksum calculation across all creation paths

**Fix Required:**
- Replace "placeholder" in `Registry::Manager.register` with actual checksum calculation
- Ensure checksum is calculated consistently (same algorithm as generator)

#### 10. Enhanced Logging & Audit Trail
**Priority:** LOW - Operational polish

**Status:** Kill switch logging is comprehensive; audit trail could be enhanced

**Missing:**
- ✅ Kill switch activation attempts logging (fully implemented)
- ✅ Kill switch overrides logging (fully implemented)
- ⚠️ Comprehensive audit trail table for production operation attempts (optional enhancement - logging exists but structured audit table would be better)

#### 11. Error Handling Consistency
**Priority:** LOW - Code quality

**Status:** Kill switch errors are properly implemented; other error types need consistency

**Missing:**
- ✅ Kill switch violations raise `KillSwitchError` (fully implemented)
- ❌ Permission violations should raise `PermissionError`
- ❌ Drift issues should raise `DriftError`
- ❌ Consistent error handling across all operations

#### 12. Testing Coverage
**Priority:** LOW - Quality assurance

**Status:** Kill switch has comprehensive tests; other areas need coverage

**Missing:**
- ❌ SQL capsules need tests
- ✅ Kill switch has comprehensive tests (fully tested)
- ❌ Drift detection needs tests
- ❌ Permission enforcement needs tests
- ❌ Drop/re-execute flow needs tests

#### 13. Documentation Updates
**Priority:** LOW - User experience

**Status:** Kill switch is well documented; other areas need documentation

**Missing:**
- ❌ README mentions SQL capsules but no implementation details
- ✅ README includes kill switch documentation with enforcement details (fully documented)
- ❌ Need examples for SQL capsules
- ❌ Need examples for permission configuration

#### 14. Partial Implementation Notes
**Priority:** LOW - Known issues

- ⚠️ Permissions Model - Structure exists but not enforced in UI/CLI/console
- ✅ Kill Switch - Fully implemented (see Section 6 for details)
- ⚠️ Checksum - Implemented in generator service correctly, but Registry::Manager.register uses "placeholder" (needs fix for DSL-registered triggers)
- ⚠️ Drift Detection - Constants defined, Detector and Reporter classes missing
- ⚠️ Dashboard - Drift state displayed but drift detection not fully implemented (will work once drift detection is implemented)
- ⚠️ Dashboard - Last applied (installed_at exists in registry but not displayed in UI)
- ⚠️ `PgSqlTriggers::Registry.diff` - Calls drift detection which is not fully implemented

---

### 📝 Technical Notes

1. **Console API Naming:** Goal shows `PgSqlTrigger.list` but implementation is `PgSqlTriggers::Registry.list` (current is better, just note the difference)
