# frozen_string_literal: true

require_relative "lib/pg_sql_triggers/version"

Gem::Specification.new do |spec|
  spec.name = "pg_sql_triggers"
  spec.version = PgSqlTriggers::VERSION
  spec.authors = ["samaswin87"]
  spec.email = ["samaswin@gmail.com"]

  spec.summary = "A PostgreSQL Trigger Control Plane for Rails"
  spec.description = "Production-grade PostgreSQL trigger management for Rails with " \
                     "lifecycle management, safe deploys, versioning, drift detection, " \
                     "and a mountable UI."
  spec.homepage = "https://github.com/samaswin87/pg_sql_triggers"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/samaswin87/pg_sql_triggers"
  spec.metadata["changelog_uri"] = "https://github.com/samaswin87/pg_sql_triggers/blob/main/CHANGELOG.md"
  spec.metadata["github_repo"] = "ssh://github.com/samaswin87/pg_sql_triggers"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "pg", ">= 1.0"
  spec.add_dependency "rails", ">= 6.1"

  # Development dependencies
  spec.add_development_dependency "bigdecimal", ">= 3.0" # Required for Ruby 3.4+ (removed from stdlib)
  spec.add_development_dependency "database_cleaner-active_record", "~> 2.0"
  spec.add_development_dependency "erb_lint", "~> 0.9"
  spec.add_development_dependency "factory_bot_rails", "~> 6.0"
  spec.add_development_dependency "rails-controller-testing", "~> 1.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-rails", "~> 2.19"
  spec.add_development_dependency "rubocop-rspec", "~> 2.20"
  spec.add_development_dependency "simplecov", "~> 0.21"
end
