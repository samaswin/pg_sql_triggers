# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Drift::Detector do
  let(:trigger_name) { "test_trigger" }
  let(:table_name) { "users" }
  let(:function_name) { "test_function" }
  let(:function_body) { "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;" }
  let(:condition) { "NEW.email IS NOT NULL" }

  describe ".detect" do
    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when trigger is in sync" do
      let!(:registry_entry) do
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: trigger_name,
          table_name: table_name,
          version: 1,
          enabled: true,
          source: "dsl",
          checksum: calculate_checksum(trigger_name, table_name, 1, function_body, condition),
          definition: {}.to_json,
          function_body: function_body,
          condition: condition
        )
      end
      let(:db_trigger) do
        {
          "trigger_name" => trigger_name,
          "table_name" => table_name,
          "function_name" => function_name,
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER #{trigger_name} BEFORE INSERT ON #{table_name} FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION #{function_name}();",
          "enabled" => "O"
        }
      end

      before do
        allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
          .with(trigger_name)
          .and_return(db_trigger)
      end

      it "returns IN_SYNC state" do
        result = described_class.detect(trigger_name)
        expect(result[:state]).to eq(PgSqlTriggers::DRIFT_STATE_IN_SYNC)
        expect(result[:checksum_match]).to be true
        expect(result[:details]).to include("in sync")
      end

      it "includes registry entry and db trigger" do
        result = described_class.detect(trigger_name)
        expect(result[:registry_entry]).to eq(registry_entry)
        expect(result[:db_trigger]).to eq(db_trigger)
      end
    end

    context "when trigger has drifted" do
      let(:modified_function_body) { "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN OLD; END; $$ LANGUAGE plpgsql;" }
      let(:db_trigger) do
        {
          "trigger_name" => trigger_name,
          "table_name" => table_name,
          "function_name" => function_name,
          "function_definition" => modified_function_body,
          "trigger_definition" => "CREATE TRIGGER #{trigger_name} BEFORE INSERT ON #{table_name} FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION #{function_name}();",
          "enabled" => "O"
        }
      end

      before do
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: trigger_name,
          table_name: table_name,
          version: 1,
          enabled: true,
          source: "dsl",
          checksum: calculate_checksum(trigger_name, table_name, 1, function_body, condition),
          definition: {}.to_json,
          function_body: function_body,
          condition: condition
        )

        allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
          .with(trigger_name)
          .and_return(db_trigger)
      end

      it "returns DRIFTED state with checksum mismatch" do
        result = described_class.detect(trigger_name)
        expect(result[:state]).to eq(PgSqlTriggers::DRIFT_STATE_DRIFTED)
        expect(result[:checksum_match]).to be false
        expect(result[:details]).to include("drifted")
      end
    end

    context "when trigger is missing from database" do
      let!(:registry_entry) do
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: trigger_name,
          table_name: table_name,
          version: 1,
          enabled: true,
          source: "dsl",
          checksum: calculate_checksum(trigger_name, table_name, 1, function_body, condition),
          definition: {}.to_json,
          function_body: function_body,
          condition: condition
        )
      end

      before do
        allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
          .with(trigger_name)
          .and_return(nil)
      end

      it "returns DROPPED state" do
        result = described_class.detect(trigger_name)
        expect(result[:state]).to eq(PgSqlTriggers::DRIFT_STATE_DROPPED)
        expect(result[:registry_entry]).to eq(registry_entry)
        expect(result[:db_trigger]).to be_nil
        expect(result[:details]).to include("not in database")
      end
    end

    context "when trigger is unknown (external)" do
      let(:db_trigger) do
        {
          "trigger_name" => trigger_name,
          "table_name" => table_name,
          "function_name" => function_name,
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER #{trigger_name} BEFORE INSERT ON #{table_name} FOR EACH ROW EXECUTE FUNCTION #{function_name}();",
          "enabled" => "O"
        }
      end

      before do
        allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
          .with(trigger_name)
          .and_return(db_trigger)
      end

      it "returns UNKNOWN state" do
        result = described_class.detect(trigger_name)
        expect(result[:state]).to eq(PgSqlTriggers::DRIFT_STATE_UNKNOWN)
        expect(result[:registry_entry]).to be_nil
        expect(result[:db_trigger]).to eq(db_trigger)
        expect(result[:details]).to include("external")
      end
    end

    context "when trigger is disabled" do
      let(:db_trigger) do
        {
          "trigger_name" => trigger_name,
          "table_name" => table_name,
          "function_name" => function_name,
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER #{trigger_name} BEFORE INSERT ON #{table_name} FOR EACH ROW EXECUTE FUNCTION #{function_name}();",
          "enabled" => "D"
        }
      end

      before do
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: trigger_name,
          table_name: table_name,
          version: 1,
          enabled: false,
          source: "dsl",
          checksum: calculate_checksum(trigger_name, table_name, 1, function_body, condition),
          definition: {}.to_json,
          function_body: function_body,
          condition: condition
        )

        allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
          .with(trigger_name)
          .and_return(db_trigger)
      end

      it "returns DISABLED state" do
        result = described_class.detect(trigger_name)
        expect(result[:state]).to eq(PgSqlTriggers::DRIFT_STATE_DISABLED)
        expect(result[:details]).to include("disabled")
      end
    end

    context "when trigger is manual override" do
      let(:db_trigger) do
        {
          "trigger_name" => trigger_name,
          "table_name" => table_name,
          "function_name" => function_name,
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER #{trigger_name} BEFORE INSERT ON #{table_name} FOR EACH ROW EXECUTE FUNCTION #{function_name}();",
          "enabled" => "O"
        }
      end

      before do
        PgSqlTriggers::TriggerRegistry.create!(
          trigger_name: trigger_name,
          table_name: table_name,
          version: 1,
          enabled: true,
          source: "manual_sql",
          checksum: calculate_checksum(trigger_name, table_name, 1, function_body, condition),
          definition: {}.to_json,
          function_body: function_body,
          condition: condition
        )

        allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
          .with(trigger_name)
          .and_return(db_trigger)
      end

      it "returns MANUAL_OVERRIDE state" do
        result = described_class.detect(trigger_name)
        expect(result[:state]).to eq(PgSqlTriggers::DRIFT_STATE_MANUAL_OVERRIDE)
        expect(result[:details]).to include("manual")
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe ".detect_all" do
    let(:db_triggers) do
      [
        {
          "trigger_name" => "in_sync_trigger",
          "table_name" => table_name,
          "function_name" => function_name,
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER in_sync_trigger BEFORE INSERT ON #{table_name} FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION #{function_name}();",
          "enabled" => "O"
        },
        {
          "trigger_name" => "unknown_trigger",
          "table_name" => table_name,
          "function_name" => "unknown_function",
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER unknown_trigger BEFORE INSERT ON #{table_name} FOR EACH ROW EXECUTE FUNCTION unknown_function();",
          "enabled" => "O"
        }
      ]
    end

    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "in_sync_trigger",
        table_name: table_name,
        version: 1,
        enabled: true,
        source: "dsl",
        checksum: calculate_checksum("in_sync_trigger", table_name, 1, function_body, condition),
        definition: {}.to_json,
        function_body: function_body,
        condition: condition
      )

      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "dropped_trigger",
        table_name: table_name,
        version: 1,
        enabled: true,
        source: "dsl",
        checksum: calculate_checksum("dropped_trigger", table_name, 1, function_body, condition),
        definition: {}.to_json,
        function_body: function_body,
        condition: condition
      )

      allow(PgSqlTriggers::Drift::DbQueries).to receive(:all_triggers).and_return(db_triggers)
      allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger) do |name|
        db_triggers.find { |t| t["trigger_name"] == name }
      end
    end

    it "detects all triggers correctly" do
      results = described_class.detect_all

      expect(results.count).to eq(3)

      in_sync = results.find { |r| r[:registry_entry]&.trigger_name == "in_sync_trigger" }
      expect(in_sync[:state]).to eq(PgSqlTriggers::DRIFT_STATE_IN_SYNC)

      dropped = results.find { |r| r[:registry_entry]&.trigger_name == "dropped_trigger" }
      expect(dropped[:state]).to eq(PgSqlTriggers::DRIFT_STATE_DROPPED)

      unknown = results.find { |r| r[:db_trigger]&.dig("trigger_name") == "unknown_trigger" }
      expect(unknown[:state]).to eq(PgSqlTriggers::DRIFT_STATE_UNKNOWN)
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe ".detect_for_table" do
    let(:users_db_triggers) do
      [
        {
          "trigger_name" => "users_trigger_1",
          "table_name" => "users",
          "function_name" => function_name,
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER users_trigger_1 BEFORE INSERT ON users FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION #{function_name}();",
          "enabled" => "O"
        }
      ]
    end

    before do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "users_trigger_1",
        table_name: "users",
        version: 1,
        enabled: true,
        source: "dsl",
        checksum: calculate_checksum("users_trigger_1", "users", 1, function_body, condition),
        definition: {}.to_json,
        function_body: function_body,
        condition: condition
      )

      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "posts_trigger_1",
        table_name: "posts",
        version: 1,
        enabled: true,
        source: "dsl",
        checksum: calculate_checksum("posts_trigger_1", "posts", 1, function_body, condition),
        definition: {}.to_json,
        function_body: function_body,
        condition: condition
      )

      allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_triggers_for_table)
        .with("users")
        .and_return(users_db_triggers)
      allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
        .with("users_trigger_1")
        .and_return(users_db_triggers.first)
    end

    it "detects triggers only for the specified table" do
      results = described_class.detect_for_table("users")

      expect(results.count).to eq(1)
      expect(results.first[:registry_entry].trigger_name).to eq("users_trigger_1")
      expect(results.first[:state]).to eq(PgSqlTriggers::DRIFT_STATE_IN_SYNC)
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  private

  def calculate_checksum(trigger_name, table_name, version, function_body, condition)
    require "digest"
    Digest::SHA256.hexdigest([
      trigger_name,
      table_name,
      version,
      function_body || "",
      condition || ""
    ].join)
  end
end
