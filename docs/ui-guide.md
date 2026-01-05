# UI Guide

A quick-start guide to using the PgSqlTriggers web interface.

## Table of Contents

- [Getting Started](#getting-started)
- [Dashboard](#dashboard)
- [Trigger Management](#trigger-management)
- [Quick Actions](#quick-actions)
- [Permissions](#permissions)
- [Common Tasks](#common-tasks)

## Getting Started

### Accessing the UI

The PgSqlTriggers web UI is available at:

```
http://localhost:3000/pg_sql_triggers
```

You can customize the mount path in your routes if needed.

### Navigation

The main navigation includes:

- **Dashboard**: Overview of all triggers
- **Tables**: Browse triggers by table (with pagination and filters)
- **Generator**: Create new triggers via UI
- **Audit Log**: View operation history

## Dashboard

The dashboard provides an overview of your trigger ecosystem.

### Key Features

- **Trigger List**: All triggers with status indicators
- **Status Colors**: Visual indicators for trigger states
- **Last Applied**: When triggers were last applied
- **Quick Actions**: Enable/disable buttons (based on permissions)
- **Drift Indicators**: Visual warnings for drifted triggers

## Tables Page

The Tables page shows all database tables and their triggers.

### Key Features

- **Statistics**: Count of tables with/without triggers
- **Filtering**: View all tables, only with triggers, or only without triggers
- **Pagination**: Navigate through large table lists (20 per page by default)
- **Table Details**: Click "View Details" to see all triggers for a table
- **Quick Actions**: Create triggers directly from the table list

### Using Filters

1. Click "View Tables" from dashboard
2. Use filter buttons:
   - **All Tables**: Shows everything
   - **With Triggers**: Only tables that have triggers (default)
   - **Without Triggers**: Only tables without triggers
3. Filter selection is preserved when navigating pages

### Status Indicators

- **✓ Green**: Managed and in sync
- **⚠ Yellow**: Drifted or manual override
- **✗ Red**: Dropped or error
- **○ Gray**: Disabled
- **? Purple**: Unknown state

### Sorting and Filtering

- Click column headers to sort
- Use filters to narrow results
- Search by trigger name

## Trigger Management

### Viewing Trigger Details

Click any trigger name to view details:

- **Summary Panel**: Status, version, environment
- **SQL Information**: Function body and trigger configuration
- **Drift Information**: Expected vs actual SQL (if drifted)
- **Action Buttons**: Enable, disable, drop, re-execute

### Enabling/Disabling Triggers

1. Navigate to trigger (dashboard or detail page)
2. Click **Enable** or **Disable** button
3. In production, enter confirmation text when prompted
4. Confirm in modal
5. Operation is logged to audit trail

### Dropping Triggers (Admin Only)

1. Navigate to trigger detail page
2. Click **Drop** button (Admin permission required)
3. Enter reason for dropping
4. Enter confirmation text (in production)
5. Confirm in modal
6. Trigger is removed from database and registry

### Re-executing Triggers (Admin Only)

Re-execute is used to fix drifted triggers:

1. Navigate to drifted trigger detail page
2. Review drift diff (expected vs actual)
3. Click **Re-execute** button
4. Enter reason
5. Enter confirmation text (in production)
6. Confirm in modal
7. Trigger is dropped and recreated with current definition

## Quick Actions

### From Dashboard

- **Enable/Disable**: Quick toggle buttons (Operator+)
- **View Details**: Click trigger name
- **View Table**: Click table name

### From Trigger Detail Page

- **Enable/Disable**: Full action panel
- **Drop**: Remove trigger (Admin)
- **Re-execute**: Fix drift (Admin)
- **View Table**: Navigate to table view
- **Back to Dashboard**: Return to overview

## Permissions

The UI automatically adjusts based on your role:

- **Viewer**: Can view all triggers and details
- **Operator**: Can enable/disable, generate triggers
- **Admin**: Full access including drop and re-execute

Buttons are hidden if you don't have permission. See [Permissions Guide](permissions.md) for configuration details.

## Common Tasks

### Enable a Disabled Trigger

1. Go to Dashboard
2. Find trigger (gray indicator = disabled)
3. Click **Enable** button
4. Enter confirmation (if in production)
5. Confirm

### Fix a Drifted Trigger

1. Go to Dashboard
2. Find drifted trigger (yellow indicator)
3. Click trigger name to view details
4. Review drift diff
5. Click **Re-execute** button (Admin required)
6. Enter reason: "Fix drift"
7. Enter confirmation (if in production)
8. Confirm

### View Trigger History

1. Go to Audit Log
2. Filter by trigger name
3. Review operation history
4. Click entry for details

### Generate a New Trigger

1. Go to Generator
2. Fill in trigger details:
   - Trigger name
   - Table name
   - Events (INSERT, UPDATE, etc.)
   - Function body (SQL)
   - Version
3. Preview DSL and SQL
4. Validate SQL
5. Create trigger
6. Run migration: `rake trigger:migrate`

### Export Audit Logs

1. Go to Audit Log
2. Apply filters (optional)
3. Click **Export CSV**
4. File downloads with filtered results

## Tips

- **Use filters**: Narrow results quickly
- **Check drift regularly**: Yellow indicators need attention
- **Review audit logs**: Understand what operations occurred
- **Use breadcrumbs**: Easy navigation between views
- **Read error messages**: They include recovery suggestions

## Next Steps

- [Web UI Documentation](web-ui.md) - Comprehensive UI reference
- [Permissions Guide](permissions.md) - Configure access controls
- [Audit Trail Guide](audit-trail.md) - Viewing and exporting logs
- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions

