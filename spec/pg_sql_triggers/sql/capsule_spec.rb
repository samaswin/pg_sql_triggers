# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::SQL::Capsule do
  describe "initialization" do
    it "creates a valid capsule with all required attributes" do
      capsule = described_class.new(
        name: "fix_user_permissions",
        environment: "production",
        purpose: "Emergency fix for user permission issue",
        sql: "UPDATE users SET role = 'admin' WHERE email = 'admin@example.com';"
      )

      expect(capsule.name).to eq("fix_user_permissions")
      expect(capsule.environment).to eq("production")
      expect(capsule.purpose).to eq("Emergency fix for user permission issue")
      expect(capsule.sql).to eq("UPDATE users SET role = 'admin' WHERE email = 'admin@example.com';")
      expect(capsule.created_at).to be_a(Time)
    end

    it "accepts custom created_at timestamp" do
      timestamp = 1.hour.ago
      capsule = described_class.new(
        name: "test",
        environment: "production",
        purpose: "test purpose",
        sql: "SELECT 1;",
        created_at: timestamp
      )

      expect(capsule.created_at).to eq(timestamp)
    end

    it "defaults created_at to current time if not provided" do
      freeze_time do
        capsule = described_class.new(
          name: "test",
          environment: "production",
          purpose: "test purpose",
          sql: "SELECT 1;"
        )

        expect(capsule.created_at).to eq(Time.current)
      end
    end
  end

  describe "validations" do
    context "with valid attributes" do
      it "does not raise error for alphanumeric name" do
        expect do
          described_class.new(
            name: "fix123",
            environment: "production",
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.not_to raise_error
      end

      it "does not raise error for name with underscores" do
        expect do
          described_class.new(
            name: "fix_user_permissions",
            environment: "production",
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.not_to raise_error
      end

      it "does not raise error for name with hyphens" do
        expect do
          described_class.new(
            name: "fix-user-permissions",
            environment: "production",
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.not_to raise_error
      end
    end

    context "when name is missing" do
      it "raises ArgumentError" do
        expect do
          described_class.new(
            name: nil,
            environment: "production",
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.to raise_error(ArgumentError, /Name cannot be blank/)
      end

      it "raises ArgumentError for empty string" do
        expect do
          described_class.new(
            name: "",
            environment: "production",
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.to raise_error(ArgumentError, /Name cannot be blank/)
      end

      it "raises ArgumentError for whitespace only" do
        expect do
          described_class.new(
            name: "   ",
            environment: "production",
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.to raise_error(ArgumentError, /Name cannot be blank/)
      end
    end

    context "when environment is missing" do
      it "raises ArgumentError" do
        expect do
          described_class.new(
            name: "test",
            environment: nil,
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.to raise_error(ArgumentError, /Environment cannot be blank/)
      end
    end

    context "when purpose is missing" do
      it "raises ArgumentError" do
        expect do
          described_class.new(
            name: "test",
            environment: "production",
            purpose: nil,
            sql: "SELECT 1;"
          )
        end.to raise_error(ArgumentError, /Purpose cannot be blank/)
      end
    end

    context "when sql is missing" do
      it "raises ArgumentError" do
        expect do
          described_class.new(
            name: "test",
            environment: "production",
            purpose: "test",
            sql: nil
          )
        end.to raise_error(ArgumentError, /SQL cannot be blank/)
      end
    end

    context "when name format is invalid" do
      it "raises ArgumentError for spaces" do
        expect do
          described_class.new(
            name: "fix user permissions",
            environment: "production",
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.to raise_error(ArgumentError, /Name must contain only/)
      end

      it "raises ArgumentError for special characters" do
        expect do
          described_class.new(
            name: "fix@user!",
            environment: "production",
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.to raise_error(ArgumentError, /Name must contain only/)
      end

      it "raises ArgumentError for dots" do
        expect do
          described_class.new(
            name: "fix.user",
            environment: "production",
            purpose: "test",
            sql: "SELECT 1;"
          )
        end.to raise_error(ArgumentError, /Name must contain only/)
      end
    end

    context "with multiple validation errors" do
      it "includes all errors in message" do
        expect do
          described_class.new(
            name: nil,
            environment: nil,
            purpose: nil,
            sql: nil
          )
        end.to raise_error(ArgumentError, /Name cannot be blank.*Environment cannot be blank.*Purpose cannot be blank.*SQL cannot be blank/m)
      end
    end
  end

  describe "#checksum" do
    let(:capsule) do
      described_class.new(
        name: "test",
        environment: "production",
        purpose: "test purpose",
        sql: "SELECT 1;"
      )
    end

    it "calculates SHA256 checksum of SQL content" do
      expected_checksum = Digest::SHA256.hexdigest("SELECT 1;")
      expect(capsule.checksum).to eq(expected_checksum)
    end

    it "returns consistent checksum for same SQL" do
      checksum1 = capsule.checksum
      checksum2 = capsule.checksum
      expect(checksum1).to eq(checksum2)
    end

    it "returns different checksum for different SQL" do
      capsule1 = described_class.new(
        name: "test1",
        environment: "production",
        purpose: "test",
        sql: "SELECT 1;"
      )
      capsule2 = described_class.new(
        name: "test2",
        environment: "production",
        purpose: "test",
        sql: "SELECT 2;"
      )

      expect(capsule1.checksum).not_to eq(capsule2.checksum)
    end

    it "caches the checksum" do
      # First call calculates and caches
      checksum1 = capsule.checksum

      # Mock Digest to ensure it's not called again
      allow(Digest::SHA256).to receive(:hexdigest)

      # Second call should use cached value
      checksum2 = capsule.checksum

      expect(checksum1).to eq(checksum2)
      expect(Digest::SHA256).not_to have_received(:hexdigest)
    end
  end

  describe "#to_h" do
    let(:capsule) do
      described_class.new(
        name: "fix_users",
        environment: "production",
        purpose: "Fix user permissions",
        sql: "UPDATE users SET role = 'admin';",
        created_at: Time.parse("2024-01-01 12:00:00 UTC")
      )
    end

    it "returns hash with all capsule data" do
      hash = capsule.to_h

      expect(hash[:name]).to eq("fix_users")
      expect(hash[:environment]).to eq("production")
      expect(hash[:purpose]).to eq("Fix user permissions")
      expect(hash[:sql]).to eq("UPDATE users SET role = 'admin';")
      expect(hash[:checksum]).to eq(capsule.checksum)
      expect(hash[:created_at]).to eq(Time.parse("2024-01-01 12:00:00 UTC"))
    end

    it "includes calculated checksum" do
      hash = capsule.to_h
      expect(hash[:checksum]).to be_present
      expect(hash[:checksum]).to eq(Digest::SHA256.hexdigest("UPDATE users SET role = 'admin';"))
    end
  end

  describe "#registry_trigger_name" do
    it "returns trigger name with sql_capsule_ prefix" do
      capsule = described_class.new(
        name: "fix_permissions",
        environment: "production",
        purpose: "test",
        sql: "SELECT 1;"
      )

      expect(capsule.registry_trigger_name).to eq("sql_capsule_fix_permissions")
    end

    it "uses the capsule name in trigger name" do
      capsule = described_class.new(
        name: "emergency_fix",
        environment: "production",
        purpose: "test",
        sql: "SELECT 1;"
      )

      expect(capsule.registry_trigger_name).to eq("sql_capsule_emergency_fix")
    end
  end
end
