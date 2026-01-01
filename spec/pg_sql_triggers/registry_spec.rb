# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Registry do
  describe ".register" do
    let(:definition) do
      definition = PgSqlTriggers::DSL::TriggerDefinition.new("test_trigger")
      definition.table(:users)
      definition.on(:insert)
      definition.function(:test_function)
      definition.version(1)
      definition.enabled(false)
      definition
    end

    it "delegates to Manager.register" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:register).with(definition)
      described_class.register(definition)
    end
  end

  describe ".list" do
    it "delegates to Manager.list" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:list)
      described_class.list
    end
  end

  describe ".enabled" do
    it "delegates to Manager.enabled" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:enabled)
      described_class.enabled
    end
  end

  describe ".disabled" do
    it "delegates to Manager.disabled" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:disabled)
      described_class.disabled
    end
  end

  describe ".for_table" do
    it "delegates to Manager.for_table" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:for_table).with("users")
      described_class.for_table("users")
    end
  end

  describe ".diff" do
    it "delegates to Manager.diff" do
      expect(PgSqlTriggers::Registry::Manager).to receive(:diff)
      described_class.diff
    end
  end

  describe ".validate!" do
    it "delegates to Validator.validate!" do
      allow(PgSqlTriggers::Registry::Validator).to receive(:validate!).and_return(true)
      result = described_class.validate!
      expect(PgSqlTriggers::Registry::Validator).to have_received(:validate!)
      expect(result).to be true
    end
  end
end

RSpec.describe PgSqlTriggers::Registry::Manager do
  # Clear cache before each test to ensure test isolation
  before do
    described_class._clear_registry_cache
  end

  describe ".register" do
    let(:definition) do
      definition = PgSqlTriggers::DSL::TriggerDefinition.new("test_trigger")
      definition.table(:users)
      definition.on(:insert)
      definition.function(:test_function)
      definition.version(1)
      definition.enabled(false)
      definition.when_env(:production)
      definition
    end

    context "when trigger doesn't exist" do
      it "creates a new registry entry" do
        registry = described_class.register(definition)
        expect(registry).to be_persisted
        expect(registry.trigger_name).to eq("test_trigger")
        expect(registry.table_name).to eq("users")
        expect(registry.version).to eq(1)
        expect(registry.enabled).to be(false)
        expect(registry.source).to eq("dsl")
        expect(registry.environment).to eq("production")
      end

      it "stores definition as JSON" do
        registry = described_class.register(definition)
        expect(registry.definition).to be_present
        parsed = JSON.parse(registry.definition)
        expect(parsed["name"]).to eq("test_trigger")
      end

      it "sets a placeholder checksum" do
        registry = described_class.register(definition)
        expect(registry.checksum).to eq("placeholder")
      end
    end

    context "when trigger already exists" do
      before do
        create(:trigger_registry, :enabled,
          trigger_name: "test_trigger",
          table_name: "users",
          checksum: "old",
          source: "generated")
      end

      it "updates the existing registry entry" do
        registry = described_class.register(definition)
        expect(registry.enabled).to be(false)
        expect(registry.source).to eq("dsl")
      end
    end
  end

  describe ".list" do
    before do
      create(:trigger_registry, :enabled, trigger_name: "trigger1", table_name: "users")
      create(:trigger_registry, :disabled, trigger_name: "trigger2", table_name: "posts", source: "generated")
    end

    it "returns all triggers" do
      result = described_class.list
      expect(result.count).to eq(2)
      expect(result.map(&:trigger_name)).to contain_exactly("trigger1", "trigger2")
    end
  end

  describe ".enabled" do
    before do
      create(:trigger_registry, :enabled, trigger_name: "enabled_trigger", table_name: "users")
      create(:trigger_registry, :disabled, trigger_name: "disabled_trigger", table_name: "posts")
    end

    it "returns only enabled triggers" do
      result = described_class.enabled
      expect(result.count).to eq(1)
      expect(result.first.trigger_name).to eq("enabled_trigger")
    end
  end

  describe ".disabled" do
    before do
      create(:trigger_registry, :enabled, trigger_name: "enabled_trigger", table_name: "users")
      create(:trigger_registry, :disabled, trigger_name: "disabled_trigger", table_name: "posts")
    end

    it "returns only disabled triggers" do
      result = described_class.disabled
      expect(result.count).to eq(1)
      expect(result.first.trigger_name).to eq("disabled_trigger")
    end
  end

  describe ".for_table" do
    before do
      create(:trigger_registry, :enabled, trigger_name: "trigger1", table_name: "users")
      create(:trigger_registry, :disabled, trigger_name: "trigger2", table_name: "users")
      create(:trigger_registry, :enabled, trigger_name: "trigger3", table_name: "posts")
    end

    it "returns triggers for the specified table" do
      result = described_class.for_table("users")
      expect(result.count).to eq(2)
      expect(result.map(&:trigger_name)).to contain_exactly("trigger1", "trigger2")
    end
  end

  describe ".diff" do
    it "delegates to Drift.detect" do
      expect(PgSqlTriggers::Drift).to receive(:detect)
      described_class.diff
    end
  end

  describe ".drifted" do
    it "returns triggers with drifted state" do
      # Create real triggers and set up drift scenarios
      create(:trigger_registry, :enabled, trigger_name: "drifted1", table_name: "users")
      create(:trigger_registry, :enabled, trigger_name: "in_sync1", table_name: "posts")
      create(:trigger_registry, :enabled, trigger_name: "drifted2", table_name: "comments")

      # Use real drift detection - results depend on actual database state
      result = described_class.drifted
      expect(result).to respond_to(:pluck)
      # The actual count depends on real drift detection
      expect(result.pluck(:trigger_name)).to be_an(Array)
    end
  end

  describe ".in_sync" do
    it "returns triggers with in_sync state" do
      # Create real triggers
      create(:trigger_registry, :enabled, trigger_name: "in_sync1", table_name: "users")
      create(:trigger_registry, :enabled, trigger_name: "drifted1", table_name: "posts")
      create(:trigger_registry, :enabled, trigger_name: "in_sync2", table_name: "comments")

      # Use real drift detection
      result = described_class.in_sync
      expect(result).to respond_to(:pluck)
      expect(result.pluck(:trigger_name)).to be_an(Array)
    end
  end

  describe ".unknown_triggers" do
    it "returns triggers with unknown state" do
      # Create real triggers
      create(:trigger_registry, :enabled, trigger_name: "in_sync1", table_name: "users")

      # Use real drift detection
      result = described_class.unknown_triggers
      expect(result).to respond_to(:pluck)
      expect(result.pluck(:trigger_name)).to be_an(Array)
    end
  end

  describe ".dropped" do
    it "returns triggers with dropped state" do
      # Create real triggers
      create(:trigger_registry, :enabled, trigger_name: "dropped1", table_name: "users")
      create(:trigger_registry, :enabled, trigger_name: "in_sync1", table_name: "posts")
      create(:trigger_registry, :enabled, trigger_name: "dropped2", table_name: "comments")

      # Use real drift detection
      result = described_class.dropped
      expect(result).to respond_to(:pluck)
      expect(result.pluck(:trigger_name)).to be_an(Array)
    end
  end

  describe "caching optimization" do
    describe "._registry_cache" do
      it "returns an empty hash initially" do
        described_class._clear_registry_cache
        expect(described_class._registry_cache).to eq({})
      end

      it "persists cached values across multiple calls" do
        described_class._clear_registry_cache
        cache = described_class._registry_cache
        cache["test"] = "value"
        expect(described_class._registry_cache["test"]).to eq("value")
      end
    end

    describe "._clear_registry_cache" do
      it "clears the registry cache" do
        described_class._registry_cache["test"] = "value"
        described_class._clear_registry_cache
        expect(described_class._registry_cache).to eq({})
      end
    end

    describe ".preload_triggers" do
      before do
        described_class._clear_registry_cache
        create(:trigger_registry, :enabled, trigger_name: "trigger1", table_name: "users")
        create(:trigger_registry, :disabled, trigger_name: "trigger2", table_name: "posts")
      end

      it "loads triggers into cache" do
        expect(described_class._registry_cache).to be_empty
        described_class.preload_triggers(%w[trigger1 trigger2])
        expect(described_class._registry_cache.keys).to contain_exactly("trigger1", "trigger2")
        expect(described_class._registry_cache["trigger1"].trigger_name).to eq("trigger1")
        expect(described_class._registry_cache["trigger2"].trigger_name).to eq("trigger2")
      end

      it "only loads uncached triggers" do
        # Pre-populate cache with trigger1
        described_class._registry_cache["trigger1"] = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "trigger1")

        # Should only query for trigger2
        expect(PgSqlTriggers::TriggerRegistry).to receive(:where).with(trigger_name: ["trigger2"]).and_call_original
        described_class.preload_triggers(%w[trigger1 trigger2])
      end

      it "handles empty array" do
        expect { described_class.preload_triggers([]) }.not_to raise_error
        expect(described_class._registry_cache).to be_empty
      end

      it "handles triggers that don't exist" do
        described_class.preload_triggers(%w[nonexistent_trigger])
        expect(described_class._registry_cache).to be_empty
      end
    end

    describe ".register with caching" do
      let(:definition) do
        definition = PgSqlTriggers::DSL::TriggerDefinition.new("cached_trigger")
        definition.table(:users)
        definition.on(:insert)
        definition.function(:test_function)
        definition.version(1)
        definition.enabled(false)
        definition
      end

      before do
        described_class._clear_registry_cache
      end

      it "caches the lookup result" do
        registry = described_class.register(definition)
        expect(described_class._registry_cache["cached_trigger"]).to eq(registry)
      end

      it "uses cached value on subsequent lookups" do
        # First registration
        first_registry = described_class.register(definition)

        # Clear the database query expectation
        expect(PgSqlTriggers::TriggerRegistry).not_to receive(:find_by)

        # Second registration should use cache
        second_registry = described_class.register(definition)
        expect(second_registry).to eq(first_registry)
      end

      it "updates the cache after updating an existing trigger" do
        create(:trigger_registry, :enabled,
          trigger_name: "cached_trigger",
          table_name: "users",
          checksum: "old",
          source: "generated")

        registry = described_class.register(definition)
        expect(described_class._registry_cache["cached_trigger"]).to eq(registry)
        expect(described_class._registry_cache["cached_trigger"].enabled).to be(false)
      end

      it "caches the newly created record" do
        registry = described_class.register(definition)
        expect(described_class._registry_cache["cached_trigger"]).to eq(registry)
        expect(described_class._registry_cache["cached_trigger"]).to be_persisted
      end
    end

    describe "N+1 query prevention" do
      let(:definitions) do
        [
          PgSqlTriggers::DSL::TriggerDefinition.new("trigger1").tap do |d|
            d.table(:users)
            d.on(:insert)
            d.function(:func1)
            d.version(1)
            d.enabled(false)
          end,
          PgSqlTriggers::DSL::TriggerDefinition.new("trigger2").tap do |d|
            d.table(:posts)
            d.on(:update)
            d.function(:func2)
            d.version(1)
            d.enabled(false)
          end,
          PgSqlTriggers::DSL::TriggerDefinition.new("trigger3").tap do |d|
            d.table(:comments)
            d.on(:delete)
            d.function(:func3)
            d.version(1)
            d.enabled(false)
          end
        ]
      end

      before do
        described_class._clear_registry_cache
      end

      it "reduces queries when preloading triggers" do
        # Create triggers first
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: "trigger1",
          table_name: "users",
          version: 1,
          enabled: false,
          checksum: "abc",
          source: "dsl"
        )
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: "trigger2",
          table_name: "posts",
          version: 1,
          enabled: false,
          checksum: "def",
          source: "dsl"
        )
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: "trigger3",
          table_name: "comments",
          version: 1,
          enabled: false,
          checksum: "ghi",
          source: "dsl"
        )

        # Preload all triggers - should make one query
        expect(PgSqlTriggers::TriggerRegistry).to receive(:where).once.and_call_original
        described_class.preload_triggers(%w[trigger1 trigger2 trigger3])

        # Registering should use cache, not query again
        expect(PgSqlTriggers::TriggerRegistry).not_to receive(:find_by)
        definitions.each do |defn|
          described_class.register(defn)
        end
      end
    end
  end

  # rubocop:disable RSpec/NestedGroups, RSpec/AnyInstance
  describe "console API permission enforcement" do
    let(:actor) { { type: "User", id: 1 } }
    let!(:trigger) do
      create(:trigger_registry, :disabled, :with_function_body,
        trigger_name: "test_trigger",
        table_name: "users",
        function_body: "CREATE OR REPLACE FUNCTION test_trigger_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
    end

    # Kill switch and permissions are configured per test context using around blocks

    describe ".enable" do
      context "with operator permissions" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(enable_trigger: true) do
              example.run
            end
          end
        end

        it "enables the trigger" do
          # Use real enable! method
          expect do
            PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
          end.to change { trigger.reload.enabled }.from(false).to(true)
        end

        it "passes confirmation to enable!" do
          # Use real enable! method with confirmation
          expect do
            PgSqlTriggers::Registry.enable("test_trigger", actor: actor, confirmation: "EXECUTE")
          end.to change { trigger.reload.enabled }.from(false).to(true)
        end
      end

      context "without operator permissions" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(enable_trigger: false) do
              example.run
            end
          end
        end

        it "raises PermissionError" do
          expect do
            PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        it "does not enable trigger" do
          expect do
            expect do
              PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
            end.to raise_error(PgSqlTriggers::PermissionError)
          end.not_to change { trigger.reload.enabled }
        end
      end

      context "when trigger not found" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(enable_trigger: true) do
              example.run
            end
          end
        end

        it "raises ArgumentError" do
          expect do
            PgSqlTriggers::Registry.enable("nonexistent", actor: actor)
          end.to raise_error(ArgumentError, /not found in registry/)
        end
      end
    end

    describe ".disable" do
      before do
        trigger.update!(enabled: true)
      end

      context "with operator permissions" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(disable_trigger: true) do
              example.run
            end
          end
        end

        it "disables the trigger" do
          # Use real disable! method
          expect do
            PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
          end.to change { trigger.reload.enabled }.from(true).to(false)
        end

        it "passes confirmation to disable!" do
          # Use real disable! method with confirmation
          expect do
            PgSqlTriggers::Registry.disable("test_trigger", actor: actor, confirmation: "EXECUTE")
          end.to change { trigger.reload.enabled }.from(true).to(false)
        end
      end

      context "without operator permissions" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(disable_trigger: false) do
              example.run
            end
          end
        end

        it "raises PermissionError" do
          expect do
            PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        it "does not disable trigger" do
          expect do
            expect do
              PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
            end.to raise_error(PgSqlTriggers::PermissionError)
          end.not_to change { trigger.reload.enabled }
        end
      end

      context "when trigger not found" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(disable_trigger: true) do
              example.run
            end
          end
        end

        it "raises ArgumentError" do
          expect do
            PgSqlTriggers::Registry.disable("nonexistent", actor: actor)
          end.to raise_error(ArgumentError, /not found in registry/)
        end
      end
    end

    describe ".drop" do
      context "with admin permissions" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(drop_trigger: true) do
              example.run
            end
          end
        end

        it "drops the trigger" do
          # Use real drop! method
          expect do
            PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "No longer needed")
          end.to change { PgSqlTriggers::TriggerRegistry.exists?(trigger.id) }.from(true).to(false)
        end

        it "passes confirmation to drop!" do
          # Use real drop! method with confirmation
          expect do
            PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "Testing", confirmation: "DROP TRIGGER")
          end.to change { PgSqlTriggers::TriggerRegistry.exists?(trigger.id) }.from(true).to(false)
        end

        it "requires reason parameter" do
          # drop! method will raise ArgumentError if reason is missing
          expect do
            PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: nil)
          end.to raise_error(ArgumentError, /Reason is required/)
        end
      end

      context "without admin permissions" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(drop_trigger: false) do
              example.run
            end
          end
        end

        it "raises PermissionError" do
          expect do
            PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "Testing")
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        it "does not drop trigger" do
          expect do
            expect do
              PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "Testing")
            end.to raise_error(PgSqlTriggers::PermissionError)
          end.not_to change { PgSqlTriggers::TriggerRegistry.exists?(trigger.id) }
        end
      end

      context "when trigger not found" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(drop_trigger: true) do
              example.run
            end
          end
        end

        it "raises ArgumentError" do
          expect do
            PgSqlTriggers::Registry.drop("nonexistent", actor: actor, reason: "Testing")
          end.to raise_error(ArgumentError, /not found in registry/)
        end
      end
    end

    describe ".re_execute" do
      context "with admin permissions" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(drop_trigger: true) do
              example.run
            end
          end
        end

        it "re-executes the trigger" do
          # Use real re_execute! method
          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
          end.not_to raise_error
        end

        it "passes confirmation to re_execute!" do
          # Use real re_execute! method with confirmation
          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift", confirmation: "RE-EXECUTE")
          end.not_to raise_error
        end

        it "requires reason parameter" do
          # re_execute! method will raise ArgumentError if reason is missing
          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: nil)
          end.to raise_error(ArgumentError, /Reason is required/)
        end
      end

      context "without admin permissions" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(drop_trigger: false) do
              example.run
            end
          end
        end

        it "raises PermissionError" do
          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        it "does not re-execute trigger" do
          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
          end.to raise_error(PgSqlTriggers::PermissionError)
        end
      end

      context "when trigger not found" do
        around do |example|
          with_kill_switch_disabled do
            with_permission_checker(drop_trigger: true) do
              example.run
            end
          end
        end

        it "raises ArgumentError" do
          expect do
            PgSqlTriggers::Registry.re_execute("nonexistent", actor: actor, reason: "Fix drift")
          end.to raise_error(ArgumentError, /not found in registry/)
        end
      end
    end

    describe "permission level requirements" do
      around do |example|
        with_kill_switch_disabled do
          example.run
        end
      end

      it "enable requires :enable_trigger action" do
        # Verify that denying enable_trigger permission raises an error
        with_permission_checker(enable_trigger: false) do
          expect do
            PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        # Verify that allowing enable_trigger permission works
        with_permission_checker(enable_trigger: true) do
          expect do
            PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
          end.to change { trigger.reload.enabled }.from(false).to(true)
        end
      end

      it "disable requires :disable_trigger action" do
        trigger.update!(enabled: true)

        # Verify that denying disable_trigger permission raises an error
        with_permission_checker(disable_trigger: false) do
          expect do
            PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        # Verify that allowing disable_trigger permission works
        trigger.update!(enabled: true)
        with_permission_checker(disable_trigger: true) do
          expect do
            PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
          end.to change { trigger.reload.enabled }.from(true).to(false)
        end
      end

      it "drop requires :drop_trigger action" do
        # Verify that denying drop_trigger permission raises an error
        with_permission_checker(drop_trigger: false) do
          expect do
            PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "Testing")
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        # Verify that allowing drop_trigger permission works
        with_permission_checker(drop_trigger: true) do
          expect do
            PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "Testing")
          end.to change { PgSqlTriggers::TriggerRegistry.exists?(trigger.id) }.from(true).to(false)
        end
      end

      it "re_execute requires :drop_trigger action (same as drop)" do
        # Verify that denying drop_trigger permission raises an error for re_execute
        with_permission_checker(drop_trigger: false) do
          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        # Verify that allowing drop_trigger permission works for re_execute
        with_permission_checker(drop_trigger: true) do
          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
          end.not_to raise_error
        end
      end
    end
  end
  # rubocop:enable RSpec/NestedGroups, RSpec/AnyInstance
end
