# Code Coverage Report

**Total Coverage: 94.9%**

Covered: 1989 / 2096 lines

---

## File Coverage

| File | Coverage | Covered Lines | Missed Lines | Total Lines |
|------|----------|---------------|--------------|-------------|
| `lib/pg_sql_triggers/testing/dry_run.rb` | 100.0% ✅ | 24 | 0 | 24 |
| `lib/pg_sql_triggers/testing/syntax_validator.rb` | 100.0% ✅ | 58 | 0 | 58 |
| `lib/pg_sql_triggers/testing.rb` | 100.0% ✅ | 6 | 0 | 6 |
| `lib/pg_sql_triggers/sql.rb` | 100.0% ✅ | 7 | 0 | 7 |
| `lib/pg_sql_triggers/registry/validator.rb` | 100.0% ✅ | 39 | 0 | 39 |
| `lib/pg_sql_triggers/permissions/checker.rb` | 100.0% ✅ | 17 | 0 | 17 |
| `lib/pg_sql_triggers/permissions.rb` | 100.0% ✅ | 11 | 0 | 11 |
| `lib/pg_sql_triggers/migrator/pre_apply_diff_reporter.rb` | 100.0% ✅ | 75 | 0 | 75 |
| `lib/pg_sql_triggers/migrator/pre_apply_comparator.rb` | 100.0% ✅ | 123 | 0 | 123 |
| `lib/pg_sql_triggers/migration.rb` | 100.0% ✅ | 4 | 0 | 4 |
| `lib/generators/pg_sql_triggers/install_generator.rb` | 100.0% ✅ | 18 | 0 | 18 |
| `lib/pg_sql_triggers/dsl/trigger_definition.rb` | 100.0% ✅ | 34 | 0 | 34 |
| `lib/pg_sql_triggers/dsl.rb` | 100.0% ✅ | 9 | 0 | 9 |
| `lib/pg_sql_triggers/drift.rb` | 100.0% ✅ | 13 | 0 | 13 |
| `app/controllers/pg_sql_triggers/triggers_controller.rb` | 100.0% ✅ | 75 | 0 | 75 |
| `lib/pg_sql_triggers.rb` | 100.0% ✅ | 41 | 0 | 41 |
| `config/initializers/pg_sql_triggers.rb` | 100.0% ✅ | 10 | 0 | 10 |
| `app/controllers/pg_sql_triggers/dashboard_controller.rb` | 100.0% ✅ | 26 | 0 | 26 |
| `app/models/pg_sql_triggers/application_record.rb` | 100.0% ✅ | 3 | 0 | 3 |
| `app/models/pg_sql_triggers/audit_log.rb` | 100.0% ✅ | 28 | 0 | 28 |
| `app/helpers/pg_sql_triggers/permissions_helper.rb` | 100.0% ✅ | 16 | 0 | 16 |
| `app/controllers/pg_sql_triggers/application_controller.rb` | 100.0% ✅ | 13 | 0 | 13 |
| `lib/pg_sql_triggers/errors.rb` | 100.0% ✅ | 83 | 0 | 83 |
| `app/controllers/concerns/pg_sql_triggers/error_handling.rb` | 100.0% ✅ | 19 | 0 | 19 |
| `app/controllers/concerns/pg_sql_triggers/kill_switch_protection.rb` | 100.0% ✅ | 17 | 0 | 17 |
| `lib/pg_sql_triggers/registry/manager.rb` | 98.68% ✅ | 75 | 1 | 76 |
| `lib/pg_sql_triggers/migrator/safety_validator.rb` | 98.33% ✅ | 118 | 2 | 120 |
| `app/controllers/pg_sql_triggers/audit_logs_controller.rb` | 97.73% ✅ | 43 | 1 | 44 |
| `lib/pg_sql_triggers/sql/kill_switch.rb` | 96.51% ✅ | 83 | 3 | 86 |
| `lib/generators/pg_sql_triggers/trigger_migration_generator.rb` | 96.3% ✅ | 26 | 1 | 27 |
| `lib/pg_sql_triggers/drift/db_queries.rb` | 96.15% ✅ | 25 | 1 | 26 |
| `lib/pg_sql_triggers/database_introspection.rb` | 94.29% ✅ | 66 | 4 | 70 |
| `lib/pg_sql_triggers/drift/reporter.rb` | 94.12% ✅ | 96 | 6 | 102 |
| `lib/pg_sql_triggers/drift/detector.rb` | 92.31% ✅ | 72 | 6 | 78 |
| `lib/pg_sql_triggers/migrator.rb` | 92.11% ✅ | 140 | 12 | 152 |
| `app/models/pg_sql_triggers/trigger_registry.rb` | 91.92% ✅ | 182 | 16 | 198 |
| `lib/pg_sql_triggers/testing/safe_executor.rb` | 91.89% ✅ | 34 | 3 | 37 |
| `lib/pg_sql_triggers/registry.rb` | 91.84% ✅ | 45 | 4 | 49 |
| `app/controllers/pg_sql_triggers/tables_controller.rb` | 90.63% ✅ | 29 | 3 | 32 |
| `lib/pg_sql_triggers/testing/function_tester.rb` | 89.71% ⚠️ | 61 | 7 | 68 |
| `lib/pg_sql_triggers/engine.rb` | 88.24% ⚠️ | 15 | 2 | 17 |
| `app/controllers/concerns/pg_sql_triggers/permission_checking.rb` | 85.37% ⚠️ | 35 | 6 | 41 |
| `app/controllers/pg_sql_triggers/migrations_controller.rb` | 82.76% ⚠️ | 72 | 15 | 87 |
| `config/routes.rb` | 17.65% ❌ | 3 | 14 | 17 |

---

*Report generated automatically from SimpleCov results*
*To regenerate: Run `bundle exec rspec` and then `ruby scripts/generate_coverage_report.rb`*
