# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Drift::Reporter do
  let(:trigger_name) { "test_trigger_reporter_#{SecureRandom.hex(4)}" }
  let(:table_name) { "users" }
  let(:function_body) { "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;" }
  let(:condition) { "NEW.email IS NOT NULL" }

  describe ".summary" do
    let(:db_triggers) do
      [
        {
          "trigger_name" => "in_sync_trigger",
          "table_name" => table_name,
          "function_name" => "test_function",
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER in_sync_trigger BEFORE INSERT ON #{table_name} FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION test_function();",
          "enabled" => "O"
        },
        {
          "trigger_name" => "drifted_trigger",
          "table_name" => table_name,
          "function_name" => "test_function",
          "function_definition" => "MODIFIED FUNCTION",
          "trigger_definition" => "CREATE TRIGGER drifted_trigger BEFORE INSERT ON #{table_name} FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION test_function();",
          "enabled" => "O"
        },
        {
          "trigger_name" => "disabled_trigger",
          "table_name" => table_name,
          "function_name" => "test_function",
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER disabled_trigger BEFORE INSERT ON #{table_name} FOR EACH ROW EXECUTE FUNCTION test_function();",
          "enabled" => "D"
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
      create(:trigger_registry, :enabled, :dsl_source, :in_sync,
             trigger_name: "in_sync_trigger",
             table_name: table_name,
             definition: {}.to_json,
             function_body: function_body,
             condition: condition)

      create(:trigger_registry, :enabled, :dsl_source, :in_sync,
             trigger_name: "drifted_trigger",
             table_name: table_name,
             definition: {}.to_json,
             function_body: function_body,
             condition: condition)

      create(:trigger_registry, :disabled, :dsl_source, :in_sync,
             trigger_name: "disabled_trigger",
             table_name: table_name,
             definition: {}.to_json,
             function_body: function_body,
             condition: condition)

      allow(PgSqlTriggers::Drift::DbQueries).to receive(:all_triggers).and_return(db_triggers)
      allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger) do |name|
        db_triggers.find { |t| t["trigger_name"] == name }
      end
    end

    it "returns accurate drift counts" do
      summary = described_class.summary

      expect(summary[:total]).to eq(4)
      expect(summary[:in_sync]).to eq(1)
      expect(summary[:drifted]).to eq(1)
      expect(summary[:disabled]).to eq(1)
      expect(summary[:unknown]).to eq(1)
      expect(summary[:dropped]).to eq(0)
      expect(summary[:manual_override]).to eq(0)
    end
  end

  describe ".report" do
    let(:db_trigger) do
      {
        "trigger_name" => trigger_name,
        "table_name" => table_name,
        "function_name" => "test_function",
        "function_definition" => function_body,
        "trigger_definition" => "CREATE TRIGGER #{trigger_name} BEFORE INSERT ON #{table_name} FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION test_function();",
        "enabled" => "O"
      }
    end

    before do
      create(:trigger_registry, :enabled, :dsl_source, :in_sync,
             trigger_name: trigger_name,
             table_name: table_name,
             definition: {}.to_json,
             function_body: function_body,
             condition: condition)

      allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
        .with(trigger_name)
        .and_return(db_trigger)
    end

    it "generates a detailed report for a trigger" do
      report = described_class.report(trigger_name)

      expect(report).to include("Drift Report: #{trigger_name}")
      expect(report).to include("State:")
      expect(report).to include("Details:")
      expect(report).to include("Registry Information:")
      expect(report).to include("Database Information:")
    end

    it "includes trigger state" do
      report = described_class.report(trigger_name)
      expect(report).to include("IN SYNC")
    end

    it "includes registry information" do
      report = described_class.report(trigger_name)
      expect(report).to include("Table: #{table_name}")
      expect(report).to include("Version: 1")
      expect(report).to include("Enabled: true")
      expect(report).to include("Source: dsl")
    end
  end

  describe ".diff" do
    before do
      create(:trigger_registry, :enabled, :dsl_source, :in_sync,
             trigger_name: trigger_name,
             table_name: table_name,
             definition: {}.to_json,
             function_body: function_body,
             condition: condition)
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when trigger has drifted" do
      let(:modified_function_body) { "MODIFIED FUNCTION BODY" }
      let(:db_trigger) do
        {
          "trigger_name" => trigger_name,
          "table_name" => table_name,
          "function_name" => "test_function",
          "function_definition" => modified_function_body,
          "trigger_definition" => "CREATE TRIGGER #{trigger_name} BEFORE INSERT ON #{table_name} FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION test_function();",
          "enabled" => "O"
        }
      end

      before do
        allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
          .with(trigger_name)
          .and_return(db_trigger)
      end

      it "generates a diff comparison" do
        diff = described_class.diff(trigger_name)

        expect(diff).to include("Drift Comparison:")
        expect(diff).to include("Version:")
        expect(diff).to include("Checksum:")
        expect(diff).to include("Function:")
        expect(diff).to include("Registry Function Body:")
        expect(diff).to include("Database Function Definition:")
      end

      it "shows registry and database function bodies" do
        diff = described_class.diff(trigger_name)

        expect(diff).to include(function_body)
        expect(diff).to include(modified_function_body)
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers

    context "when trigger is in sync" do
      let(:db_trigger) do
        {
          "trigger_name" => trigger_name,
          "table_name" => table_name,
          "function_name" => "test_function",
          "function_definition" => function_body,
          "trigger_definition" => "CREATE TRIGGER #{trigger_name} BEFORE INSERT ON #{table_name} FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION test_function();",
          "enabled" => "O"
        }
      end

      before do
        allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
          .with(trigger_name)
          .and_return(db_trigger)
      end

      it "returns no drift message" do
        diff = described_class.diff(trigger_name)
        expect(diff).to eq("No drift detected")
      end
    end
  end

  describe ".drifted_list" do
    let(:db_triggers) do
      [
        {
          "trigger_name" => "drifted_trigger",
          "table_name" => table_name,
          "function_name" => "test_function",
          "function_definition" => "MODIFIED FUNCTION",
          "trigger_definition" => "CREATE TRIGGER drifted_trigger BEFORE INSERT ON #{table_name} FOR EACH ROW EXECUTE FUNCTION test_function();",
          "enabled" => "O"
        }
      ]
    end

    before do
      create(:trigger_registry, :enabled, :dsl_source, :in_sync,
             trigger_name: "drifted_trigger",
             table_name: table_name,
             definition: {}.to_json,
             function_body: function_body,
             condition: condition)

      allow(PgSqlTriggers::Drift::DbQueries).to receive(:all_triggers).and_return(db_triggers)
      allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger)
        .with("drifted_trigger")
        .and_return(db_triggers.first)
    end

    it "returns a list of drifted triggers" do
      list = described_class.drifted_list

      expect(list).to include("Drifted Triggers (1):")
      expect(list).to include("drifted_trigger")
    end

    context "when no drifted triggers" do
      before do
        allow(PgSqlTriggers::Drift::DbQueries).to receive(:all_triggers).and_return([])
        allow(PgSqlTriggers::TriggerRegistry).to receive(:all).and_return([])
      end

      it "returns no drifted triggers message" do
        list = described_class.drifted_list
        expect(list).to eq("No drifted triggers found")
      end
    end
  end

  describe ".problematic_list" do
    let(:db_triggers) do
      [
        {
          "trigger_name" => "drifted_trigger",
          "table_name" => table_name,
          "function_name" => "test_function",
          "function_definition" => "MODIFIED FUNCTION",
          "trigger_definition" => "CREATE TRIGGER drifted_trigger BEFORE INSERT ON #{table_name} FOR EACH ROW EXECUTE FUNCTION test_function();",
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
      create(:trigger_registry, :enabled, :dsl_source, :in_sync,
             trigger_name: "drifted_trigger",
             table_name: table_name,
             definition: {}.to_json,
             function_body: function_body,
             condition: condition)

      create(:trigger_registry, :enabled, :dsl_source, :in_sync,
             trigger_name: "dropped_trigger",
             table_name: table_name,
             definition: {}.to_json,
             function_body: function_body,
             condition: condition)

      allow(PgSqlTriggers::Drift::DbQueries).to receive(:all_triggers).and_return(db_triggers)
      allow(PgSqlTriggers::Drift::DbQueries).to receive(:find_trigger) do |name|
        db_triggers.find { |t| t["trigger_name"] == name }
      end
    end

    it "returns only problematic triggers" do
      problematic = described_class.problematic_list

      expect(problematic.count).to eq(3)

      states = problematic.pluck(:state)
      expect(states).to include(PgSqlTriggers::DRIFT_STATE_DRIFTED)
      expect(states).to include(PgSqlTriggers::DRIFT_STATE_DROPPED)
      expect(states).to include(PgSqlTriggers::DRIFT_STATE_UNKNOWN)
    end

    it "does not include in-sync or disabled triggers" do
      problematic = described_class.problematic_list

      states = problematic.pluck(:state)
      expect(states).not_to include(PgSqlTriggers::DRIFT_STATE_IN_SYNC)
      expect(states).not_to include(PgSqlTriggers::DRIFT_STATE_DISABLED)
    end
  end

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
