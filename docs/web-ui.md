# Web UI Documentation

The PgSqlTriggers web interface provides a visual dashboard for managing triggers, migrations, and monitoring drift status.

## Table of Contents

- [Accessing the Web UI](#accessing-the-web-ui)
- [Dashboard Overview](#dashboard-overview)
- [Managing Triggers](#managing-triggers)
- [Migration Management](#migration-management)
- [SQL Capsules](#sql-capsules)
- [Audit Log](#audit-log)
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

1. **Trigger List**: View all triggers with their current status and "Last Applied" timestamps
2. **Drift Detection**: Visual indicators for drift states
3. **Migration Status**: See pending and applied migrations
4. **Quick Actions**: Enable/disable triggers, drop/re-execute triggers (based on permissions), run migrations
5. **Kill Switch Status**: Production environment indicator
6. **Audit Trail**: All operations are logged with actor information and viewable via Audit Log UI

![Dashboard Screenshot](screenshots/dashboard.png)

### Status Indicators

- **✓ Green**: Managed & In Sync
- **⚠ Yellow**: Drifted or Manual Override
- **✗ Red**: Dropped or Error
- **○ Gray**: Disabled
- **? Purple**: Unknown

## Database Tables & Triggers

The Database Tables & Triggers page provides a comprehensive view of all tables in your database and their associated triggers. This page helps you understand which tables have triggers and which don't, making it easier to manage your trigger ecosystem.

### Accessing the Tables Page

1. Click "View Tables" from the dashboard
2. Or navigate directly to `/pg_sql_triggers/tables`

### Statistics Overview

The page displays three key statistics:
- **Tables with Triggers**: Count of tables that have at least one trigger
- **Tables without Triggers**: Count of tables that have no triggers
- **Total Tables**: Total count of all tables in the database

### Filtering Tables

Use the filter controls to view different subsets of tables:
- **All Tables**: Shows all tables regardless of trigger status
- **With Triggers**: Shows only tables that have at least one trigger (default)
- **Without Triggers**: Shows only tables that have no triggers

The active filter is highlighted with a colored background. Click any filter button to switch views.

### Pagination

When you have many tables, the list is paginated for better performance:
- **Default**: 20 tables per page
- **Configurable**: Choose 10, 20, 50, or 100 tables per page
- **Navigation**: Use Previous/Next buttons to move between pages
- **Filter Preservation**: Your selected filter is preserved when navigating pages

### Table Information

Each table row displays:
- **Table Name**: The name of the database table
- **Trigger Count**: Number of triggers on the table (badge indicator)
- **Trigger Names & Functions**: List of all triggers with their function names
  - Registry triggers (blue border) - Triggers managed by pg_sql_triggers
  - Database-only triggers (yellow border) - Triggers not in the registry
- **Status**: Summary of enabled/disabled triggers
- **Actions**: 
  - "View Details" - Navigate to the table detail page
  - "Create Trigger" - Generate a new trigger for this table

### Table Detail Page

Click "View Details" on any table to see:
- **Table Columns**: Complete list of columns with data types and nullability
- **Registered Triggers**: All triggers managed by pg_sql_triggers with full details
- **Database Triggers**: Triggers that exist in the database but aren't in the registry

From the table detail page, you can:
- Enable/disable individual triggers (Operator+ permission)
- Drop triggers (Admin permission)
- Re-execute drifted triggers (Admin permission)
- Create new triggers for the table

## Managing Triggers

### Viewing Trigger Details

Click on any trigger name (from dashboard or table view) to access the trigger detail page. The detail page includes:

#### Navigation
- **Breadcrumb Navigation**: Dashboard → Tables → Table Name → Trigger Name
- **Quick Links**: Back to Dashboard, View Table

#### Summary Panel
- Current status and drift state with visual indicators
- Table and function information
- Version, source (DSL/generated/manual_sql), and environment
- **Last Applied**: Human-readable timestamp showing when trigger was last applied (e.g., "2 hours ago")
- **Last Verified**: Timestamp of last drift verification
- **Created At**: Original creation timestamp

#### SQL Information
- **Function Body**: Complete PL/pgSQL function code
- **Trigger Configuration**: Events, timing, conditions
- **SQL Diff View**: If drift detected, shows expected vs actual SQL side-by-side

#### Actions
All action buttons available based on permissions:
- Enable/Disable (Operator+)
- Re-Execute (Admin, shown only when drift detected)
- Drop (Admin)

### Enabling/Disabling Triggers

Triggers can be enabled or disabled from multiple locations:
- **Dashboard**: Quick action buttons in the trigger table (Operator+ permission)
- **Table Detail Page**: Action buttons for each trigger (Operator+ permission)
- **Trigger Detail Page**: Full action panel (Operator+ permission)

#### Enable a Trigger

1. Navigate to the trigger (dashboard, table view, or trigger detail page)
2. Click the "Enable" button (green button)
3. In production environments, enter the confirmation text when prompted
4. Confirm the action in the modal
5. The trigger will be enabled and the operation logged to the audit trail

#### Disable a Trigger

1. Navigate to the trigger (dashboard, table view, or trigger detail page)
2. Click the "Disable" button (red button)
3. In production environments, enter the confirmation text when prompted
4. Confirm the action in the modal
5. The trigger will be disabled and the operation logged to the audit trail

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

The drop action permanently removes a trigger from the database and registry. Available from:
- **Dashboard**: "Drop" button in trigger table (Admin only)
- **Table Detail Page**: "Drop Trigger" button (Admin only)
- **Trigger Detail Page**: "Drop Trigger" button (Admin only)

**Steps**:
1. Navigate to the trigger (any view with drop button)
2. Click the "Drop Trigger" button (gray button with warning icon)
3. A modal will appear requiring:
   - **Reason**: Explanation for dropping the trigger (required for audit trail)
   - **Confirmation**: In protected environments, type the exact confirmation text shown
4. Review the warning message carefully
5. Click "Drop Trigger" to confirm

**Important Notes**:
- This action is **irreversible** - the trigger will be permanently removed
- Requires **Admin** permission level
- Protected by kill switch in production environments
- Reason is logged for compliance and audit purposes
- The trigger is removed from both the database and the registry
- Operation is logged to audit trail with actor information and state changes

### Re-Execute Trigger

The re-execute action fixes drifted triggers by dropping and recreating them from the registry definition. Available from:
- **Dashboard**: "Re-Execute" button in trigger table (Admin only, shown only when drift detected)
- **Table Detail Page**: "Re-Execute Trigger" button (Admin only, shown only when drift detected)
- **Trigger Detail Page**: "Re-Execute Trigger" button (Admin only, shown only when drift detected)

**Steps**:
1. Navigate to the trigger (any view with re-execute button)
2. If the trigger is drifted, you'll see a drift warning and the "Re-Execute" button will be visible
3. Click the "Re-Execute" button (yellow/warning button)
4. A modal will appear showing:
   - **Drift Comparison**: Side-by-side differences between expected (registry) and actual (database) SQL
   - **Reason Field**: Explanation for re-executing (required for audit trail)
   - **Confirmation**: In protected environments, type the exact confirmation text shown
5. Review the drift differences carefully to understand what will change
6. Click "Re-Execute Trigger" to confirm

**What Happens**:
1. Current trigger is dropped from the database
2. New trigger is created using the registry definition (function_body, events, timing, condition)
3. Registry is updated with execution timestamp
4. Operation is logged to audit trail with:
   - Reason and actor information
   - Before and after state
   - SQL diff information

**Important Notes**:
- Requires **Admin** permission level
- Protected by kill switch in production environments
- Reason is logged for compliance and audit purposes
- Executes in a database transaction (rolls back on error)
- Best used to fix triggers that have drifted from their DSL definition
- Button only appears when drift is detected

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

## Audit Log

The Audit Log provides a comprehensive view of all trigger operations performed through the web UI, console APIs, and CLI. This feature is essential for compliance, debugging, and tracking changes to your trigger ecosystem.

### Accessing the Audit Log

1. Navigate to the "Audit Log" link in the main navigation menu
2. Or visit `/pg_sql_triggers/audit_logs` directly

### Viewing Audit Log Entries

The audit log displays all operations with the following information:

- **Time**: When the operation occurred (relative time with exact timestamp on hover)
- **Trigger**: The trigger name (clickable link to trigger detail page if available)
- **Operation**: The type of operation performed (e.g., `trigger_enable`, `trigger_drop`, `trigger_re_execute`)
- **Status**: Success or failure indicator
- **Environment**: The environment where the operation was performed
- **Actor**: Who performed the operation (e.g., `UI:user_id`, `Console:email`)
- **Reason**: Explanation for the operation (for drop/re-execute operations)
- **Error**: Error message if the operation failed

### Filtering Audit Logs

The audit log supports multiple filters to help you find specific entries:

1. **Trigger Name**: Filter by specific trigger name
2. **Operation**: Filter by operation type (enable, disable, drop, re_execute, etc.)
3. **Status**: Filter by success or failure
4. **Environment**: Filter by environment (production, staging, development, etc.)
5. **Sort Order**: Sort by date (newest first or oldest first)

Click "Apply Filters" to update the view, or "Clear" to remove all filters.

### Exporting Audit Logs

To export audit log entries:

1. Apply any desired filters
2. Click the "Export CSV" button
3. The CSV file will include all entries matching your filters (not just the current page)
4. File is named with timestamp: `audit_logs_YYYYMMDD_HHMMSS.csv`

The CSV export includes:
- ID, Trigger Name, Operation, Status, Environment
- Actor Type and ID
- Reason and Error Message
- Created At timestamp

### Pagination

The audit log uses pagination to handle large datasets:

- Default: 50 entries per page (adjustable via URL parameter)
- Maximum: 200 entries per page
- Navigate using "Previous" and "Next" buttons
- Page numbers and total count displayed

### What Gets Logged

All of the following operations are logged to the audit log:

- **Enable Trigger**: Success/failure, before/after state
- **Disable Trigger**: Success/failure, before/after state
- **Drop Trigger**: Success/failure, reason, state changes
- **Re-execute Trigger**: Success/failure, reason, drift diff information
- **SQL Capsule Execution**: Success/failure, capsule details
- **Migration Operations**: Up, down, and redo operations (infrastructure ready)

Each log entry includes:
- Complete actor information (who performed the operation)
- Before and after state (for state-changing operations)
- Operation metadata (reason, confirmation text, environment)
- Error details (if the operation failed)
- Timestamp of the operation

### Use Cases

Common use cases for the audit log:

- **Compliance**: Track all changes for audit requirements
- **Debugging**: Understand what operations were performed before an issue
- **Accountability**: See who performed specific operations
- **Troubleshooting**: Review failed operations and their error messages
- **Change History**: Track the evolution of your trigger ecosystem over time

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
4. **Audit Logging**: All protected operations are logged with complete audit trail:
   - Actor information (who performed the operation)
   - Before and after state
   - Operation details (reason, confirmation text)
   - Success/failure status
   - Error messages (if failed)
   - Timestamp of operation

### Configuring Permissions

Set up custom permission checking in the initializer:

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  config.permission_checker = ->(actor, action, environment) {
    user = User.find_by(id: actor[:id])
    return false unless user

    case action
    when :view_triggers, :view_diffs
      user.present? # Viewer level
    when :enable_trigger, :disable_trigger, :apply_trigger, :generate_trigger, :test_trigger, :dry_run_sql
      user.operator? || user.admin? # Operator level
    when :drop_trigger, :execute_sql, :override_drift
      user.admin? # Admin level
    else
      false
    end
  }
end
```else
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

## Dashboard Enhancements (v1.3.0+)

### Last Applied Column

The dashboard now includes a "Last Applied" column showing when each trigger was last applied to the database:
- **Human-readable format**: Displays relative time (e.g., "2 hours ago", "3 days ago")
- **Tooltip**: Hover over the timestamp to see exact date and time
- **Default sorting**: Dashboard sorted by most recently applied triggers first
- **Never applied**: Shows "Never" if trigger has never been applied

This helps you quickly identify:
- Which triggers are actively maintained
- How recently triggers were updated
- Triggers that may need attention

### Quick Actions in Dashboard

The dashboard trigger table now includes quick action buttons:
- **Enable/Disable**: Toggle trigger state (Operator+ permission)
- **Drop**: Remove trigger permanently (Admin only)
- **Re-Execute**: Fix drifted triggers (Admin only, shown only when drift detected)

All actions respect permission levels and show/hide buttons based on your role.

## Tips and Best Practices

1. **Check Status Regularly**: Monitor drift detection to catch unexpected changes
2. **Use Confirmations**: Don't bypass production confirmations without understanding the impact
3. **Test in Development**: Always test UI actions in development before production
4. **Review Logs**: Check application logs and audit trail after important operations
5. **Document Changes**: Add detailed reasons when dropping or re-executing triggers
6. **Monitor Last Applied**: Use the "Last Applied" column to track trigger maintenance activity
7. **Breadcrumb Navigation**: Use breadcrumbs on trigger detail page for easy navigation

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
