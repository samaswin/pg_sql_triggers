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
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: "test_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "old",
          source: "generated"
        )
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
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger1",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger2",
        table_name: "posts",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "generated"
      )
    end

    it "returns all triggers" do
      result = described_class.list
      expect(result.count).to eq(2)
      expect(result.map(&:trigger_name)).to contain_exactly("trigger1", "trigger2")
    end
  end

  describe ".enabled" do
    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "enabled_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "disabled_trigger",
        table_name: "posts",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "dsl"
      )
    end

    it "returns only enabled triggers" do
      result = described_class.enabled
      expect(result.count).to eq(1)
      expect(result.first.trigger_name).to eq("enabled_trigger")
    end
  end

  describe ".disabled" do
    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "enabled_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "disabled_trigger",
        table_name: "posts",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "dsl"
      )
    end

    it "returns only disabled triggers" do
      result = described_class.disabled
      expect(result.count).to eq(1)
      expect(result.first.trigger_name).to eq("disabled_trigger")
    end
  end

  describe ".for_table" do
    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger1",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger2",
        table_name: "users",
        version: 1,
        enabled: false,
        checksum: "def",
        source: "dsl"
      )
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "trigger3",
        table_name: "posts",
        version: 1,
        enabled: true,
        checksum: "ghi",
        source: "dsl"
      )
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
      allow(PgSqlTriggers::Drift::Detector).to receive(:detect_all).and_return([
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_DRIFTED, trigger_name: "drifted1" },
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_IN_SYNC, trigger_name: "in_sync1" },
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_DRIFTED, trigger_name: "drifted2" }
                                                                               ])

      result = described_class.drifted
      expect(result.count).to eq(2)
      expect(result.pluck(:trigger_name)).to contain_exactly("drifted1", "drifted2")
    end
  end

  describe ".in_sync" do
    it "returns triggers with in_sync state" do
      allow(PgSqlTriggers::Drift::Detector).to receive(:detect_all).and_return([
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_IN_SYNC, trigger_name: "in_sync1" },
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_DRIFTED, trigger_name: "drifted1" },
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_IN_SYNC, trigger_name: "in_sync2" }
                                                                               ])

      result = described_class.in_sync
      expect(result.count).to eq(2)
      expect(result.pluck(:trigger_name)).to contain_exactly("in_sync1", "in_sync2")
    end
  end

  describe ".unknown_triggers" do
    it "returns triggers with unknown state" do
      allow(PgSqlTriggers::Drift::Detector).to receive(:detect_all).and_return([
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_UNKNOWN, trigger_name: "unknown1" },
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_IN_SYNC, trigger_name: "in_sync1" },
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_UNKNOWN, trigger_name: "unknown2" }
                                                                               ])

      result = described_class.unknown_triggers
      expect(result.count).to eq(2)
      expect(result.pluck(:trigger_name)).to contain_exactly("unknown1", "unknown2")
    end
  end

  describe ".dropped" do
    it "returns triggers with dropped state" do
      allow(PgSqlTriggers::Drift::Detector).to receive(:detect_all).and_return([
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_DROPPED, trigger_name: "dropped1" },
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_IN_SYNC, trigger_name: "in_sync1" },
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_DROPPED, trigger_name: "dropped2" }
                                                                               ])

      result = described_class.dropped
      expect(result.count).to eq(2)
      expect(result.pluck(:trigger_name)).to contain_exactly("dropped1", "dropped2")
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
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: "trigger1",
          table_name: "users",
          version: 1,
          enabled: true,
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
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: "cached_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "old",
          source: "generated"
        )

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

  # rubocop:disable RSpec/NestedGroups, RSpec/AnyInstance, RSpec/StubbedMock
  describe "console API permission enforcement" do
    let(:actor) { { type: "User", id: 1 } }
    let!(:trigger) do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: false,
        checksum: "abc",
        source: "dsl",
        function_body: "CREATE OR REPLACE FUNCTION test_trigger_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      )
    end

    before do
      # Stub kill switch by default
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # Stub logger
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
    end

    describe ".enable" do
      context "with operator permissions" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :enable_trigger)
            .and_return(true)
        end

        it "checks permissions before enabling" do
          expect(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :enable_trigger)

          PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
        end

        it "enables the trigger" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:enable!)
            .with(confirmation: nil)

          PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
        end

        it "passes confirmation to enable!" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:enable!)
            .with(confirmation: "EXECUTE")

          PgSqlTriggers::Registry.enable("test_trigger", actor: actor, confirmation: "EXECUTE")
        end
      end

      context "without operator permissions" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :enable_trigger)
            .and_raise(PgSqlTriggers::PermissionError.new("Permission denied"))
        end

        it "raises PermissionError" do
          expect do
            PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        it "does not enable trigger" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:enable!)

          expect do
            PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
          end.to raise_error(PgSqlTriggers::PermissionError)
        end
      end

      context "when trigger not found" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :enable_trigger)
            .and_return(true)
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
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :disable_trigger)
            .and_return(true)
        end

        it "checks permissions before disabling" do
          expect(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :disable_trigger)

          PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
        end

        it "disables the trigger" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:disable!)
            .with(confirmation: nil)

          PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
        end

        it "passes confirmation to disable!" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:disable!)
            .with(confirmation: "EXECUTE")

          PgSqlTriggers::Registry.disable("test_trigger", actor: actor, confirmation: "EXECUTE")
        end
      end

      context "without operator permissions" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :disable_trigger)
            .and_raise(PgSqlTriggers::PermissionError.new("Permission denied"))
        end

        it "raises PermissionError" do
          expect do
            PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
          end.to raise_error(PgSqlTriggers::PermissionError)
        end

        it "does not disable trigger" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:disable!)

          expect do
            PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
          end.to raise_error(PgSqlTriggers::PermissionError)
        end
      end

      context "when trigger not found" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :disable_trigger)
            .and_return(true)
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
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :drop_trigger)
            .and_return(true)
        end

        it "checks permissions before dropping" do
          expect(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :drop_trigger)

          PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "No longer needed")
        end

        it "drops the trigger" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:drop!)
            .with(reason: "No longer needed", confirmation: nil, actor: actor)

          PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "No longer needed")
        end

        it "passes confirmation to drop!" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:drop!)
            .with(reason: "Testing", confirmation: "DROP TRIGGER", actor: actor)

          PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "Testing", confirmation: "DROP TRIGGER")
        end

        it "requires reason parameter" do
          # drop! method will raise ArgumentError if reason is missing
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:drop!)
            .with(reason: nil, confirmation: nil, actor: actor)
            .and_raise(ArgumentError.new("Reason is required"))

          expect do
            PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: nil)
          end.to raise_error(ArgumentError, /Reason is required/)
        end
      end

      context "without admin permissions" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :drop_trigger)
            .and_raise(PgSqlTriggers::PermissionError.new("Permission denied: admin role required"))
        end

        it "raises PermissionError" do
          expect do
            PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "Testing")
          end.to raise_error(PgSqlTriggers::PermissionError, /admin role required/)
        end

        it "does not drop trigger" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:drop!)

          expect do
            PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "Testing")
          end.to raise_error(PgSqlTriggers::PermissionError)
        end
      end

      context "when trigger not found" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :drop_trigger)
            .and_return(true)
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
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :drop_trigger)
            .and_return(true)
          allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:drift_result)
            .and_return({ state: :drifted })
        end

        it "checks permissions before re-executing" do
          expect(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :drop_trigger)

          PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
        end

        it "re-executes the trigger" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:re_execute!)
            .with(reason: "Fix drift", confirmation: nil, actor: actor)

          PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
        end

        it "passes confirmation to re_execute!" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:re_execute!)
            .with(reason: "Fix drift", confirmation: "RE-EXECUTE", actor: actor)

          PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift", confirmation: "RE-EXECUTE")
        end

        it "requires reason parameter" do
          # re_execute! method will raise ArgumentError if reason is missing
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
            .to receive(:re_execute!)
            .with(reason: nil, confirmation: nil, actor: actor)
            .and_raise(ArgumentError.new("Reason is required"))

          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: nil)
          end.to raise_error(ArgumentError, /Reason is required/)
        end
      end

      context "without admin permissions" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :drop_trigger)
            .and_raise(PgSqlTriggers::PermissionError.new("Permission denied: admin role required"))
        end

        it "raises PermissionError" do
          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
          end.to raise_error(PgSqlTriggers::PermissionError, /admin role required/)
        end

        it "does not re-execute trigger" do
          expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:re_execute!)

          expect do
            PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
          end.to raise_error(PgSqlTriggers::PermissionError)
        end
      end

      context "when trigger not found" do
        before do
          allow(PgSqlTriggers::Permissions).to receive(:check!)
            .with(actor, :drop_trigger)
            .and_return(true)
        end

        it "raises ArgumentError" do
          expect do
            PgSqlTriggers::Registry.re_execute("nonexistent", actor: actor, reason: "Fix drift")
          end.to raise_error(ArgumentError, /not found in registry/)
        end
      end
    end

    describe "permission level requirements" do
      it "enable requires :enable_trigger action" do
        expect(PgSqlTriggers::Permissions).to receive(:check!)
          .with(actor, :enable_trigger)

        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!)

        PgSqlTriggers::Registry.enable("test_trigger", actor: actor)
      end

      it "disable requires :disable_trigger action" do
        expect(PgSqlTriggers::Permissions).to receive(:check!)
          .with(actor, :disable_trigger)

        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:disable!)

        PgSqlTriggers::Registry.disable("test_trigger", actor: actor)
      end

      it "drop requires :drop_trigger action" do
        expect(PgSqlTriggers::Permissions).to receive(:check!)
          .with(actor, :drop_trigger)

        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:drop!)

        PgSqlTriggers::Registry.drop("test_trigger", actor: actor, reason: "Testing")
      end

      it "re_execute requires :drop_trigger action (same as drop)" do
        expect(PgSqlTriggers::Permissions).to receive(:check!)
          .with(actor, :drop_trigger)

        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:re_execute!)

        PgSqlTriggers::Registry.re_execute("test_trigger", actor: actor, reason: "Fix drift")
      end
    end
  end
  # rubocop:enable RSpec/NestedGroups, RSpec/AnyInstance, RSpec/StubbedMock
end
