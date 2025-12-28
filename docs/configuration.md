# Configuration Reference

Complete reference for configuring PgSqlTriggers in your Rails application.

## Table of Contents

- [Overview](#overview)
- [Configuration File](#configuration-file)
- [Core Settings](#core-settings)
- [Kill Switch Configuration](#kill-switch-configuration)
- [Permission System](#permission-system)
- [Environment Detection](#environment-detection)
- [Advanced Configuration](#advanced-configuration)
- [Examples](#examples)

## Overview

PgSqlTriggers is configured through an initializer file. All configuration is done within the `PgSqlTriggers.configure` block.

## Configuration File

The default configuration file is created during installation:

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  # Your configuration here
end
```

## Core Settings

### `default_environment`

Specifies how to detect the current environment.

- **Type**: Lambda/Proc
- **Default**: `-> { Rails.env }`
- **Returns**: String or Symbol

```ruby
config.default_environment = -> { Rails.env }

# Custom environment detection
config.default_environment = -> {
  ENV['APP_ENV'] || Rails.env
}

# Static environment
config.default_environment = -> { 'production' }
```

### `mount_path`

Customize where the web UI is mounted (configured in routes, not initializer).

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount PgSqlTriggers::Engine, at: "/admin/triggers"
end
```

## Kill Switch Configuration

### `kill_switch_enabled`

Master toggle for the kill switch system.

- **Type**: Boolean
- **Default**: `true`

```ruby
# Enable kill switch (recommended)
config.kill_switch_enabled = true

# Disable kill switch (not recommended for production)
config.kill_switch_enabled = false
```

### `kill_switch_environments`

List of environments where the kill switch is active.

- **Type**: Array of Symbols
- **Default**: `[:production, :staging]`

```ruby
# Default: protect production and staging
config.kill_switch_environments = %i[production staging]

# Protect additional environments
config.kill_switch_environments = %i[production staging qa demo]

# Only protect production
config.kill_switch_environments = [:production]

# Protect all except development
config.kill_switch_environments = %i[production staging test qa uat]
```

### `kill_switch_confirmation_required`

Whether confirmation text is required for overrides.

- **Type**: Boolean
- **Default**: `true`

```ruby
# Require confirmation text (recommended)
config.kill_switch_confirmation_required = true

# Only require ENV override (less safe)
config.kill_switch_confirmation_required = false
```

### `kill_switch_confirmation_pattern`

Defines the format of required confirmation text.

- **Type**: Lambda/Proc
- **Parameter**: `operation` (Symbol)
- **Returns**: String
- **Default**: `->(operation) { "EXECUTE #{operation.to_s.upcase}" }`

```ruby
# Default pattern
config.kill_switch_confirmation_pattern = ->(operation) {
  "EXECUTE #{operation.to_s.upcase}"
}

# Include date
config.kill_switch_confirmation_pattern = ->(operation) {
  date = Date.today.strftime('%Y%m%d')
  "EXECUTE-#{operation.to_s.upcase}-#{date}"
}

# Include environment
config.kill_switch_confirmation_pattern = ->(operation) {
  env = Rails.env.upcase
  "#{env}-#{operation.to_s.upcase}"
}

# Custom prefix
config.kill_switch_confirmation_pattern = ->(operation) {
  "CONFIRM-PRODUCTION-#{operation.to_s.upcase}"
}
```

### `kill_switch_logger`

Logger for kill switch events.

- **Type**: Logger instance
- **Default**: `Rails.logger`

```ruby
# Use Rails logger (default)
config.kill_switch_logger = Rails.logger

# Separate log file
config.kill_switch_logger = Logger.new(
  Rails.root.join('log', 'kill_switch.log')
)

# Custom formatter
kill_switch_logger = Logger.new(Rails.root.join('log', 'kill_switch.log'))
kill_switch_logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}\n"
end
config.kill_switch_logger = kill_switch_logger

# Multiple destinations
require 'logger'
config.kill_switch_logger = Logger.new(STDOUT)
config.kill_switch_logger.extend(ActiveSupport::Logger.broadcast(
  Logger.new(Rails.root.join('log', 'kill_switch.log'))
))
```

## Permission System

### `permission_checker`

Custom authorization logic for the web UI and API.

- **Type**: Lambda/Proc
- **Parameters**:
  - `actor` (Hash): Information about who is performing the action
  - `action` (Symbol): The action being performed
  - `environment` (String): Current environment
- **Returns**: Boolean
- **Default**: `->(_actor, _action, _environment) { true }`

```ruby
# Default: allow all (development only!)
config.permission_checker = ->(_actor, _action, _environment) { true }

# Basic user check
config.permission_checker = ->(actor, action, environment) {
  user = User.find_by(id: actor[:id])
  user.present?
}

# Role-based permissions
config.permission_checker = ->(actor, action, environment) {
  user = User.find_by(id: actor[:id])
  return false unless user

  case action
  when :view
    user.present?
  when :operate
    user.operator? || user.admin?
  when :admin
    user.admin?
  else
    false
  end
}

# Environment-specific permissions
config.permission_checker = ->(actor, action, environment) {
  user = User.find_by(id: actor[:id])
  return false unless user

  if environment.to_s == 'production'
    # Stricter in production
    user.admin?
  else
    # More permissive in other environments
    user.developer? || user.admin?
  end
}

# Integration with Pundit
config.permission_checker = ->(actor, action, environment) {
  user = User.find_by(id: actor[:id])
  policy = PgSqlTriggersPolicy.new(user, :pg_sql_triggers)

  case action
  when :view
    policy.read?
  when :operate
    policy.operate?
  when :admin
    policy.admin?
  else
    false
  end
}

# Integration with CanCanCan
config.permission_checker = ->(actor, action, environment) {
  user = User.find_by(id: actor[:id])
  ability = Ability.new(user)

  case action
  when :view
    ability.can?(:read, :pg_sql_triggers)
  when :operate
    ability.can?(:operate, :pg_sql_triggers)
  when :admin
    ability.can?(:admin, :pg_sql_triggers)
  else
    false
  end
}
```

### Permission Levels

The permission checker should handle three levels:

#### `:view` (Read-Only)
- View triggers and status
- View migrations
- View drift information
- Access console read-only methods

#### `:operate`
- All `:view` permissions
- Enable/disable triggers
- Run migrations
- Apply generated triggers

#### `:admin`
- All `:operate` permissions
- Drop triggers
- Execute SQL capsules
- Modify registry directly

## Environment Detection

### Custom Environment Logic

```ruby
# Use environment variable
config.default_environment = -> {
  ENV['DEPLOYMENT_ENV'] || Rails.env
}

# Detect from hostname
config.default_environment = -> {
  hostname = Socket.gethostname
  case hostname
  when /prod/
    'production'
  when /staging/
    'staging'
  else
    Rails.env
  end
}

# Use Rails credentials
config.default_environment = -> {
  Rails.application.credentials.environment || Rails.env
}
```

## Advanced Configuration

### Complete Example

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  # Environment Detection
  config.default_environment = -> { Rails.env }

  # Kill Switch Settings
  config.kill_switch_enabled = true
  config.kill_switch_environments = %i[production staging]
  config.kill_switch_confirmation_required = true

  # Custom confirmation pattern with date
  config.kill_switch_confirmation_pattern = ->(operation) {
    date = Date.today.strftime('%Y%m%d')
    "EXECUTE-#{operation.to_s.upcase}-#{date}"
  }

  # Dedicated kill switch logger
  kill_switch_logger = Logger.new(
    Rails.root.join('log', 'kill_switch.log'),
    10,  # Keep 10 old log files
    1024 * 1024 * 10  # 10 MB per file
  )
  kill_switch_logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime.iso8601}] [#{severity}] #{msg}\n"
  end
  config.kill_switch_logger = kill_switch_logger

  # Role-based permission system
  config.permission_checker = ->(actor, action, environment) {
    user = User.find_by(id: actor[:id])
    return false unless user

    case action
    when :view
      user.has_role?(:viewer, :operator, :admin)
    when :operate
      user.has_role?(:operator, :admin)
    when :admin
      user.has_role?(:admin)
    else
      false
    end
  }
end
```

### Environment-Specific Configuration

```ruby
# config/initializers/pg_sql_triggers.rb
PgSqlTriggers.configure do |config|
  # Common settings
  config.default_environment = -> { Rails.env }
  config.kill_switch_enabled = true

  # Environment-specific settings
  case Rails.env.to_sym
  when :production
    config.kill_switch_environments = [:production]
    config.kill_switch_confirmation_required = true
    config.kill_switch_confirmation_pattern = ->(op) {
      "PRODUCTION-EXECUTE-#{op.to_s.upcase}-#{SecureRandom.hex(2)}"
    }

    config.permission_checker = ->(actor, action, environment) {
      user = User.find_by(id: actor[:id])
      user&.admin?  # Only admins in production
    }

  when :staging
    config.kill_switch_environments = [:staging]
    config.kill_switch_confirmation_required = true
    config.kill_switch_confirmation_pattern = ->(op) {
      "STAGING-#{op.to_s.upcase}"
    }

    config.permission_checker = ->(actor, action, environment) {
      user = User.find_by(id: actor[:id])
      user&.developer? || user&.admin?
    }

  when :development
    config.kill_switch_environments = []
    config.kill_switch_confirmation_required = false

    config.permission_checker = ->(_actor, _action, _environment) { true }

  when :test
    config.kill_switch_enabled = false
    config.permission_checker = ->(_actor, _action, _environment) { true }
  end
end
```

## Examples

### Production-Grade Configuration

```ruby
PgSqlTriggers.configure do |config|
  # Use Rails environment
  config.default_environment = -> { Rails.env }

  # Enable kill switch
  config.kill_switch_enabled = true
  config.kill_switch_environments = %i[production staging]
  config.kill_switch_confirmation_required = true

  # Date-based confirmation
  config.kill_switch_confirmation_pattern = ->(operation) {
    "EXECUTE-#{operation.to_s.upcase}-#{Date.today.strftime('%Y%m%d')}"
  }

  # Structured logging
  config.kill_switch_logger = ActiveSupport::TaggedLogging.new(
    Logger.new(Rails.root.join('log', 'kill_switch.log'))
  )

  # Integration with existing authorization
  config.permission_checker = ->(actor, action, environment) {
    user = User.find_by(id: actor[:id])
    return false unless user

    policy = PgSqlTriggersPolicy.new(user, :triggers)

    case action
    when :view
      policy.read?
    when :operate
      policy.write?
    when :admin
      policy.admin?
    else
      false
    end
  }
end
```

### Development-Friendly Configuration

```ruby
PgSqlTriggers.configure do |config|
  config.default_environment = -> { Rails.env }

  if Rails.env.development?
    # Disabled kill switch for development
    config.kill_switch_enabled = false
    config.permission_checker = ->(_actor, _action, _environment) { true }
  else
    # Standard production settings
    config.kill_switch_enabled = true
    config.kill_switch_environments = %i[production staging]
    config.kill_switch_confirmation_required = true

    config.permission_checker = ->(actor, action, environment) {
      user = User.find_by(id: actor[:id])
      user&.admin?
    }
  end
end
```

### Multi-Tenant Configuration

```ruby
PgSqlTriggers.configure do |config|
  # Detect environment from tenant
  config.default_environment = -> {
    tenant = Apartment::Tenant.current
    tenant == 'production_tenant' ? 'production' : Rails.env
  }

  config.kill_switch_enabled = true
  config.kill_switch_environments = [:production]

  # Tenant-aware permissions
  config.permission_checker = ->(actor, action, environment) {
    user = User.find_by(id: actor[:id])
    return false unless user

    tenant = Apartment::Tenant.current

    # Check user has permission for current tenant
    user.can_access_tenant?(tenant) && user.has_permission?(action)
  }
end
```

## Configuration Validation

Verify your configuration is correct:

```ruby
# In Rails console
PgSqlTriggers.configuration.kill_switch_enabled
# => true

PgSqlTriggers.configuration.kill_switch_environments
# => [:production, :staging]

PgSqlTriggers.configuration.default_environment.call
# => "development"

# Test permission checker
actor = { id: 1, type: 'console' }
PgSqlTriggers.configuration.permission_checker.call(actor, :view, 'production')
# => true or false
```

## Next Steps

- [Kill Switch](kill-switch.md) - Understand production safety features
- [Web UI](web-ui.md) - Configure the web interface
- [Getting Started](getting-started.md) - Initial setup guide
