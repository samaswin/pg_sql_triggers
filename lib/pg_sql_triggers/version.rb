# frozen_string_literal: true

# Version follows Semantic Versioning (https://semver.org/):
# - MAJOR: Breaking changes (1.0.0 → 2.0.0)
# - MINOR: New features, backward compatible (1.0.0 → 1.1.0)
# - PATCH: Bug fixes, backward compatible (1.0.0 → 1.0.1)
#
# To release a new version:
# 1. Update this version number
# 2. Update CHANGELOG.md with the new version and changes
# 3. Run: bundle exec rake release
# See RELEASE.md for detailed release instructions
module PgSqlTriggers
  VERSION = "1.0.0"
end
