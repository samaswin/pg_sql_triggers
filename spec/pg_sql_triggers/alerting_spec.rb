# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Alerting do
  describe ".alertable?" do
    it "is true for drifted, dropped, and unknown" do
      expect(described_class.alertable?({ state: PgSqlTriggers::DRIFT_STATE_DRIFTED })).to be true
      expect(described_class.alertable?({ state: PgSqlTriggers::DRIFT_STATE_DROPPED })).to be true
      expect(described_class.alertable?({ state: PgSqlTriggers::DRIFT_STATE_UNKNOWN })).to be true
    end

    it "is false for in_sync and other states" do
      expect(described_class.alertable?({ state: PgSqlTriggers::DRIFT_STATE_IN_SYNC })).to be false
      expect(described_class.alertable?({ state: PgSqlTriggers::DRIFT_STATE_MANUAL_OVERRIDE })).to be false
    end
  end

  describe ".filter_alertable" do
    it "returns only problematic results" do
      rows = [
        { state: PgSqlTriggers::DRIFT_STATE_IN_SYNC },
        { state: PgSqlTriggers::DRIFT_STATE_DRIFTED },
        { state: PgSqlTriggers::DRIFT_STATE_DROPPED }
      ]
      expect(described_class.filter_alertable(rows).size).to eq(2)
    end
  end

  describe ".check_and_notify" do
    after do
      PgSqlTriggers.drift_notifier = nil
    end

    it "returns results, alertable subset, and notified false when notifier is nil" do
      drifted = { state: PgSqlTriggers::DRIFT_STATE_DRIFTED, details: "x" }
      allow(PgSqlTriggers::Drift::Detector).to receive(:detect_all).and_return([
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_IN_SYNC },
                                                                                 drifted
                                                                               ])

      outcome = described_class.check_and_notify
      expect(outcome[:results].size).to eq(2)
      expect(outcome[:alertable]).to eq([drifted])
      expect(outcome[:notified]).to be false
    end

    it "calls drift_notifier with alertable results and all_results keyword" do
      drifted = { state: PgSqlTriggers::DRIFT_STATE_DRIFTED, details: "x" }
      all_rows = [{ state: PgSqlTriggers::DRIFT_STATE_IN_SYNC }, drifted]
      allow(PgSqlTriggers::Drift::Detector).to receive(:detect_all).and_return(all_rows)

      received = nil
      received_all = nil
      PgSqlTriggers.drift_notifier = lambda do |alertable, all_results:|
        received = alertable
        received_all = all_results
      end

      outcome = described_class.check_and_notify
      expect(outcome[:notified]).to be true
      expect(received).to eq([drifted])
      expect(received_all).to eq(all_rows)
    end

    it "does not call notifier when there are no alertable results" do
      allow(PgSqlTriggers::Drift::Detector).to receive(:detect_all).and_return([
                                                                                 { state: PgSqlTriggers::DRIFT_STATE_IN_SYNC }
                                                                               ])
      called = false
      PgSqlTriggers.drift_notifier = ->(*) { called = true }

      outcome = described_class.check_and_notify
      expect(called).to be false
      expect(outcome[:notified]).to be false
    end
  end
end
