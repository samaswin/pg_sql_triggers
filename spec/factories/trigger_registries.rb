# frozen_string_literal: true

FactoryBot.define do
  factory :trigger_registry, class: "PgSqlTriggers::TriggerRegistry" do
    sequence(:trigger_name) { |n| "test_trigger_#{n}" }
    table_name { "users" }
    version { 1 }
    enabled { false }
    source { "dsl" }
    sequence(:checksum) { |n| "checksum_#{n}" }
    environment { "test" }
    timing { "before" }

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :production do
      environment { "production" }
    end

    trait :staging do
      environment { "staging" }
    end

    trait :development do
      environment { "development" }
    end

    trait :with_definition do
      definition { "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_function()" }
    end

    trait :with_function_body do
      function_body { "BEGIN\n  -- Trigger logic here\n  RETURN NEW;\nEND;" }
    end

    trait :with_condition do
      condition { "NEW.status = 'active'" }
    end

    trait :after_insert do
      timing { "after" }
    end

    trait :before_insert do
      timing { "before" }
    end

    # Drift-related traits
    trait :drifted do
      checksum { "old_checksum_123" }
      after(:create) do |registry|
        # Ensure database has different function body
        # rubocop:disable Rails/SkipsModelValidations
        registry.update_column(:checksum, "different_checksum")
        # rubocop:enable Rails/SkipsModelValidations
      end
    end

    trait :in_sync do
      after(:build) do |registry|
        require "digest"
        registry.checksum = Digest::SHA256.hexdigest([
          registry.trigger_name,
          registry.table_name,
          registry.version,
          registry.function_body || "",
          registry.condition || ""
        ].join)
      end
    end

    trait :missing_from_db do
      trigger_name { "nonexistent_trigger" }
    end

    # Source type traits
    trait :manual_sql_source do
      source { "manual_sql" }
    end

    trait :dsl_source do
      source { "dsl" }
    end

    trait :generated_source do
      source { "generated" }
    end

    # Complex definition traits
    trait :with_complex_definition do
      definition do
        {
          "event" => "after_insert",
          "for_each" => "row",
          "when" => "NEW.status = 'active'",
          "execute" => "notify_users()"
        }.to_json
      end
    end

    trait :with_json_definition do
      definition do
        {
          "timing" => "after",
          "events" => %w[insert update],
          "for_each" => "row",
          "function" => "trigger_function_name"
        }.to_json
      end
    end

    # Table-specific traits
    trait :for_users_table do
      table_name { "users" }
      trigger_name { "users_audit_trigger" }
    end

    trait :for_posts_table do
      table_name { "posts" }
      trigger_name { "posts_audit_trigger" }
    end

    # Convenience factory for production triggers
    factory :production_trigger, traits: [:production]

    # Convenience factory for enabled triggers
    factory :enabled_trigger, traits: [:enabled]

    # Convenience factory for disabled triggers
    factory :disabled_trigger, traits: [:disabled]
  end
end
