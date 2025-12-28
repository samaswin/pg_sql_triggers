# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Drift do
  let(:trigger_name) { "test_trigger" }
  let(:table_name) { "users" }
  let(:function_body) { "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;" }
  let(:condition) { "NEW.email IS NOT NULL" }

  describe ".detect" do
    context "with trigger name" do
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

      it "delegates to Detector.detect" do
        expect(PgSqlTriggers::Drift::Detector).to receive(:detect).with(trigger_name)
        described_class.detect(trigger_name)
      end

      it "returns drift result" do
        result = described_class.detect(trigger_name)
        expect(result).to be_a(Hash)
        expect(result[:state]).to be_present
      end
    end

    context "without trigger name" do
      before do
        allow(PgSqlTriggers::Drift::Detector).to receive(:detect_all).and_return([])
      end

      it "delegates to Detector.detect_all" do
        expect(PgSqlTriggers::Drift::Detector).to receive(:detect_all)
        described_class.detect
      end

      it "returns array of drift results" do
        results = described_class.detect
        expect(results).to be_an(Array)
      end
    end
  end

  describe ".summary" do
    before do
      allow(PgSqlTriggers::Drift::Reporter).to receive(:summary).and_return({
                                                                              total: 0,
                                                                              in_sync: 0,
                                                                              drifted: 0,
                                                                              disabled: 0,
                                                                              dropped: 0,
                                                                              unknown: 0,
                                                                              manual_override: 0
                                                                            })
    end

    it "delegates to Reporter.summary" do
      expect(PgSqlTriggers::Drift::Reporter).to receive(:summary)
      described_class.summary
    end

    it "returns summary hash" do
      summary = described_class.summary
      expect(summary).to be_a(Hash)
      expect(summary).to have_key(:total)
      expect(summary).to have_key(:in_sync)
      expect(summary).to have_key(:drifted)
    end
  end

  describe ".report" do
    before do
      allow(PgSqlTriggers::Drift::Reporter).to receive(:report)
        .with(trigger_name)
        .and_return("Drift Report: #{trigger_name}")
    end

    it "delegates to Reporter.report" do
      expect(PgSqlTriggers::Drift::Reporter).to receive(:report).with(trigger_name)
      described_class.report(trigger_name)
    end

    it "returns report string" do
      report = described_class.report(trigger_name)
      expect(report).to be_a(String)
      expect(report).to include(trigger_name)
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
