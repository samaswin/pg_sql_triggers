# Code Coverage Report

**Total Coverage: 93.02%**

Covered: 2239 / 2407 lines

---

## File Coverage

| File | Coverage | Covered Lines | Missed Lines | Total Lines |
|------|----------|---------------|--------------|-------------|
| `lib/pg_sql_triggers/drift.rb` | 100.0% ✅ | 13 | 0 | 13 |
| `lib/pg_sql_triggers/drift/db_queries.rb` | 100.0% ✅ | 24 | 0 | 24 |
| `lib/pg_sql_triggers/dsl.rb` | 100.0% ✅ | 9 | 0 | 9 |
| `lib/pg_sql_triggers/dsl/trigger_definition.rb` | 100.0% ✅ | 37 | 0 | 37 |
| `lib/pg_sql_triggers/generator.rb` | 100.0% ✅ | 4 | 0 | 4 |
| `lib/pg_sql_triggers/generator/form.rb` | 100.0% ✅ | 36 | 0 | 36 |
| `lib/pg_sql_triggers/generator/service.rb` | 100.0% ✅ | 101 | 0 | 101 |
| `lib/generators/pg_sql_triggers/install_generator.rb` | 100.0% ✅ | 18 | 0 | 18 |
| `lib/generators/trigger/migration_generator.rb` | 100.0% ✅ | 27 | 0 | 27 |
| `lib/pg_sql_triggers/migration.rb` | 100.0% ✅ | 4 | 0 | 4 |
| `lib/pg_sql_triggers/migrator/pre_apply_diff_reporter.rb` | 100.0% ✅ | 75 | 0 | 75 |
| `lib/pg_sql_triggers/migrator/safety_validator.rb` | 100.0% ✅ | 110 | 0 | 110 |
| `lib/pg_sql_triggers/permissions.rb` | 100.0% ✅ | 11 | 0 | 11 |
| `lib/pg_sql_triggers/permissions/checker.rb` | 100.0% ✅ | 17 | 0 | 17 |
| `lib/pg_sql_triggers/registry/validator.rb` | 100.0% ✅ | 5 | 0 | 5 |
| `lib/pg_sql_triggers/sql/capsule.rb` | 100.0% ✅ | 28 | 0 | 28 |
| `lib/pg_sql_triggers/sql/executor.rb` | 100.0% ✅ | 63 | 0 | 63 |
| `lib/pg_sql_triggers/testing.rb` | 100.0% ✅ | 6 | 0 | 6 |
| `lib/pg_sql_triggers/testing/syntax_validator.rb` | 100.0% ✅ | 58 | 0 | 58 |
| `lib/pg_sql_triggers/testing/dry_run.rb` | 100.0% ✅ | 24 | 0 | 24 |
| `app/controllers/concerns/pg_sql_triggers/kill_switch_protection.rb` | 100.0% ✅ | 17 | 0 | 17 |
| `app/models/pg_sql_triggers/audit_log.rb` | 100.0% ✅ | 28 | 0 | 28 |
| `app/controllers/pg_sql_triggers/application_controller.rb` | 100.0% ✅ | 13 | 0 | 13 |
| `app/controllers/pg_sql_triggers/audit_logs_controller.rb` | 100.0% ✅ | 47 | 0 | 47 |
| `app/controllers/pg_sql_triggers/dashboard_controller.rb` | 100.0% ✅ | 27 | 0 | 27 |
| `app/models/pg_sql_triggers/application_record.rb` | 100.0% ✅ | 3 | 0 | 3 |
| `config/initializers/pg_sql_triggers.rb` | 100.0% ✅ | 10 | 0 | 10 |
| `app/controllers/pg_sql_triggers/triggers_controller.rb` | 100.0% ✅ | 75 | 0 | 75 |
| `lib/pg_sql_triggers.rb` | 100.0% ✅ | 40 | 0 | 40 |
| `lib/pg_sql_triggers/migrator/pre_apply_comparator.rb` | 99.19% ✅ | 122 | 1 | 123 |
| `lib/pg_sql_triggers/drift/detector.rb` | 98.48% ✅ | 65 | 1 | 66 |
| `app/controllers/pg_sql_triggers/sql_capsules_controller.rb` | 97.14% ✅ | 68 | 2 | 70 |
| `lib/generators/pg_sql_triggers/trigger_migration_generator.rb` | 96.3% ✅ | 26 | 1 | 27 |
| `lib/pg_sql_triggers/sql/kill_switch.rb` | 96.04% ✅ | 97 | 4 | 101 |
| `lib/pg_sql_triggers/migrator.rb` | 95.42% ✅ | 125 | 6 | 131 |
| `lib/pg_sql_triggers/registry/manager.rb` | 95.08% ✅ | 58 | 3 | 61 |
| `app/controllers/pg_sql_triggers/tables_controller.rb` | 94.74% ✅ | 18 | 1 | 19 |
| `lib/pg_sql_triggers/database_introspection.rb` | 94.29% ✅ | 66 | 4 | 70 |
| `lib/pg_sql_triggers/drift/reporter.rb` | 94.12% ✅ | 96 | 6 | 102 |
| `lib/pg_sql_triggers/engine.rb` | 92.86% ✅ | 13 | 1 | 14 |
| `lib/pg_sql_triggers/testing/safe_executor.rb` | 91.89% ✅ | 34 | 3 | 37 |
| `lib/pg_sql_triggers/registry.rb` | 91.84% ✅ | 45 | 4 | 49 |
| `app/controllers/pg_sql_triggers/generator_controller.rb` | 91.49% ✅ | 86 | 8 | 94 |
| `lib/pg_sql_triggers/sql.rb` | 90.91% ✅ | 10 | 1 | 11 |
| `lib/pg_sql_triggers/testing/function_tester.rb` | 89.55% ⚠️ | 60 | 7 | 67 |
| `app/models/pg_sql_triggers/trigger_registry.rb` | 88.44% ⚠️ | 153 | 20 | 173 |
| `app/controllers/pg_sql_triggers/migrations_controller.rb` | 82.76% ⚠️ | 72 | 15 | 87 |
| `app/controllers/concerns/pg_sql_triggers/permission_checking.rb` | 75.0% ⚠️ | 24 | 8 | 32 |
| `lib/pg_sql_triggers/errors.rb` | 62.65% ❌ | 52 | 31 | 83 |
| `app/helpers/pg_sql_triggers/permissions_helper.rb` | 56.25% ❌ | 9 | 7 | 16 |
| `app/controllers/concerns/pg_sql_triggers/error_handling.rb` | 36.84% ❌ | 7 | 12 | 19 |
| `config/routes.rb` | 12.0% ❌ | 3 | 22 | 25 |

---

*Report generated automatically from SimpleCov results*
*To regenerate: Run `bundle exec rspec` and then `ruby scripts/generate_coverage_report.rb`*
