# Gem Release Guide

This guide walks you through the process of releasing a new version of `pg_sql_triggers` to RubyGems.

## Prerequisites

Before releasing, ensure you have:

1. **RubyGems account**: You need an account at https://rubygems.org
2. **API key**: Generate one at https://rubygems.org/api_keys
3. **MFA enabled**: Your gemspec requires MFA (`rubygems_mfa_required = "true"`), so ensure MFA is enabled on your RubyGems account
4. **Git access**: You need push access to the repository

## Release Checklist

### 1. Update Version Number

Update the version in `lib/pg_sql_triggers/version.rb` following [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.0.0 → 2.0.0): Breaking changes
- **MINOR** (1.0.0 → 1.1.0): New features, backward compatible
- **PATCH** (1.0.0 → 1.0.1): Bug fixes, backward compatible

```ruby
# lib/pg_sql_triggers/version.rb
module PgSqlTriggers
  VERSION = "1.0.1"  # Update this
end
```

### 2. Update CHANGELOG.md

Add a new entry to `CHANGELOG.md` following the existing format:

```markdown
## [1.0.1] - 2025-12-28

### Added
- New feature description

### Changed
- Change description

### Fixed
- Bug fix description
```

**Important**: Update the date to today's date and ensure all changes since the last release are documented.

### 3. Run Tests

Ensure all tests pass before releasing:

```bash
# Run the full test suite
bundle exec rspec

# Or use the rake task
bundle exec rake spec
```

### 4. Check for Linting Issues

Run RuboCop to ensure code quality:

```bash
bundle exec rubocop
```

Fix any issues before proceeding.

### 5. Build the Gem Locally (Optional but Recommended)

Build the gem locally to verify it works:

```bash
# Build the gem
gem build pg_sql_triggers.gemspec

# This creates pg_sql_triggers-1.0.1.gem
# You can inspect it or test install it locally
```

### 6. Commit Your Changes

Commit the version bump and CHANGELOG updates:

```bash
# Stage your changes
git add lib/pg_sql_triggers/version.rb CHANGELOG.md

# Commit with a descriptive message
git commit -m "Bump version to 1.0.1"
```

### 7. Create a Git Tag

The release process will create a tag automatically, but you can also create it manually:

```bash
# Create an annotated tag
git tag -a v1.0.1 -m "Release version 1.0.1"

# Or let the release task handle it (recommended)
```

### 8. Push to Git Repository

Push your commits and tags:

```bash
# Push commits
git push origin main  # or master, depending on your default branch

# Push tags (if created manually)
git push origin v1.0.1
```

### 9. Release to RubyGems

Use the built-in Rake task to release:

```bash
# This will:
# 1. Build the gem
# 2. Create a git tag
# 3. Push commits and tags to git
# 4. Push the gem to RubyGems.org
bundle exec rake release
```

**Note**: This command will:
- Build the gem file
- Create a git tag for the version
- Push git commits and tags to the remote repository
- Push the `.gem` file to RubyGems.org

You'll be prompted for:
- Your RubyGems credentials (username and password)
- Your MFA code (if MFA is enabled, which it should be)

### 10. Verify the Release

After releasing, verify the gem is available:

```bash
# Check if the gem is available
gem search pg_sql_triggers

# Or visit https://rubygems.org/gems/pg_sql_triggers
```

### 11. Create a GitHub Release (Optional but Recommended)

1. Go to https://github.com/samaswin87/pg_sql_triggers/releases
2. Click "Draft a new release"
3. Select the tag you just created (e.g., `v1.0.1`)
4. Use the CHANGELOG entry as the release notes
5. Publish the release

## Quick Release Script

For convenience, here's a quick release script you can run:

```bash
#!/bin/bash
# release.sh

set -e  # Exit on error

VERSION=$1

if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version>"
  echo "Example: ./release.sh 1.0.1"
  exit 1
fi

echo "Releasing version $VERSION..."

# Update version
sed -i '' "s/VERSION = \".*\"/VERSION = \"$VERSION\"/" lib/pg_sql_triggers/version.rb

# Run tests
echo "Running tests..."
bundle exec rspec

# Run linter
echo "Running linter..."
bundle exec rubocop

# Build gem
echo "Building gem..."
gem build pg_sql_triggers.gemspec

# Commit changes
echo "Committing changes..."
git add lib/pg_sql_triggers/version.rb CHANGELOG.md
git commit -m "Bump version to $VERSION"

# Create tag
echo "Creating tag..."
git tag -a v$VERSION -m "Release version $VERSION"

# Push
echo "Pushing to git..."
git push origin main
git push origin v$VERSION

# Release
echo "Releasing to RubyGems..."
bundle exec rake release

echo "Release $VERSION complete!"
```

## Troubleshooting

### MFA Required Error

If you get an MFA error, ensure:
1. MFA is enabled on your RubyGems account
2. You're using the correct API key
3. You have the latest version of the `gem` command

### Authentication Issues

If authentication fails:
1. Check your RubyGems credentials: `gem credentials list`
2. Update credentials: `gem signin`
3. Verify your API key at https://rubygems.org/api_keys

### Tag Already Exists

If the tag already exists:
```bash
# Delete local tag
git tag -d v1.0.1

# Delete remote tag
git push origin :refs/tags/v1.0.1

# Then retry the release
```

### Gem Already Exists

If the version already exists on RubyGems:
1. You cannot overwrite a published gem version
2. You must bump to a new version number
3. Update the version in `version.rb` and try again

## Best Practices

1. **Always test before releasing**: Run the full test suite
2. **Update CHANGELOG**: Document all changes for users
3. **Follow semantic versioning**: Be consistent with version numbers
4. **Create GitHub releases**: Helps with documentation and announcements
5. **Release during business hours**: Easier to monitor and fix issues
6. **Test the gem after release**: Install it in a test project to verify

## Post-Release

After a successful release:

1. ✅ Verify the gem is installable: `gem install pg_sql_triggers -v 1.0.1`
2. ✅ Check the RubyGems page: https://rubygems.org/gems/pg_sql_triggers
3. ✅ Update any documentation that references version numbers
4. ✅ Announce the release (if applicable) via blog, Twitter, etc.

