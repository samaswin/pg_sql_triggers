# Audit Trail Guide

PgSqlTriggers provides comprehensive audit logging for all trigger operations. This guide explains how to view, filter, and export audit logs.

## Table of Contents

- [Overview](#overview)
- [Accessing Audit Logs](#accessing-audit-logs)
- [Viewing Audit Logs](#viewing-audit-logs)
- [Filtering Logs](#filtering-logs)
- [Exporting Logs](#exporting-logs)
- [Console API](#console-api)
- [Logged Operations](#logged-operations)
- [Audit Log Structure](#audit-log-structure)

## Overview

The audit trail captures:

- **Who**: Actor information (user type and ID)
- **What**: Operation performed (enable, disable, drop, re-execute, etc.)
- **When**: Timestamp of the operation
- **Where**: Environment where operation occurred
- **Result**: Success or failure status
- **Context**: Before/after state, reasons, confirmation text, error messages

All operations are automatically logged, providing a complete audit trail for compliance and debugging.

## Accessing Audit Logs

### Via Web UI

Navigate to the Audit Log page:

1. Go to the PgSqlTriggers dashboard
2. Click "Audit Log" in the navigation menu
3. URL: `http://localhost:3000/pg_sql_triggers/audit_logs`

### Via Console API

```ruby
# Get all audit logs
PgSqlTriggers::AuditLog.all

# Get logs for a specific trigger
PgSqlTriggers::AuditLog.for_trigger_name("users_email_validation")

# Get recent logs
PgSqlTriggers::AuditLog.recent.limit(100)
```

## Viewing Audit Logs

### Audit Log Table

The audit log table displays:

- **Timestamp**: When the operation occurred
- **Operation**: Type of operation (enable, disable, drop, etc.)
- **Trigger Name**: Affected trigger (if applicable)
- **Actor**: Who performed the operation (type and ID)
- **Environment**: Environment where operation occurred
- **Status**: Success or failure
- **Reason**: Reason provided (for drop/re-execute operations)

### Viewing Details

Click on any audit log entry to view detailed information:

- **Before State**: State before the operation (enabled/disabled, function body, etc.)
- **After State**: State after the operation
- **Diff**: Changes made (for re-execute operations)
- **Confirmation Text**: Confirmation text used (if applicable)
- **Error Message**: Error details (for failed operations)

## Filtering Logs

### Filter Options

Filter audit logs by:

- **Trigger Name**: Filter by specific trigger
- **Operation**: Filter by operation type (enable, disable, drop, etc.)
- **Status**: Filter by success or failure
- **Environment**: Filter by environment (production, staging, etc.)
- **Sort Order**: Newest first or oldest first

### Using Filters in UI

1. Navigate to Audit Log page
2. Use filter dropdowns at the top
3. Click "Apply Filters"
4. Use "Clear" to reset filters

### Filtering via Console API

```ruby
# Filter by trigger
PgSqlTriggers::AuditLog.for_trigger("users_email_validation")

# Filter by operation
PgSqlTriggers::AuditLog.for_operation("trigger_enable")

# Filter by environment
PgSqlTriggers::AuditLog.for_environment("production")

# Filter by status
PgSqlTriggers::AuditLog.successful
PgSqlTriggers::AuditLog.failed

# Combine filters
PgSqlTriggers::AuditLog
  .for_trigger("users_email_validation")
  .for_operation("trigger_enable")
  .successful
  .recent
  .limit(50)
```

### Advanced Filtering

```ruby
# Get failed operations in production
PgSqlTriggers::AuditLog
  .for_environment("production")
  .failed
  .recent

# Get all drop operations
PgSqlTriggers::AuditLog
  .for_operation("trigger_drop")
  .includes(:trigger_name)

# Get operations by specific actor
PgSqlTriggers::AuditLog
  .where("actor->>'type' = ? AND actor->>'id' = ?", "User", "123")
```

## Exporting Logs

### CSV Export via UI

1. Apply any desired filters
2. Click "Export CSV" button
3. CSV file downloads with all visible entries
4. Filters are preserved in the export

### CSV Export Format

The CSV includes all columns:

- Timestamp
- Operation
- Trigger Name
- Actor Type
- Actor ID
- Environment
- Status
- Reason
- Error Message (for failures)
- Created At

### Programmatic Export

```ruby
# Export to CSV
require 'csv'

logs = PgSqlTriggers::AuditLog.recent.limit(1000)

CSV.open("audit_logs.csv", "w") do |csv|
  csv << ["Timestamp", "Operation", "Trigger", "Actor", "Environment", "Status", "Reason"]
  
  logs.each do |log|
    csv << [
      log.created_at,
      log.operation,
      log.trigger_name,
      "#{log.actor['type']}:#{log.actor['id']}",
      log.environment,
      log.status,
      log.reason
    ]
  end
end
```

## Console API

### Querying Audit Logs

```ruby
# Get logs for a trigger
PgSqlTriggers::AuditLog.for_trigger_name("users_email_validation")

# Returns: ActiveRecord::Relation ordered by most recent first
```

### Logging Operations

Operations are automatically logged, but you can also log manually:

```ruby
# Log a successful operation
PgSqlTriggers::AuditLog.log_success(
  operation: :trigger_enable,
  trigger_name: "users_email_validation",
  actor: { type: "Console", id: "admin@example.com" },
  environment: "production",
  before_state: { enabled: false },
  after_state: { enabled: true }
)

# Log a failed operation
PgSqlTriggers::AuditLog.log_failure(
  operation: :trigger_drop,
  trigger_name: "old_trigger",
  actor: { type: "UI", id: "user_123" },
  environment: "production",
  error_message: "Trigger not found",
  reason: "Cleanup"
)
```

## Logged Operations

The following operations are automatically logged:

### Trigger Operations

- **`trigger_enable`**: Trigger enabled
- **`trigger_disable`**: Trigger disabled
- **`trigger_drop`**: Trigger dropped from database
- **`trigger_re_execute`**: Trigger re-executed (drop and recreate)

### Migration Operations

- **`migration_up`**: Migration applied (up)
- **`migration_down`**: Migration rolled back (down)

### SQL Capsule Operations

- **`sql_capsule_execute`**: SQL capsule executed
- **`sql_capsule_dry_run`**: SQL capsule dry-run performed

### Generator Operations

- **`trigger_generate`**: Trigger generated via UI

## Audit Log Structure

### Database Schema

The audit log table (`pg_sql_triggers_audit_log`) contains:

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Primary key |
| `trigger_name` | string | Trigger name (nullable) |
| `operation` | string | Operation type |
| `actor` | jsonb | Actor information (type, id) |
| `environment` | string | Environment name |
| `status` | string | "success" or "failure" |
| `reason` | text | Reason for operation (nullable) |
| `confirmation_text` | text | Confirmation text used (nullable) |
| `before_state` | jsonb | State before operation (nullable) |
| `after_state` | jsonb | State after operation (nullable) |
| `diff` | text | Diff information (nullable) |
| `error_message` | text | Error message (for failures) |
| `created_at` | timestamp | When operation occurred |
| `updated_at` | timestamp | Last update time |

### Actor Format

Actor information is stored as JSON:

```json
{
  "type": "User",
  "id": "123"
}
```

Or for console operations:

```json
{
  "type": "Console",
  "id": "admin@example.com"
}
```

### State Format

Before and after states are stored as JSON:

```json
{
  "enabled": true,
  "function_body": "CREATE FUNCTION...",
  "version": 1,
  "drift_state": "in_sync"
}
```

## Use Cases

### Compliance Auditing

Track who performed what operations for compliance:

```ruby
# Get all admin operations in production
PgSqlTriggers::AuditLog
  .for_environment("production")
  .where("actor->>'type' = ?", "Admin")
  .recent
```

### Debugging Failed Operations

Find and analyze failed operations:

```ruby
# Get recent failures
failures = PgSqlTriggers::AuditLog.failed.recent.limit(50)

failures.each do |log|
  puts "#{log.created_at}: #{log.operation} on #{log.trigger_name}"
  puts "Error: #{log.error_message}"
  puts "Actor: #{log.actor}"
  puts "---"
end
```

### Trigger History

View complete history of a trigger:

```ruby
history = PgSqlTriggers::AuditLog.for_trigger_name("users_email_validation")

history.each do |log|
  puts "#{log.created_at}: #{log.operation} - #{log.status}"
  if log.reason
    puts "  Reason: #{log.reason}"
  end
end
```

### Operation Analysis

Analyze operation patterns:

```ruby
# Count operations by type
PgSqlTriggers::AuditLog
  .group(:operation)
  .count

# Count failures by operation
PgSqlTriggers::AuditLog
  .failed
  .group(:operation)
  .count

# Operations by environment
PgSqlTriggers::AuditLog
  .group(:environment)
  .count
```

## Best Practices

1. **Regular Reviews**: Review audit logs regularly for anomalies
2. **Retention Policy**: Implement a retention policy for old logs
3. **Monitoring**: Set up alerts for failed operations
4. **Backup**: Include audit logs in your backup strategy
5. **Analysis**: Use audit logs to understand usage patterns

## Troubleshooting

### Audit logs not appearing

**Problem**: Operations are not being logged.

**Solution**: 
- Check that migrations are run (`rails db:migrate`). The audit log table is created by `20260103114508_create_pg_sql_triggers_audit_log.rb` (see [Gem schema migrations](getting-started.md#gem-schema-migrations)).
- Verify the audit log table exists
- Check Rails logs for audit logging errors

### Performance issues with large logs

**Problem**: Audit log queries are slow.

**Solution**:
- Add indexes on frequently queried columns
- Implement pagination
- Archive old logs regularly
- Use filtering to reduce result set size

### Missing actor information

**Problem**: Actor shows as "unknown".

**Solution**: Ensure `current_actor` method is properly implemented in your controllers.

## Related Documentation

- [Web UI Guide](web-ui.md#audit-log) - Using the audit log UI
- [API Reference](api-reference.md#audit-log-api) - Console API methods
- [Configuration Reference](configuration.md) - Configuration options

