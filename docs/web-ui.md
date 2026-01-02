# Web UI Documentation

The PgSqlTriggers web interface provides a visual dashboard for managing triggers, migrations, and monitoring drift status.

## Table of Contents

- [Accessing the Web UI](#accessing-the-web-ui)
- [Dashboard Overview](#dashboard-overview)
- [Managing Triggers](#managing-triggers)
- [Migration Management](#migration-management)
- [SQL Capsules](#sql-capsules)
- [Permissions and Safety](#permissions-and-safety)

## Accessing the Web UI

By default, the web UI is mounted at:

```
http://localhost:3000/pg_sql_triggers
```

You can customize the mount path in your routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount PgSqlTriggers::Engine, at: "/admin/triggers"  # Custom path
end
```

## Dashboard Overview

The dashboard provides a comprehensive view of your trigger ecosystem.

### Main Features

1. **Trigger List**: View all triggers with their current status
2. **Drift Detection**: Visual indicators for drift states
3. **Migration Status**: See pending and applied migrations
4. **Quick Actions**: Enable/disable triggers, run migrations
5. **Kill Switch Status**: Production environment indicator

![Dashboard Screenshot](screenshots/dashboard.png)

### Status Indicators

- **✓ Green**: Managed & In Sync
- **⚠ Yellow**: Drifted or Manual Override
- **✗ Red**: Dropped or Error
- **○ Gray**: Disabled
- **? Purple**: Unknown

## Managing Triggers

### Viewing Trigger Details

Click on any trigger to view:
- Current status and drift state
- Table and function information
- Version history
- Enabled/disabled state
- Environment configuration

### Enabling/Disabling Triggers

#### Enable a Trigger

1. Navigate to the trigger in the dashboard
2. Click the "Enable" button
3. In production environments, enter the confirmation text when prompted
4. Confirm the action

#### Disable a Trigger

1. Navigate to the trigger in the dashboard
2. Click the "Disable" button
3. In production environments, enter the confirmation text when prompted
4. Confirm the action

### Viewing Drift Status

The dashboard automatically shows drift status for each trigger:

- **In Sync**: Green checkmark, no action needed
- **Drifted**: Yellow warning, shows differences between DSL and database
- **Manual Override**: Yellow warning, indicates changes made outside PgSqlTriggers
- **Dropped**: Red X, trigger removed from database but still in registry

### Trigger Actions

Available actions depend on trigger state and your permissions:

- **Enable/Disable**: Toggle trigger activation
- **Apply**: Apply generated trigger definition
- **Drop**: Remove trigger from database (Admin only)
- **Re-Execute**: Drop and recreate trigger from registry definition (Admin only)
- **View SQL**: See the trigger's SQL definition
- **View Diff**: Compare DSL vs database state

### Drop Trigger

The drop action permanently removes a trigger from the database and registry.

1. Navigate to the trigger detail page
2. Click the "Drop Trigger" button
3. A modal will appear requiring:
   - **Reason**: Explanation for dropping the trigger (required for audit trail)
   - **Confirmation**: In protected environments, type the exact confirmation text shown
4. Review the warning message
5. Click "Drop Trigger" to confirm

**Important Notes**:
- This action is **irreversible** - the trigger will be permanently removed
- Requires **Admin** permission level
- Protected by kill switch in production environments
- Reason is logged for compliance and audit purposes
- The trigger is removed from both the database and the registry

### Re-Execute Trigger

The re-execute action fixes drifted triggers by dropping and recreating them from the registry definition.

1. Navigate to the trigger detail page
2. If the trigger is drifted, you'll see a drift warning
3. Click the "Re-Execute" button
4. A modal will appear showing:
   - **Drift Comparison**: Differences between database state and registry definition
   - **Reason Field**: Explanation for re-executing (required for audit trail)
   - **Confirmation**: In protected environments, type the exact confirmation text shown
5. Review the drift differences to understand what will change
6. Click "Re-Execute Trigger" to confirm

**What Happens**:
1. Current trigger is dropped from the database
2. New trigger is created using the registry definition (function_body, events, timing, condition)
3. Registry is updated with execution timestamp
4. Operation is logged with reason and actor information

**Important Notes**:
- Requires **Admin** permission level
- Protected by kill switch in production environments
- Reason is logged for compliance and audit purposes
- Executes in a database transaction (rolls back on error)
- Best used to fix triggers that have drifted from their DSL definition

## Migration Management

The Web UI provides full migration management capabilities.

### Migration Status View

Navigate to the "Migrations" tab to see:

- **Pending Migrations**: Not yet applied (down state)
- **Applied Migrations**: Successfully run (up state)
- **Migration Details**: Timestamp, name, and status

### Applying Migrations

#### Apply All Pending Migrations

1. Click "Apply All Pending Migrations" button
2. Review the list of migrations to be applied
3. In production, enter confirmation text: `EXECUTE UI_MIGRATION_UP`
4. Confirm the action
5. Wait for completion and review results

#### Apply Individual Migration

1. Find the migration in the status table
2. Click the "Up" button next to the migration
3. In production, enter confirmation text
4. Confirm the action

### Rolling Back Migrations

#### Rollback Last Migration

1. Click "Rollback Last Migration" button
2. Review which migration will be rolled back
3. In production, enter confirmation text: `EXECUTE UI_MIGRATION_DOWN`
4. Confirm the action

#### Rollback Individual Migration

1. Find the migration in the status table
2. Click the "Down" button next to the migration
3. In production, enter confirmation text
4. Confirm the action

### Redo Migrations

Redo (rollback and re-apply) a migration:

1. Click "Redo Last Migration" for the most recent migration
2. Or click "Redo" button next to a specific migration
3. In production, enter confirmation text: `EXECUTE UI_MIGRATION_REDO`
4. Confirm the action

### Migration Feedback

After each migration action:
- **Success**: Green flash message with details
- **Error**: Red flash message with error details
- **Warnings**: Yellow flash message if issues occurred

## SQL Capsules

SQL Capsules provide emergency escape hatches for executing SQL directly with comprehensive safety checks and audit logging.

### When to Use SQL Capsules

Use SQL Capsules for:
- Emergency fixes in production
- Critical data corrections
- Testing SQL functions
- Debugging trigger behavior
- One-off database operations

### Creating and Executing SQL Capsules

1. Navigate to "SQL Capsules" → "New SQL Capsule"
2. Fill in the capsule form:
   - **Name**: Unique identifier (alphanumeric, underscores, hyphens only)
   - **Environment**: Target environment (e.g., production, staging)
   - **Purpose**: Detailed explanation of what the SQL does and why (required for audit trail)
   - **SQL**: The SQL statement(s) to execute
3. Click "Create and Execute" or "Save for Later"
4. Review the capsule details on the confirmation page
5. In protected environments, enter confirmation text when prompted
6. Click "Execute" to run the SQL
7. Review the execution results

### Viewing Capsule History

1. Navigate to "SQL Capsules" → "History"
2. View list of previously executed capsules with:
   - Name and purpose
   - Environment and timestamp
   - SQL checksum
   - Execution status
3. Click on a capsule to view details
4. Re-execute historical capsules if needed

### Safety Features

- **Admin Permission Required**: Only Admin users can create and execute SQL capsules
- **Production Protection**: Requires typed confirmation in protected environments
- **Kill Switch Integration**: All executions are protected by kill switch
- **Comprehensive Logging**: All operations logged with actor, timestamp, and checksum
- **Transactional Execution**: SQL runs in a transaction and rolls back on error
- **Registry Storage**: All capsules are stored in the registry with checksums
- **Purpose Tracking**: Required purpose field ensures all executions are documented

### Example SQL Capsules

#### View All Triggers
```sql
SELECT
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'public';
```

#### Check Function Definitions
```sql
SELECT
  routine_name,
  routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE '%trigger%';
```

#### Verify Trigger State
```sql
SELECT * FROM pg_sql_triggers_registry
WHERE trigger_name = 'users_email_validation';
```

## Permissions and Safety

### Permission Levels

The Web UI enforces three permission levels:

#### Viewer (Read-Only)
- View triggers and their status
- View drift information
- Check migration status
- View SQL definitions

Cannot:
- Enable/disable triggers
- Run migrations
- Execute SQL
- Drop triggers

#### Operator
- All Viewer permissions
- Enable/disable triggers
- Apply generated triggers
- Run migrations (up/down/redo)

Cannot:
- Drop triggers
- Execute arbitrary SQL

#### Admin (Full Access)
- All Operator permissions
- Drop triggers
- Execute SQL via capsules
- Modify registry directly

### Kill Switch Protection

In protected environments (production, staging), the Web UI enforces additional safety:

1. **Status Indicator**: Kill switch badge shows protection status
2. **Confirmation Required**: Dangerous operations require typed confirmation
3. **Warning Banners**: Visual alerts for production environment
4. **Audit Logging**: All protected operations are logged

### Configuring Permissions

Set up custom permission checking in the initializer:

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  config.permission_checker = ->(actor, action, environment) {
    user = User.find(actor[:id])

    case action
    when :view
      user.present?
    when :operate
      user.admin? || user.operator?
    when :admin
      user.admin?
    else
      false
    end
  }
end
```

## Screenshots

### Main Dashboard
![Main Dashboard](screenshots/dashboard.png)

### Trigger Generator

The trigger generator provides a comprehensive form for creating triggers:

1. **Basic Information**: Trigger name, table name, function name, and function body
2. **Trigger Events**: Select timing (BEFORE/AFTER) and events (INSERT, UPDATE, DELETE, TRUNCATE)
3. **Configuration**: Version, environments, WHEN condition, and enabled state
4. **Preview**: Review generated DSL and migration code with timing and condition information

The preview page displays:
- Generated DSL code with timing
- Trigger configuration summary (timing, events, table, function, condition)
- PL/pgSQL function body (editable)
- SQL validation results

![Trigger Generator](screenshots/generator.png)

### Migration Management
![Migration Management](screenshots/migrations.png)

### Kill Switch Protection
![Kill Switch](screenshots/kill-switch.png)

### SQL Capsules
![SQL Capsules](screenshots/sql-capsules.png)

## Tips and Best Practices

1. **Check Status Regularly**: Monitor drift detection to catch unexpected changes
2. **Use Confirmations**: Don't bypass production confirmations without understanding the impact
3. **Test in Development**: Always test UI actions in development before production
4. **Review Logs**: Check application logs after important operations
5. **Document Changes**: Add comments when making manual changes via SQL Capsules

## Troubleshooting

### UI Not Accessible

Check that:
1. The engine is mounted in routes
2. Your database migrations are up to date
3. The registry table exists

### Permission Denied

Verify:
1. Your permission checker is configured correctly
2. Your user has the required permission level
3. The kill switch isn't blocking your operation

### Migration Failures

If migrations fail:
1. Check the error message in the flash notification
2. Review the migration SQL in `db/triggers/`
3. Test the SQL in a console first
4. Check database logs for detailed error information

## Next Steps

- [Kill Switch Documentation](kill-switch.md) - Understand production safety
- [Configuration](configuration.md) - Customize UI behavior
- [API Reference](api-reference.md) - Programmatic access
