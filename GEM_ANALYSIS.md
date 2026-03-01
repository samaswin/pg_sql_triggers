# pg_sql_triggers — Gem Analysis

> Analysed against version **1.3.0** · February 2026

---

## Table of Contents
1. [Critical Bugs](#1-critical-bugs)
2. [Design Issues](#2-design-issues)
3. [Security Concerns](#3-security-concerns)
4. [Missing Features](#4-missing-features)
5. [Unnecessary / Over-engineered Features](#5-unnecessary--over-engineered-features)
6. [Low-coverage Hotspots](#6-low-coverage-hotspots)
7. [Summary Table](#7-summary-table)

---

## 1. Critical Bugs

### 1.1 Checksum Algorithm Is Inconsistent — Will Always Report False Drift

Three places compute a trigger checksum. They use different field sets:

| Location | Fields included |
|---|---|
| `TriggerRegistry#calculate_checksum` | `trigger_name, table_name, version, function_body, condition, timing` |
| `Registry::Manager#calculate_checksum` | `name, table_name, version, function_body, condition, timing` |
| `Drift::Detector#calculate_db_checksum` | `trigger_name, table_name, version, function_body, condition` ← **missing `timing`** |

Because the registry stores a checksum that includes `timing`, but the drift detector recomputes the checksum without `timing`, **every trigger that has a non-default timing value will permanently show as `DRIFTED`** even when fully in sync.

Files:
- [lib/pg_sql_triggers/drift/detector.rb:88-103](lib/pg_sql_triggers/drift/detector.rb#L88-L103)
- [app/models/pg_sql_triggers/trigger_registry.rb:318-327](app/models/pg_sql_triggers/trigger_registry.rb#L318-L327)
- [lib/pg_sql_triggers/registry/manager.rb:129-145](lib/pg_sql_triggers/registry/manager.rb#L129-L145)

---

### 1.2 `extract_function_body` Returns the Full `CREATE FUNCTION` Statement

`Detector#extract_function_body` returns `function_def` unchanged — the full output of `pg_get_functiondef()`, including the `CREATE OR REPLACE FUNCTION` header. The registry stores only the PL/pgSQL body. These two strings will never match, so **the drift detector will report every trigger as DRIFTED regardless of actual state**.

```ruby
# lib/pg_sql_triggers/drift/detector.rb:106-114
def extract_function_body(db_trigger)
  function_def = db_trigger["function_definition"]
  return nil unless function_def

  # TODO: Parse and extract just the body if needed
  function_def  # ← returns entire CREATE FUNCTION definition
end
```

The `# TODO` comment confirms this is incomplete.

---

### 1.3 DSL Triggers Store `"placeholder"` as Checksum → Permanent False Drift

When a DSL trigger definition has no `function_body` (which is the normal case — `TriggerDefinition#function_body` always returns `nil`), `Manager#calculate_checksum` detects `function_body_value.blank?` and stores the literal string `"placeholder"` in the registry. The drift detector then computes a real SHA256 hash from the database and compares it to `"placeholder"`, so **all DSL-defined triggers always appear DRIFTED**.

```ruby
# lib/pg_sql_triggers/registry/manager.rb:133
return "placeholder" if function_body_value.blank?
```

---

### 1.4 `re_execute!` Is Broken for All DSL-Defined Triggers

`TriggerRegistry#re_execute!` raises immediately if `function_body` is blank:

```ruby
raise StandardError, "Cannot re-execute: missing function_body" if function_body.blank?
```

Since `TriggerDefinition#function_body` always returns `nil`, DSL-defined triggers (the primary usage path) can **never be re-executed** through this method. The method is effectively dead for the main use case.

File: [app/models/pg_sql_triggers/trigger_registry.rb:289](app/models/pg_sql_triggers/trigger_registry.rb#L289)

---

### 1.5 `SafetyValidator#capture_sql` Actually Executes the Migration

The safety validator captures SQL by monkey-patching the instance's `execute` method, then calling the migration's `up`/`down` method:

```ruby
# lib/pg_sql_triggers/migrator/safety_validator.rb:57-68
def capture_sql(migration_instance, direction)
  captured = []
  migration_instance.define_singleton_method(:execute) do |sql|
    captured << sql.to_s.strip
  end
  migration_instance.public_send(direction)  # ← runs the migration method
  captured
end
```

If the migration does anything other than call `execute` (e.g. calls `add_column`, `create_table`, or any other ActiveRecord migration helper), those side effects run for real during the safety check. Then `run_migration` creates two more instances and runs them again — meaning a single migration run can execute the migration's code path **three times**.

---

### 1.6 Dead Code in `drop!`

Inside `drop!`, there is a bare expression `trigger_name` on its own line that does nothing:

```ruby
# app/models/pg_sql_triggers/trigger_registry.rb:249-251
ActiveRecord::Base.transaction do
  drop_trigger_from_database
  trigger_name   # ← no-op; return value is discarded
  destroy!
```

This is likely a leftover from an assignment like `name = trigger_name` that was refactored away.

---

## 2. Design Issues

### 2.1 N+1 Queries in All Drift Registry Methods

`Registry::Manager#drifted`, `#in_sync`, `#unknown_triggers`, and `#dropped` all call `Drift::Detector.detect_all`, which loops over every registry entry and calls `detect(entry.trigger_name)` per entry. Each `detect` call performs `TriggerRegistry.find_by(trigger_name:)` — an individual SQL query. For N triggers, this is N+1 queries.

```ruby
# lib/pg_sql_triggers/drift/detector.rb:38-56
def detect_all
  registry_entries = TriggerRegistry.all.to_a   # 1 query
  db_triggers = DbQueries.all_triggers           # 1 query
  results = registry_entries.map do |entry|
    detect(entry.trigger_name)                   # 1 query per entry ← N+1
  end
```

---

### 2.2 Class-Level Cache Is Not Thread-Safe

`Registry::Manager._registry_cache` is stored in a class-level instance variable (`@_registry_cache`). In a multi-threaded Puma server, concurrent requests share and mutate this hash without synchronisation, creating a potential race condition where one thread's cache write corrupts another thread's lookup.

File: [lib/pg_sql_triggers/registry/manager.rb:9-15](lib/pg_sql_triggers/registry/manager.rb#L9-L15)

---

### 2.3 `DbQueries` Hard-Codes the `public` Schema

Every SQL query filters `n.nspname = 'public'`. Applications using non-public schemas (multi-tenant schemas, `app`, `audit`, etc.) cannot use this gem at all.

File: [lib/pg_sql_triggers/drift/db_queries.rb](lib/pg_sql_triggers/drift/db_queries.rb) — lines 27, 51, 78, 93

---

### 2.4 `when_env` DSL Option Is an Anti-Pattern

The DSL supports environment-specific triggers:

```ruby
PgSqlTriggers::DSL.pg_sql_trigger "users_email_validation" do
  when_env :production
end
```

Having triggers that exist only in production but not in staging or development makes it impossible to test them fully. Schema drift between environments is guaranteed and bugs will only surface in production. Environment-specific behavior belongs in configuration, not in trigger definitions.

---

### 2.5 Dual Generator Paths Create Ambiguity

Two separate generator namespaces exist for the same task:

- `lib/generators/pg_sql_triggers/trigger_migration_generator.rb` → invoked with `rails g pg_sql_triggers:trigger_migration`
- `lib/generators/trigger/migration_generator.rb` → invoked with `rails g trigger:migration`

There is no documentation explaining which to prefer, and having both increases maintenance surface without benefit.

---

### 2.6 `capture_state` Does Not Include `function_body`

The audit log state snapshot captures `enabled`, `version`, `checksum`, `table_name`, `source`, `environment`, and `installed_at` — but not `function_body`. Diffs recorded in audit logs will not show what the function body was before/after an operation, making the audit trail incomplete for the most important change: the function itself.

File: [app/models/pg_sql_triggers/trigger_registry.rb:414-424](app/models/pg_sql_triggers/trigger_registry.rb#L414-L424)

---

### 2.7 `enabled` and `version` Use Non-Idiomatic Dual-Purpose Methods in DSL

```ruby
def version(version = nil)
  if version.nil?
    @version
  else
    @version = version
  end
end
```

Ruby DSLs conventionally use `attr_accessor` for simple getters/setters or separate `def version=(v)` / `def version` methods. The current pattern is confusing because calling `version` with no arguments returns the current value rather than raising `ArgumentError`, making typos silent.

---

## 3. Security Concerns

### 3.1 Default Permissions Allow Everything

`Permissions::Checker#can?` returns `true` for all actors and all actions when no `permission_checker` is configured:

```ruby
# lib/pg_sql_triggers/permissions/checker.rb:16-17
# Default behavior: allow all permissions
true
```

A newly installed gem with no extra configuration grants every user full ADMIN access (including `drop_trigger`, `execute_sql`, `override_drift`). The comment says "This should be overridden in production via configuration", but there is no warning in the initializer or README to flag this as a critical step before go-live.

---

### 3.2 `Registry::Validator` Is a No-Op

The validator that should catch invalid DSL definitions before they are registered is a stub that always returns `true`:

```ruby
# lib/pg_sql_triggers/registry/validator.rb:7-11
def self.validate!
  # This is a placeholder implementation
  true
end
```

Its test confirms only that it returns `true`. No actual validation (duplicate names, missing table, invalid events, etc.) occurs. Malformed definitions silently pass.

---

## 4. Missing Features

### 4.1 No `FOR EACH ROW` / `FOR EACH STATEMENT` DSL Support

PostgreSQL requires every trigger to specify row-level or statement-level execution. The gem's DSL has no `row_level` or `statement_level` option. The generated SQL presumably hard-codes one, but users have no way to choose.

### 4.2 No Multi-Schema Support

As noted in §2.3, the entire introspection layer is hard-coded to the `public` schema. There is no `schema` DSL option, no configuration for a default schema, and no way to manage triggers in non-public schemas.

### 4.3 No Column-Level Trigger Support (`OF column_name`)

PostgreSQL `UPDATE OF col1, col2` triggers (which fire only when specific columns change) are not representable in the DSL. This is a common performance optimisation for audit triggers.

### 4.4 No Deferred Trigger Support

The DSL provides no way to declare `DEFERRABLE INITIALLY DEFERRED` or `DEFERRABLE INITIALLY IMMEDIATE` triggers, which are essential for some referential integrity patterns.

### 4.5 No `schema.rb` / `structure.sql` Integration

Trigger definitions are managed in a separate `db/triggers/` migration system that is invisible to `rails db:schema:dump`. Restoring a database from `schema.rb` will not recreate triggers. The gem should hook into Rails' structure dump (or document clearly that `structure.sql` must be used and provide a rake task to populate it).

### 4.6 No External Alerting for Drift

Drift detection runs on demand (web UI check or API call) but there is no mechanism to push alerts to Slack, PagerDuty, or email when drift is detected. A cron-triggered rake task with configurable notification hooks would make this production-ready.

### 4.7 No Search or Filter in the Web UI

The dashboard and trigger list pages have no search, filter by table, filter by drift state, or pagination. At scale (many triggers), the UI becomes unwieldy.

### 4.8 No Trigger Dependency or Ordering Declaration

When multiple triggers fire on the same event for the same table, PostgreSQL fires them in alphabetical order by name. There is no DSL primitive to declare intended ordering or express that trigger A must run before trigger B.

### 4.9 No Export / Import of Trigger Definitions

There is no way to export the current state of all triggers to a portable format (JSON, YAML) or import definitions from another project. This makes it hard to migrate or share trigger libraries between applications.

---

## 5. Unnecessary / Over-engineered Features

### 5.1 `SQL::KillSwitch` Is ~1,200 Lines for a Three-Layer Check

The kill switch provides three layers of protection (config, ENV override, confirmation text). The core logic is straightforward, but the module spans over 1,200 lines. Much of this length is verbose logging, repeated helper methods, and defensive checks that could be reduced to ~100 lines without losing functionality. The complexity also means it accounts for 96% of its own test coverage (4% uncovered in a safety-critical module).

### 5.2 SQL Capsules Are a Separate Concern

`SQL::Capsule` and `SQL::Executor` implement a named-SQL-snippet execution system for "emergency operations". This is a useful concept, but it has nothing specifically to do with trigger management — it is a general-purpose dangerous-SQL runner. Bundling it in this gem conflates concerns and increases the attack surface of the gem's web UI.

### 5.3 Web UI Generator Is Code-Generation Against the Principle of Code-First

The `GeneratorController` provides a browser form for generating trigger DSL files and migrations. In practice, triggers are infrastructure — they should be authored in code review, not through a web UI. The UI generator produces files on disk on the server at runtime, which is a security and auditability concern in production environments.

**Recommendation:** Apply options A + C together.

1. **Immediately restrict routes to dev/test** (one-liner, no behaviour change in production):
   ```ruby
   # config/routes.rb
   if Rails.env.development? || Rails.env.test?
     mount PgSqlTriggers::Engine => "/pg_sql_triggers"
   end
   ```

2. **Replace the web generator with a Rails generator** so code generation is a local, CLI-driven action that produces files that go straight into version control:
   ```bash
   rails generate pg_sql_triggers:trigger users after_insert
   ```
   Once the Rails generator exists, the `GeneratorController` routes and views can be removed entirely. This is the idiomatic Rails pattern and eliminates server-side file writes at runtime.

### 5.4 Three Migration Instances Per Migration Run

`Migrator#run_migration` instantiates the migration class three separate times:
1. `validation_instance` — for `SafetyValidator` (which calls `direction` on it)
2. `comparison_instance` — for `PreApplyComparator`
3. `migration_instance` — for actual execution

If either the safety validator or comparator raises a non-`StandardError` or has side effects, the behaviour is unpredictable. A single instance should be captured once for SQL inspection, then a clean instance used for execution.

### 5.5 `enabled` Defaults to `false` in the DSL

The DSL initialises `@enabled = false`, meaning every newly declared trigger is disabled by default. This is a surprising default — users who forget to add `enabled true` will deploy triggers that silently do nothing, with no warning.

```ruby
# lib/pg_sql_triggers/dsl/trigger_definition.rb:12
@enabled = false
```

---

## 6. Low-coverage Hotspots

| File | Coverage | Risk |
|---|---|---|
| `config/routes.rb` | 12% | Route misconfiguration goes undetected |
| `migrations_controller.rb` | 82.76% | Error paths in the most dangerous controller |
| `permission_checking.rb` | 85.37% | Security-critical concern with gaps |
| `testing/function_tester.rb` | 89.71% | Testing utilities that are themselves untested |
| `sql/kill_switch.rb` | 96.04% | Safety mechanism with 4% uncovered paths |

---

## 7. Summary Table

| # | Category | Severity | Description |
|---|---|---|---|
| 1.1 | Bug | **Critical** | Checksum algorithm omits `timing` in drift detector — false drift always reported |
| 1.2 | Bug | **Critical** | `extract_function_body` returns full `CREATE FUNCTION` SQL — checksum never matches |
| 1.3 | Bug | **Critical** | DSL triggers store `"placeholder"` checksum — always shows as DRIFTED |
| 1.4 | Bug | **Critical** | `re_execute!` always raises for DSL triggers — feature is broken for primary use case |
| 1.5 | Bug | **High** | `SafetyValidator` executes migration code as side effect of capture |
| 1.6 | Bug | **Low** | Dead `trigger_name` expression in `drop!` |
| 2.1 | Design | **High** | N+1 queries in all drift state filter methods |
| 2.2 | Design | **High** | Class-level registry cache is not thread-safe |
| 2.3 | Design | **High** | Hard-coded `public` schema — multi-schema apps unsupported |
| 2.4 | Design | **Medium** | `when_env` DSL anti-pattern guarantees env drift |
| 2.5 | Design | **Low** | Duplicate generator namespaces with no guidance |
| 2.6 | Design | **Medium** | Audit state snapshot omits `function_body` |
| 2.7 | Design | **Low** | Non-idiomatic dual-purpose DSL methods |
| 3.1 | Security | **High** | Default permissions allow all actions — no safe default |
| 3.2 | Security | **High** | `Registry::Validator` is a stub that accepts any input |
| 4.1 | Missing | **High** | No `FOR EACH ROW` / `FOR EACH STATEMENT` DSL option |
| 4.2 | Missing | **High** | No multi-schema support |
| 4.3 | Missing | **Medium** | No column-level trigger (`UPDATE OF col`) |
| 4.4 | Missing | **Medium** | No deferred trigger support |
| 4.5 | Missing | **High** | No `schema.rb` / `structure.sql` integration |
| 4.6 | Missing | **Medium** | No external alerting for detected drift |
| 4.7 | Missing | **Low** | No search/filter in web UI |
| 4.8 | Missing | **Low** | No trigger ordering or dependency declaration |
| 4.9 | Missing | **Low** | No export/import of trigger definitions |
| 5.1 | Unnecessary | **Low** | Kill switch is ~1,200 lines for a 3-layer check |
| 5.2 | Unnecessary | **Medium** | SQL Capsules are an unrelated concern bundled in the gem |
| 5.3 | Unnecessary | **Medium** | Web UI generator creates files on production server |
| 5.4 | Unnecessary | **Medium** | Three migration instances per run (safety + compare + execute) |
| 5.5 | Unnecessary | **Medium** | `enabled false` default silently disables triggers in production |
