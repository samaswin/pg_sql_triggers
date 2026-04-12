# Permissions Guide

PgSqlTriggers includes a comprehensive three-tier permission system to control access to trigger operations. This guide explains how to configure and use permissions.

## Table of Contents

- [Overview](#overview)
- [Permission Levels](#permission-levels)
- [Actions and Required Roles](#actions-and-required-roles)
- [Configuration](#configuration)
- [Integration Examples](#integration-examples)
- [UI Behavior](#ui-behavior)
- [Console API](#console-api)

## Overview

The permission system provides three levels of access:

- **Viewer**: Read-only access to view triggers and their status
- **Operator**: Can enable/disable triggers, apply migrations, generate triggers
- **Admin**: Full access including drop, re-execute, and the reserved `execute_sql` permission action for host-defined privileged SQL

By default, all permissions are allowed (permissive mode). **You must configure permissions in production** to enforce access controls.

## Permission Levels

### Viewer

Viewers have read-only access and can:
- View the dashboard
- View trigger details
- View table listings
- View audit logs
- View drift information

### Operator

Operators can perform routine operations:
- All Viewer permissions
- Enable/disable triggers
- Apply trigger migrations
- Generate new triggers (via UI)
- Perform dry-run operations
- Test triggers

### Admin

Admins have full access:
- All Operator permissions
- Drop triggers
- Re-execute triggers
- `execute_sql` (privileged SQL; for custom integrations — not used by built-in UI)
- Override drift detection

## Actions and Required Roles

The following actions are mapped to permission levels:

| Action | Required Role | Description |
|--------|--------------|-------------|
| `view_triggers` | Viewer | View trigger list and details |
| `view_diffs` | Viewer | View SQL differences and drift |
| `enable_trigger` | Operator | Enable a trigger |
| `disable_trigger` | Operator | Disable a trigger |
| `apply_trigger` | Operator | Apply a trigger migration |
| `dry_run_sql` | Operator | Perform dry-run validation |
| `generate_trigger` | Operator | Generate triggers via UI |
| `test_trigger` | Operator | Test trigger functions |
| `drop_trigger` | Admin | Drop a trigger from database |
| `execute_sql` | Admin | Privileged SQL (`permission_checker` / custom tooling; not used by built-in UI) |
| `override_drift` | Admin | Override drift detection warnings |

## Configuration

### Basic Configuration

Configure permissions in your initializer:

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  config.permission_checker = ->(actor, action, environment) {
    # Your permission logic here
    # Return true if allowed, false if denied
  }
end
```

### Simple Role-Based Example

```ruby
PgSqlTriggers.configure do |config|
  config.permission_checker = ->(actor, action, environment) {
    # Assume actor has a :role method or attribute
    user_role = actor.role.to_s.downcase
    
    case action
    when :view_triggers, :view_diffs
      true  # Everyone can view
    when :enable_trigger, :disable_trigger, :apply_trigger,
         :dry_run_sql, :generate_trigger, :test_trigger
      user_role.in?(%w[operator admin])
    when :drop_trigger, :execute_sql, :override_drift
      user_role == 'admin'
    else
      false
    end
  }
end
```

### Pundit Integration

```ruby
PgSqlTriggers.configure do |config|
  config.permission_checker = ->(actor, action, environment) {
    resource = PgSqlTriggers::TriggerPolicy.new(actor, nil)
    
    case action
    when :view_triggers, :view_diffs
      resource.view?
    when :enable_trigger, :disable_trigger
      resource.enable? || resource.disable?
    when :drop_trigger, :execute_sql
      resource.admin?
    else
      false
    end
  }
end
```

### CanCanCan Integration

```ruby
PgSqlTriggers.configure do |config|
  config.permission_checker = ->(actor, action, environment) {
    ability = Ability.new(actor)
    
    case action
    when :view_triggers, :view_diffs
      ability.can?(:read, :trigger)
    when :enable_trigger, :disable_trigger
      ability.can?(:manage, :trigger)
    when :drop_trigger, :execute_sql
      ability.can?(:destroy, :trigger)
    else
      false
    end
  }
end
```

### Environment-Based Permissions

You can restrict permissions by environment:

```ruby
PgSqlTriggers.configure do |config|
  config.permission_checker = ->(actor, action, environment) {
    # Stricter permissions in production
    if environment == 'production'
      case action
      when :drop_trigger, :execute_sql
        actor.role == 'admin' && actor.super_admin?
      else
        actor.role.in?(%w[operator admin])
      end
    else
      # More permissive in development
      actor.role.in?(%w[viewer operator admin])
    end
  }
end
```

## Integration Examples

### Controller Integration

The permission system integrates with controllers automatically. Override `current_actor` in your application controller:

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  private

  def current_actor
    {
      type: current_user.class.name,
      id: current_user.id.to_s,
      role: current_user.role  # Add role if needed
    }
  end
end
```

For PgSqlTriggers controllers, override the ApplicationController:

```ruby
# app/controllers/pg_sql_triggers/application_controller.rb
module PgSqlTriggers
  class ApplicationController < ::PgSqlTriggers::ApplicationController
    private

    def current_actor
      {
        type: current_user.class.name,
        id: current_user.id.to_s,
        role: current_user.role
      }
    end
  end
end
```

### Custom Actor Format

Your actor can be any format as long as your permission checker understands it:

```ruby
# Actor as User object
config.permission_checker = ->(actor, action, environment) {
  return false unless actor.is_a?(User)
  actor.role >= required_role_for(action)
}

# Actor as Hash
config.permission_checker = ->(actor, action, environment) {
  return false unless actor.is_a?(Hash)
  actor[:role] >= required_role_for(action)
}
```

## UI Behavior

The UI automatically adjusts based on permissions:

### Button Visibility

- **Enable/Disable buttons**: Only visible to Operator+ roles
- **Drop button**: Only visible to Admin roles
- **Re-execute button**: Only visible to Admin roles
- **Execute SQL button**: Only visible to Admin roles
- **Generate Trigger button**: Only visible to Operator+ roles

### Permission Errors

When a user attempts an unauthorized action:

1. **UI Actions**: User is redirected with an alert message
2. **API Calls**: `PermissionError` is raised with recovery suggestions
3. **Error Messages**: Include the required role and recovery steps

## Console API

All console API methods check permissions:

```ruby
# Enable trigger (requires Operator+)
PgSqlTriggers::Registry.enable(
  "trigger_name",
  actor: current_user,
  confirmation: "EXECUTE TRIGGER_ENABLE"
)

# Drop trigger (requires Admin)
PgSqlTriggers::Registry.drop(
  "trigger_name",
  actor: current_user,
  reason: "No longer needed",
  confirmation: "EXECUTE TRIGGER_DROP"
)

# Custom tooling: gate raw SQL with the Admin-level :execute_sql action (requires Admin)
PgSqlTriggers::Permissions.check!(current_user, :execute_sql)
# ... your application's SQL execution ...
```

### Permission Errors in Console

When permission is denied, a `PermissionError` is raised:

```ruby
begin
  PgSqlTriggers::Registry.drop("trigger_name", actor: user)
rescue PgSqlTriggers::PermissionError => e
  puts "Permission denied: #{e.message}"
  puts "Recovery: #{e.recovery_suggestion}"
  # Error code: e.error_code => "PERMISSION_DENIED"
end
```

## Testing Permissions

### In Tests

```ruby
# RSpec example
RSpec.describe "Trigger permissions" do
  let(:operator_user) { create(:user, role: 'operator') }
  let(:admin_user) { create(:user, role: 'admin') }
  let(:viewer_user) { create(:user, role: 'viewer') }

  it "allows operators to enable triggers" do
    actor = { type: "User", id: operator_user.id.to_s, role: 'operator' }
    expect {
      PgSqlTriggers::Registry.enable("trigger_name", actor: actor)
    }.not_to raise_error
  end

  it "denies viewers from dropping triggers" do
    actor = { type: "User", id: viewer_user.id.to_s, role: 'viewer' }
    expect {
      PgSqlTriggers::Registry.drop("trigger_name", actor: actor)
    }.to raise_error(PgSqlTriggers::PermissionError)
  end
end
```

## Best Practices

1. **Always configure permissions in production** - Default permissive mode is unsafe
2. **Use environment-based permissions** - Stricter in production, permissive in development
3. **Test permission scenarios** - Ensure your permission checker works correctly
4. **Log permission denials** - Monitor unauthorized access attempts
5. **Document your permission model** - Help team members understand access levels

## Troubleshooting

### All users have full access

**Problem**: Permissions are not being enforced.

**Solution**: Check that `permission_checker` is configured. The default is permissive (allows all).

```ruby
# Verify configuration
PgSqlTriggers.permission_checker # Should not be nil in production
```

### Permission errors in development

**Problem**: Permission checks are blocking development work.

**Solution**: Use environment-based permissions or disable checks in development:

```ruby
config.permission_checker = ->(actor, action, environment) {
  return true if Rails.env.development?
  # Production permission logic
}
```

### Actor format errors

**Problem**: Permission checker receives unexpected actor format.

**Solution**: Ensure your permission checker handles the actor format you're using. Check controller `current_actor` method.

## Related Documentation

- [Configuration Reference](configuration.md#permission-system) - Complete configuration options
- [API Reference](api-reference.md) - Console API methods
- [Web UI Guide](web-ui.md) - UI features and behavior

