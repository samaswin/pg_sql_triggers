# Version 1.2.0 Implementation Plan

## Current Status (v1.1.0)

**Fully Implemented:**
- ✅ Trigger Declaration DSL
- ✅ Trigger Generation
- ✅ Trigger Registry with drift detection
- ✅ Safe Apply & Deploy (pre-apply comparison, safety validation)
- ✅ Kill Switch for Production Safety
- ✅ Basic UI (Dashboard, Tables view, Generator)
- ✅ Rails Console Introspection APIs

**Partially Implemented:**
- ⚠️ UI Actions (backend methods exist, no UI buttons)
- ⚠️ Permissions (structure exists, not enforced)
- ⚠️ Trigger Detail Page (info shown in tables/show, no dedicated page)

**Not Implemented (Critical):**
- ❌ SQL Capsules (MANDATORY - routes exist, no implementation)
- ❌ Drop & Re-Execute Flow (CRITICAL - no implementation)

---

## Recommended Starting Point: UI Actions (Enable/Disable)

**Why Start Here:**
1. **Quick Win** - Backend methods (`TriggerRegistry#enable!` and `#disable!`) already exist with kill switch protection
2. **Low Risk** - Simple UI additions, minimal new logic
3. **High Value** - Users can immediately control triggers from UI
4. **Foundation** - Sets up patterns for other UI actions (drop, re-execute)

**Estimated Effort:** 2-3 days

---

## Version 1.2.0 Feature Plan

### 🎯 Phase 1: Quick Wins (Week 1)

#### 1.1 UI Actions: Enable/Disable Triggers
**Priority:** HIGH - Quick win, high user value
**Status:** Backend exists, UI missing

**Tasks:**
- [ ] Add `enable` and `disable` actions to `TriggersController` (or create new controller)
- [ ] Add enable/disable buttons to dashboard view
- [ ] Add enable/disable buttons to tables/show view
- [ ] Add enable/disable buttons to trigger detail page (when created)
- [ ] Implement confirmation modal for production environments
- [ ] Add flash messages for success/error states
- [ ] Add permission checks (Operator role required)
- [ ] Add kill switch protection (already in backend, ensure UI respects it)
- [ ] Write specs (>90% coverage)
- [ ] Update documentation

**Files to Create/Modify:**
- `app/controllers/pg_sql_triggers/triggers_controller.rb` (new)
- `app/views/pg_sql_triggers/dashboard/index.html.erb` (modify)
- `app/views/pg_sql_triggers/tables/show.html.erb` (modify)
- `app/views/pg_sql_triggers/triggers/show.html.erb` (new - part of Phase 2)
- `spec/pg_sql_triggers/controllers/triggers_controller_spec.rb` (new)
- `config/routes.rb` (add triggers routes)

**Acceptance Criteria:**
- Users can enable/disable triggers from dashboard and table views
- Kill switch blocks operations in production (with confirmation)
- Permission checks prevent unauthorized access
- Flash messages provide clear feedback
- All operations are logged

---

### 🚀 Phase 2: Critical Features (Weeks 2-3)

#### 2.1 SQL Capsules (MANDATORY)
**Priority:** CRITICAL - Mandatory feature for emergency operations
**Status:** Routes exist, no implementation

**Tasks:**
- [ ] Create `lib/pg_sql_triggers/sql/capsule.rb` class
  - Named SQL capsules
  - Environment declaration
  - Purpose/description field
  - SQL content storage
  - Checksum calculation
- [ ] Create `lib/pg_sql_triggers/sql/executor.rb` class
  - Transactional execution
  - Checksum verification
  - Registry update with `source = manual_sql`
  - Kill switch protection
  - Comprehensive logging
- [ ] Create `app/controllers/pg_sql_triggers/sql_capsules_controller.rb`
  - `new` - Form for creating SQL capsule
  - `create` - Save SQL capsule (to registry or separate table)
  - `show` - Display SQL capsule details
  - `execute` - Execute SQL capsule with confirmation
- [ ] Create SQL capsule views
  - `new.html.erb` - Form with name, environment, purpose, SQL editor
  - `show.html.erb` - Display capsule details with execute button
  - Confirmation modal for execution
- [ ] Add SQL capsule storage mechanism
  - Option 1: Use registry table with `source = manual_sql` and special trigger_name pattern
  - Option 2: Create separate `pg_sql_triggers_sql_capsules` table
  - **Recommendation:** Use registry table to keep single source of truth
- [ ] Add permission checks (Admin role required for execute)
- [ ] Add kill switch protection for execution
- [ ] Write comprehensive specs (>90% coverage)
- [ ] Update documentation with examples

**Files to Create:**
- `lib/pg_sql_triggers/sql/capsule.rb` (new)
- `lib/pg_sql_triggers/sql/executor.rb` (new)
- `app/controllers/pg_sql_triggers/sql_capsules_controller.rb` (new)
- `app/views/pg_sql_triggers/sql_capsules/new.html.erb` (new)
- `app/views/pg_sql_triggers/sql_capsules/show.html.erb` (new)
- `app/views/pg_sql_triggers/sql_capsules/_form.html.erb` (new)
- `spec/pg_sql_triggers/sql/capsule_spec.rb` (new)
- `spec/pg_sql_triggers/sql/executor_spec.rb` (new)
- `spec/pg_sql_triggers/controllers/sql_capsules_controller_spec.rb` (new)

**Files to Modify:**
- `lib/pg_sql_triggers/sql.rb` (update autoload references)
- `config/routes.rb` (routes already exist, verify)

**Acceptance Criteria:**
- Users can create named SQL capsules with environment and purpose
- SQL capsules are stored in registry with `source = manual_sql`
- Execution requires explicit confirmation
- Execution runs in transaction
- Checksum is calculated and stored
- Registry is updated after execution
- Kill switch blocks execution in production
- Admin permission required
- Comprehensive logging

#### 2.2 Trigger Detail Page
**Priority:** MEDIUM-HIGH - Usability improvement
**Status:** Info shown in tables/show, no dedicated page

**Tasks:**
- [ ] Create dedicated trigger detail route (`/triggers/:id` or `/triggers/:trigger_name`)
- [ ] Create `TriggersController#show` action
- [ ] Create `app/views/pg_sql_triggers/triggers/show.html.erb`
  - Summary panel with all trigger metadata
  - SQL diff view (expected vs actual) using drift detection
  - Registry state display
  - Action buttons (Enable/Disable/Drop/Re-execute/Execute SQL capsule)
  - Permission-aware button visibility
  - Environment-aware button visibility
  - Kill switch-aware button visibility
- [ ] Add SQL diff display component
  - Use `Drift::Reporter` for formatting
  - Show expected SQL (from DSL/migration)
  - Show actual SQL (from database)
  - Highlight differences
- [ ] Integrate with enable/disable actions from Phase 1
- [ ] Write specs (>90% coverage)
- [ ] Update documentation

**Files to Create:**
- `app/views/pg_sql_triggers/triggers/show.html.erb` (new)
- `app/views/pg_sql_triggers/triggers/_summary_panel.html.erb` (new)
- `app/views/pg_sql_triggers/triggers/_sql_diff.html.erb` (new)
- `app/views/pg_sql_triggers/triggers/_action_buttons.html.erb` (new)

**Files to Modify:**
- `app/controllers/pg_sql_triggers/triggers_controller.rb` (add show action)
- `config/routes.rb` (add trigger detail route)
- `app/views/pg_sql_triggers/dashboard/index.html.erb` (link to detail page)
- `app/views/pg_sql_triggers/tables/show.html.erb` (link to detail page)

**Acceptance Criteria:**
- Dedicated trigger detail page accessible from dashboard and tables view
- Shows comprehensive trigger metadata
- Displays SQL diff (expected vs actual)
- Shows registry state and drift information
- Action buttons respect permissions, environment, and kill switch
- All actions work from detail page

---

### 🔧 Phase 3: Advanced Features (Weeks 4-5)

#### 3.1 Drop & Re-Execute Flow (CRITICAL)
**Priority:** HIGH - Operational requirements
**Status:** Not implemented

**Tasks:**
- [ ] Add `TriggerRegistry#drop!` method
  - Permission checks (Admin role)
  - Kill switch protection
  - Reason field (required)
  - Typed confirmation (required)
  - Transactional execution
  - Registry update (mark as dropped or remove)
  - Comprehensive logging
- [ ] Add `TriggerRegistry#re_execute!` method
  - Permission checks (Admin role)
  - Kill switch protection
  - Show diff before execution (using drift detection)
  - Reason field (required)
  - Typed confirmation (required)
  - Transactional execution
  - Registry update
  - Comprehensive logging
- [ ] Add drop action to `TriggersController`
- [ ] Add re_execute action to `TriggersController`
- [ ] Create drop confirmation modal
  - Show trigger details
  - Require reason input
  - Require typed confirmation text
- [ ] Create re-execute confirmation modal
  - Show diff (expected vs actual)
  - Require reason input
  - Require typed confirmation text
- [ ] Add drop/re-execute buttons to trigger detail page
- [ ] Add drop/re-execute buttons to dashboard (with permission checks)
- [ ] Write comprehensive specs (>90% coverage)
- [ ] Update documentation

**Files to Create:**
- `app/views/pg_sql_triggers/triggers/_drop_modal.html.erb` (new)
- `app/views/pg_sql_triggers/triggers/_re_execute_modal.html.erb` (new)

**Files to Modify:**
- `app/models/pg_sql_triggers/trigger_registry.rb` (add drop! and re_execute! methods)
- `app/controllers/pg_sql_triggers/triggers_controller.rb` (add drop and re_execute actions)
- `app/views/pg_sql_triggers/triggers/show.html.erb` (add buttons)
- `app/views/pg_sql_triggers/dashboard/index.html.erb` (add buttons with permission checks)

**Acceptance Criteria:**
- Drop requires Admin permission, kill switch check, reason, and typed confirmation
- Re-execute shows diff before execution
- Re-execute requires Admin permission, kill switch check, reason, and typed confirmation
- Both operations run in transactions
- Registry is updated after operations
- All operations are logged
- No silent operations allowed

#### 3.2 Permissions Enforcement
**Priority:** MEDIUM - Security enhancement
**Status:** Structure exists, not enforced

**Tasks:**
- [ ] Add permission checks to all controller actions
  - Dashboard: Viewer role
  - Tables: Viewer role
  - Generator: Operator role
  - Triggers (enable/disable): Operator role
  - Triggers (drop/re-execute): Admin role
  - SQL Capsules (execute): Admin role
  - Migrations: Operator role
- [ ] Add permission checks to UI (hide/disable buttons)
  - Use `Permissions.can?` helper in views
  - Hide buttons for unauthorized actions
  - Show disabled state with tooltip
- [ ] Add permission checks to `TriggerRegistry` methods
  - `enable!` - Operator role
  - `disable!` - Operator role
  - `drop!` - Admin role
  - `re_execute!` - Admin role
- [ ] Add permission checks to rake tasks
  - Check permissions before executing migrations
  - Raise `PermissionError` if unauthorized
- [ ] Add permission checks to console APIs
  - `Registry.enable`, `Registry.disable` - Operator role
  - `Registry.drop`, `Registry.re_execute` - Admin role
- [ ] Create `PermissionError` exception class
- [ ] Add permission helper methods to `ApplicationController`
- [ ] Write comprehensive specs (>90% coverage)
- [ ] Update documentation with permission configuration examples

**Files to Create:**
- `lib/pg_sql_triggers/permissions/error.rb` (new - PermissionError class)

**Files to Modify:**
- `app/controllers/pg_sql_triggers/application_controller.rb` (add permission helpers)
- `app/controllers/pg_sql_triggers/dashboard_controller.rb` (add permission checks)
- `app/controllers/pg_sql_triggers/tables_controller.rb` (add permission checks)
- `app/controllers/pg_sql_triggers/generator_controller.rb` (add permission checks)
- `app/controllers/pg_sql_triggers/triggers_controller.rb` (add permission checks)
- `app/controllers/pg_sql_triggers/sql_capsules_controller.rb` (add permission checks)
- `app/controllers/pg_sql_triggers/migrations_controller.rb` (add permission checks)
- `app/models/pg_sql_triggers/trigger_registry.rb` (add permission checks)
- `lib/pg_sql_triggers/registry.rb` (add permission checks to console APIs)
- `lib/tasks/trigger_migrations.rake` (add permission checks)
- All view files (add permission-aware button visibility)

**Acceptance Criteria:**
- All controller actions check permissions
- UI buttons are hidden/disabled based on permissions
- Console APIs check permissions
- Rake tasks check permissions
- Permission violations raise `PermissionError`
- Clear error messages for permission denials

---

### 🎨 Phase 4: Polish & Documentation (Week 6)

#### 4.1 UI Enhancements
**Tasks:**
- [ ] Add `installed_at` display to dashboard
- [ ] Improve drift state display in dashboard
- [ ] Add loading states for async operations
- [ ] Improve error message display
- [ ] Add tooltips for permission-restricted actions
- [ ] Improve mobile responsiveness
- [ ] Add keyboard shortcuts for common actions

#### 4.2 Documentation Updates
**Tasks:**
- [ ] Update README with SQL capsules examples
- [ ] Add SQL capsules usage guide
- [ ] Add drop/re-execute flow documentation
- [ ] Add permission configuration guide
- [ ] Update API reference with new methods
- [ ] Add troubleshooting guide
- [ ] Update CHANGELOG.md

#### 4.3 Testing & Quality
**Tasks:**
- [ ] Ensure >90% test coverage for all new features
- [ ] Run rubocop and fix linting issues
- [ ] Run erb_lint and fix linting issues
- [ ] Add integration tests for complete workflows
- [ ] Performance testing for large trigger sets
- [ ] Security audit for permission system

---

## Implementation Priority Summary

### Must Have (v1.2.0 Core)
1. ✅ **UI Actions: Enable/Disable** (Phase 1) - Quick win, high value
2. ✅ **SQL Capsules** (Phase 2.1) - MANDATORY feature
3. ✅ **Trigger Detail Page** (Phase 2.2) - Usability critical
4. ✅ **Drop & Re-Execute Flow** (Phase 3.1) - CRITICAL operational requirement

### Should Have (v1.2.0 Enhancement)
5. ✅ **Permissions Enforcement** (Phase 3.2) - Security enhancement

### Nice to Have (Future Versions)
6. Enhanced logging & audit trail table
7. Error handling consistency improvements
8. Additional UI polish

---

## Recommended Implementation Order

### Sprint 1 (Week 1): Quick Wins
- **Day 1-2:** UI Actions: Enable/Disable Triggers
- **Day 3-5:** Testing, documentation, code review

### Sprint 2 (Week 2): SQL Capsules
- **Day 1-3:** SQL Capsule model and executor
- **Day 4-5:** SQL Capsules controller and views

### Sprint 3 (Week 3): Trigger Detail Page
- **Day 1-2:** Trigger detail page implementation
- **Day 3-4:** SQL diff display
- **Day 5:** Testing and integration

### Sprint 4 (Week 4): Drop & Re-Execute
- **Day 1-2:** Drop functionality
- **Day 3-4:** Re-execute functionality
- **Day 5:** Testing and integration

### Sprint 5 (Week 5): Permissions
- **Day 1-3:** Permission enforcement across all layers
- **Day 4-5:** Testing and documentation

### Sprint 6 (Week 6): Polish & Release
- **Day 1-2:** UI enhancements
- **Day 3:** Documentation updates
- **Day 4:** Final testing and quality checks
- **Day 5:** Release preparation

---

## Success Metrics

1. **Feature Completeness:** All MANDATORY and CRITICAL features implemented
2. **Test Coverage:** >90% for all new code
3. **Code Quality:** No rubocop or erb_lint errors
4. **Documentation:** All new features documented with examples
5. **User Experience:** All actions accessible from UI with proper feedback

---

## Risk Assessment

### High Risk
- **SQL Capsules:** Complex feature, needs careful transaction handling
  - *Mitigation:* Extensive testing, use existing kill switch patterns

### Medium Risk
- **Drop & Re-Execute:** Destructive operations, must be safe
  - *Mitigation:* Multiple confirmation layers, comprehensive logging

### Low Risk
- **UI Actions:** Backend exists, mostly UI work
- **Trigger Detail Page:** Display logic, low complexity
- **Permissions:** Structure exists, enforcement is straightforward

---

## Dependencies

- **Phase 1** (UI Actions): No dependencies
- **Phase 2.1** (SQL Capsules): No dependencies
- **Phase 2.2** (Trigger Detail Page): Benefits from Phase 1 (enable/disable buttons)
- **Phase 3.1** (Drop & Re-Execute): Benefits from Phase 2.2 (detail page for actions)
- **Phase 3.2** (Permissions): Can be done in parallel, but should be integrated into all phases

---

## Notes

- All new features must respect kill switch (already implemented)
- All new features must include permission checks
- All new features must have >90% test coverage
- All new features must be documented
- All changes must be added to CHANGELOG.md
- Follow existing code patterns and conventions

