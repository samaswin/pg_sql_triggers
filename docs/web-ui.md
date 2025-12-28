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
- **View SQL**: See the trigger's SQL definition
- **View Diff**: Compare DSL vs database state

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

SQL Capsules provide emergency escape hatches for executing SQL directly.

### When to Use SQL Capsules

Use SQL Capsules for:
- Emergency fixes in production
- Quick database queries
- Testing SQL functions
- Debugging trigger behavior

### Executing SQL

1. Navigate to "SQL Capsules" tab
2. Enter your SQL query:
   ```sql
   SELECT * FROM pg_sql_triggers_registry;
   ```
3. Click "Execute"
4. In production, enter confirmation text: `EXECUTE SQL`
5. Review results in the output panel

### Safety Features

- **Production Protection**: Requires confirmation in protected environments
- **Read-Only Mode**: Optional configuration for limiting to SELECT queries
- **Query Logging**: All SQL execution is logged
- **Permission Checks**: Requires Admin permission level

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
