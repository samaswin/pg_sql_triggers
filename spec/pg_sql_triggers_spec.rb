# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers do
  it "has a version number" do
    expect(PgSqlTriggers::VERSION).not_to be_nil
    expect(PgSqlTriggers::VERSION).to be_a(String)
  end

  describe ".configure" do
    it "yields self for configuration" do
      described_class.configure do |config|
        expect(config).to eq(described_class)
      end
    end

    it "allows setting kill_switch_enabled" do
      original = described_class.kill_switch_enabled
      described_class.configure do |config|
        config.kill_switch_enabled = false
      end
      expect(described_class.kill_switch_enabled).to be(false)
      described_class.kill_switch_enabled = original
    end

    it "allows setting default_environment" do
      original = described_class.default_environment
      described_class.configure do |config|
        config.default_environment = -> { "test" }
      end
      expect(described_class.default_environment.call).to eq("test")
      described_class.default_environment = original
    end
  end

  describe "error classes" do
    it "defines Error base class" do
      expect(PgSqlTriggers::Error).to be < StandardError
    end

    it "defines PermissionError" do
      expect(PgSqlTriggers::PermissionError).to be < PgSqlTriggers::Error
    end

    it "defines DriftError" do
      expect(PgSqlTriggers::DriftError).to be < PgSqlTriggers::Error
    end

    it "defines KillSwitchError" do
      expect(PgSqlTriggers::KillSwitchError).to be < PgSqlTriggers::Error
    end

    it "defines ValidationError" do
      expect(PgSqlTriggers::ValidationError).to be < PgSqlTriggers::Error
    end
  end
end
