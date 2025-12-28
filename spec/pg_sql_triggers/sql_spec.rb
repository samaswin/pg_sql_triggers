# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::SQL do
  describe ".kill_switch_active?" do
    it "delegates to KillSwitch.active?" do
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:active?).and_return(true)
      result = described_class.kill_switch_active?
      expect(result).to be true
    end
  end

  describe ".override_kill_switch" do
    it "delegates to KillSwitch.override" do
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:override).and_yield
      described_class.override_kill_switch { :result }
    end

    it "returns the result of the block" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:override).and_yield
      result = described_class.override_kill_switch { "test_result" }
      expect(result).to eq("test_result")
    end
  end
end

