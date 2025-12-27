# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers do
  it "has a version number" do
    expect(PgTriggers::VERSION).not_to be nil
    expect(PgTriggers::VERSION).to be_a(String)
  end

  describe ".configure" do
    it "yields self for configuration" do
      PgTriggers.configure do |config|
        expect(config).to eq(PgTriggers)
      end
    end

    it "allows setting kill_switch_enabled" do
      original = PgTriggers.kill_switch_enabled
      PgTriggers.configure do |config|
        config.kill_switch_enabled = false
      end
      expect(PgTriggers.kill_switch_enabled).to eq(false)
      PgTriggers.kill_switch_enabled = original
    end

    it "allows setting default_environment" do
      original = PgTriggers.default_environment
      PgTriggers.configure do |config|
        config.default_environment = -> { "test" }
      end
      expect(PgTriggers.default_environment.call).to eq("test")
      PgTriggers.default_environment = original
    end
  end

  describe "error classes" do
    it "defines Error base class" do
      expect(PgTriggers::Error).to be < StandardError
    end

    it "defines PermissionError" do
      expect(PgTriggers::PermissionError).to be < PgTriggers::Error
    end

    it "defines DriftError" do
      expect(PgTriggers::DriftError).to be < PgTriggers::Error
    end

    it "defines KillSwitchError" do
      expect(PgTriggers::KillSwitchError).to be < PgTriggers::Error
    end

    it "defines ValidationError" do
      expect(PgTriggers::ValidationError).to be < PgTriggers::Error
    end
  end
end
