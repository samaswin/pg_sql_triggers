You are building a **production-grade Ruby on Rails gem** named **pg_sql_triggers**.

This gem is **not a toy generator**.
It is a **PostgreSQL Trigger Control Plane for Rails**, designed for real teams running production systems.

You must follow everything below strictly.

---

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

### A. Trigger Declaration (DSL)

Developers declare triggers using Ruby DSL:

```ruby
pg_trigger "users_email_validation" do
  table :users
  on :insert, :update
  function :validate_user_email

  version 3
  enabled true

  when_env :production
end
```

Rules:
- DSL generates metadata, NOT raw SQL
- Every trigger has a version
- Triggers are environment-aware
- Triggers can be enabled or disabled

---

### B. Trigger Generation

The gem must generate triggers safely.

Generators create:
1. Trigger DSL file
2. Function stub (PL/pgSQL)
3. Manifest metadata

Rules:
- Generated triggers are **disabled by default**
- Nothing executes automatically
- Developers must explicitly apply

---

### C. Trigger Registry (Source of Truth)

All triggers must be tracked in a registry table.

Registry tracks:
- trigger_name
- table_name
- version
- enabled
- checksum
- source (dsl / generated / manual_sql)
- environment
- installed_at
- last_verified_at

Rails must always know:
- what exists
- how it was created
- whether it drifted

---

### D. Safe Apply & Deploy

Applying triggers must:
- Run in a transaction
- Diff expected vs actual
- Never blindly DROP + CREATE
- Support rollback on failure
- Update registry atomically

---

### E. Drift Detection

System must detect:
- Missing triggers
- Version mismatch
- Function body drift
- Manual SQL overrides
- Unknown external triggers

Drift states:
1. Managed & In Sync
2. Managed & Drifted
3. Manual Override
4. Disabled
5. Dropped (Recorded)
6. Unknown (External)

---

### F. Rails Console Introspection

Provide console APIs:

PgTrigger.list
PgTrigger.enabled
PgTrigger.disabled
PgTrigger.for_table(:users)
PgTrigger.diff
PgTrigger.validate!

No raw SQL required by users.

---

## 4. Free-Form SQL Execution (MANDATORY)

The gem MUST support free-form SQL execution.

This is required for:
- emergency fixes
- complex migrations
- DB-owner workflows

### SQL Capsules

Free-form SQL is wrapped in **named SQL capsules**:

- Must be named
- Must declare environment
- Must declare purpose
- Must be applied explicitly

Rules:
- Runs in a transaction
- Checksum verified
- Registry updated
- Marked as `source = manual_sql`

---

## 5. Permissions Model v1

Three permission levels:

### Viewer
- Read-only
- View triggers
- View diffs

### Operator
- Enable / Disable triggers
- Apply generated triggers
- Re-execute triggers in non-prod
- Dry-run SQL

### Admin
- Drop triggers
- Execute free-form SQL
- Re-execute triggers in any env
- Override drift

Permissions enforced in:
- UI
- CLI
- Console

---

## 6. Kill Switch for Production SQL (MANDATORY)

Production mutations must be gated.

### Levels:
1. Global disable (default)
2. Runtime ENV override
3. Explicit confirmation text
4. Optional time-window auto-lock

Kill switch must:
- Block UI
- Block CLI
- Block console
- Always log attempts

---

## 8. UI (Mountable Rails Engine)

UI is operational, not decorative.

### Dashboard
- Trigger name
- Table
- Version
- Status
- Source
- Drift state
- Environment
- Last applied

### Trigger Detail Page
- Summary panel
- SQL diff
- Registry state

### Actions (State-Based)
- Enable
- Disable
- Drop
- Re-execute
- Execute SQL capsule

Buttons must:
- Be permission-aware
- Be env-aware
- Respect kill switch

---

## 9. Drop & Re-Execute Flow (CRITICAL)

Re-execute must:
1. Show diff
2. Require reason
3. Require typed confirmation
4. Execute transactionally
5. Update registry

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
