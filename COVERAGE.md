# Code Coverage Report

**Total Coverage: 96.04%**

Covered: 2499 / 2602 lines

---

## File Coverage

| File | Coverage | Covered Lines | Missed Lines | Total Lines |
|------|----------|---------------|--------------|-------------|
| `lib/pg_sql_triggers/migration.rb` | 100.0% ✅ | 4 | 0 | 4 |
| `lib/pg_sql_triggers/migrator/pre_apply_comparator.rb` | 100.0% ✅ | 125 | 0 | 125 |
| `lib/generators/pg_sql_triggers/install_generator.rb` | 100.0% ✅ | 18 | 0 | 18 |
| `lib/pg_sql_triggers/dsl/trigger_definition.rb` | 100.0% ✅ | 60 | 0 | 60 |
| `lib/pg_sql_triggers/dsl.rb` | 100.0% ✅ | 9 | 0 | 9 |
| `lib/pg_sql_triggers/migrator/pre_apply_diff_reporter.rb` | 100.0% ✅ | 75 | 0 | 75 |
| `lib/pg_sql_triggers/sql.rb` | 100.0% ✅ | 7 | 0 | 7 |
| `lib/pg_sql_triggers/migrator/safety_validator.rb` | 100.0% ✅ | 120 | 0 | 120 |
| `lib/pg_sql_triggers/drift.rb` | 100.0% ✅ | 15 | 0 | 15 |
| `lib/pg_sql_triggers/permissions.rb` | 100.0% ✅ | 11 | 0 | 11 |
| `lib/pg_sql_triggers/permissions/checker.rb` | 100.0% ✅ | 16 | 0 | 16 |
| `app/controllers/pg_sql_triggers/triggers_controller.rb` | 100.0% ✅ | 76 | 0 | 76 |
| `app/helpers/pg_sql_triggers/dashboard_helper.rb` | 100.0% ✅ | 7 | 0 | 7 |
| `app/controllers/pg_sql_triggers/dashboard_controller.rb` | 100.0% ✅ | 72 | 0 | 72 |
| `lib/pg_sql_triggers.rb` | 100.0% ✅ | 51 | 0 | 51 |
| `lib/pg_sql_triggers/errors.rb` | 100.0% ✅ | 83 | 0 | 83 |
| `lib/pg_sql_triggers/testing/dry_run.rb` | 100.0% ✅ | 24 | 0 | 24 |
| `lib/pg_sql_triggers/testing/syntax_validator.rb` | 100.0% ✅ | 58 | 0 | 58 |
| `lib/pg_sql_triggers/testing.rb` | 100.0% ✅ | 6 | 0 | 6 |
| `config/initializers/pg_sql_triggers.rb` | 100.0% ✅ | 10 | 0 | 10 |
| `app/models/pg_sql_triggers/application_record.rb` | 100.0% ✅ | 3 | 0 | 3 |
| `app/models/pg_sql_triggers/audit_log.rb` | 100.0% ✅ | 32 | 0 | 32 |
| `app/controllers/concerns/pg_sql_triggers/error_handling.rb` | 100.0% ✅ | 19 | 0 | 19 |
| `app/controllers/concerns/pg_sql_triggers/kill_switch_protection.rb` | 100.0% ✅ | 17 | 0 | 17 |
| `app/controllers/concerns/pg_sql_triggers/permission_checking.rb` | 100.0% ✅ | 41 | 0 | 41 |
| `app/controllers/pg_sql_triggers/application_controller.rb` | 100.0% ✅ | 13 | 0 | 13 |
| `app/helpers/pg_sql_triggers/permissions_helper.rb` | 100.0% ✅ | 16 | 0 | 16 |
| `app/controllers/pg_sql_triggers/audit_logs_controller.rb` | 100.0% ✅ | 55 | 0 | 55 |
| `app/controllers/pg_sql_triggers/migrations_controller.rb` | 98.82% ✅ | 84 | 1 | 85 |
| `lib/pg_sql_triggers/registry/manager.rb` | 98.81% ✅ | 83 | 1 | 84 |
| `lib/pg_sql_triggers/events_checksum.rb` | 98.33% ✅ | 59 | 1 | 60 |
| `app/models/pg_sql_triggers/trigger_registry.rb` | 97.69% ✅ | 211 | 5 | 216 |
| `lib/pg_sql_triggers/sql/kill_switch.rb` | 96.51% ✅ | 83 | 3 | 86 |
| `lib/generators/pg_sql_triggers/trigger_migration_generator.rb` | 96.3% ✅ | 26 | 1 | 27 |
| `lib/pg_sql_triggers/alerting.rb` | 96.3% ✅ | 26 | 1 | 27 |
| `lib/pg_sql_triggers/drift/db_queries.rb` | 96.15% ✅ | 25 | 1 | 26 |
| `lib/pg_sql_triggers/deferral_checksum.rb` | 96.0% ✅ | 24 | 1 | 25 |
| `lib/pg_sql_triggers/migrator.rb` | 95.78% ✅ | 159 | 7 | 166 |
| `lib/pg_sql_triggers/registry/validator.rb` | 94.83% ✅ | 165 | 9 | 174 |
| `lib/pg_sql_triggers/database_introspection.rb` | 94.29% ✅ | 66 | 4 | 70 |
| `lib/pg_sql_triggers/drift/reporter.rb` | 94.12% ✅ | 96 | 6 | 102 |
| `lib/pg_sql_triggers/drift/detector.rb` | 92.5% ✅ | 74 | 6 | 80 |
| `lib/pg_sql_triggers/testing/safe_executor.rb` | 91.89% ✅ | 34 | 3 | 37 |
| `lib/pg_sql_triggers/registry.rb` | 91.84% ✅ | 45 | 4 | 49 |
| `lib/pg_sql_triggers/trigger_structure_dumper.rb` | 90.32% ✅ | 56 | 6 | 62 |
| `lib/pg_sql_triggers/testing/function_tester.rb` | 88.31% ⚠️ | 68 | 9 | 77 |
| `app/controllers/pg_sql_triggers/tables_controller.rb` | 83.78% ⚠️ | 31 | 6 | 37 |
| `lib/pg_sql_triggers/schema_dumper_extension.rb` | 73.33% ⚠️ | 11 | 4 | 15 |
| `lib/pg_sql_triggers/engine.rb` | 72.97% ⚠️ | 27 | 10 | 37 |
| `config/routes.rb` | 17.65% ❌ | 3 | 14 | 17 |

---

*Report generated automatically from SimpleCov results*
*To regenerate: Run `bundle exec rspec` and then `ruby scripts/generate_coverage_report.rb`*
