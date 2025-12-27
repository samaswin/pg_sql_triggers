# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers::Permissions do
  describe "ACTIONS constant" do
    it "defines action permission mappings" do
      expect(PgTriggers::Permissions::ACTIONS).to be_a(Hash)
      expect(PgTriggers::Permissions::ACTIONS[:view_triggers]).to eq(PgTriggers::Permissions::VIEWER)
      expect(PgTriggers::Permissions::ACTIONS[:apply_trigger]).to eq(PgTriggers::Permissions::OPERATOR)
      expect(PgTriggers::Permissions::ACTIONS[:drop_trigger]).to eq(PgTriggers::Permissions::ADMIN)
    end
  end

  describe ".can?" do
    let(:actor) { { type: "User", id: 1 } }

    context "when custom permission checker is configured" do
      before do
        @original_checker = PgTriggers.permission_checker
        PgTriggers.permission_checker = ->(actor, action, environment) { action == :view_triggers }
      end

      after do
        PgTriggers.permission_checker = @original_checker
      end

      it "uses custom checker" do
        expect(PgTriggers::Permissions.can?(actor, :view_triggers)).to be true
        expect(PgTriggers::Permissions.can?(actor, :drop_trigger)).to be false
      end

      it "passes environment to checker" do
        checker = ->(actor, action, environment) { environment == "production" }
        PgTriggers.permission_checker = checker
        expect(PgTriggers::Permissions.can?(actor, :view_triggers, environment: "production")).to be true
        expect(PgTriggers::Permissions.can?(actor, :view_triggers, environment: "development")).to be false
        PgTriggers.permission_checker = @original_checker
      end
    end

    context "when no custom checker configured" do
      before do
        @original_checker = PgTriggers.permission_checker
        PgTriggers.permission_checker = nil
      end

      after do
        PgTriggers.permission_checker = @original_checker
      end

      it "allows all permissions by default" do
        expect(PgTriggers::Permissions.can?(actor, :view_triggers)).to be true
        expect(PgTriggers::Permissions.can?(actor, :drop_trigger)).to be true
      end
    end
  end

  describe ".check!" do
    let(:actor) { { type: "User", id: 1 } }

    context "when permission is granted" do
      before do
        @original_checker = PgTriggers.permission_checker
        PgTriggers.permission_checker = ->(actor, action, environment) { true }
      end

      after do
        PgTriggers.permission_checker = @original_checker
      end

      it "returns true" do
        expect(PgTriggers::Permissions.check!(actor, :view_triggers)).to be true
      end
    end

    context "when permission is denied" do
      before do
        @original_checker = PgTriggers.permission_checker
        PgTriggers.permission_checker = ->(actor, action, environment) { false }
      end

      after do
        PgTriggers.permission_checker = @original_checker
      end

      it "raises PermissionError" do
        expect {
          PgTriggers::Permissions.check!(actor, :drop_trigger)
        }.to raise_error(PgTriggers::PermissionError, /Permission denied/)
      end

      it "includes required permission level in error" do
        expect {
          PgTriggers::Permissions.check!(actor, :drop_trigger)
        }.to raise_error(PgTriggers::PermissionError, /admin/)
      end
    end

    context "when action is unknown" do
      before do
        @original_checker = PgTriggers.permission_checker
        PgTriggers.permission_checker = ->(actor, action, environment) { false }
      end

      after do
        PgTriggers.permission_checker = @original_checker
      end

      it "includes unknown in error message" do
        expect {
          PgTriggers::Permissions.check!(actor, :unknown_action)
        }.to raise_error(PgTriggers::PermissionError, /unknown/)
      end
    end
  end
end

RSpec.describe PgTriggers::Permissions::Checker do
  describe ".can?" do
    it "delegates to PgTriggers.permission_checker when configured" do
      custom_checker = ->(actor, action, env) { action == :allowed_action }
      original = PgTriggers.permission_checker
      PgTriggers.permission_checker = custom_checker

      actor = { type: "User", id: 1 }
      expect(PgTriggers::Permissions::Checker.can?(actor, :allowed_action)).to be true
      expect(PgTriggers::Permissions::Checker.can?(actor, :denied_action)).to be false

      PgTriggers.permission_checker = original
    end

    it "defaults to true when no checker configured" do
      original = PgTriggers.permission_checker
      PgTriggers.permission_checker = nil

      actor = { type: "User", id: 1 }
      expect(PgTriggers::Permissions::Checker.can?(actor, :any_action)).to be true

      PgTriggers.permission_checker = original
    end
  end

  describe ".check!" do
    it "calls can? and raises error if false" do
      original = PgTriggers.permission_checker
      PgTriggers.permission_checker = ->(actor, action, env) { false }

      actor = { type: "User", id: 1 }
      expect {
        PgTriggers::Permissions::Checker.check!(actor, :drop_trigger)
      }.to raise_error(PgTriggers::PermissionError)

      PgTriggers.permission_checker = original
    end

    it "returns true if can? returns true" do
      original = PgTriggers.permission_checker
      PgTriggers.permission_checker = ->(actor, action, env) { true }

      actor = { type: "User", id: 1 }
      expect(PgTriggers::Permissions::Checker.check!(actor, :view_triggers)).to be true

      PgTriggers.permission_checker = original
    end
  end
end

