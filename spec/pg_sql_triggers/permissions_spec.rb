# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Permissions do
  describe "ACTIONS constant" do
    it "defines action permission mappings" do
      expect(PgSqlTriggers::Permissions::ACTIONS).to be_a(Hash)
      expect(PgSqlTriggers::Permissions::ACTIONS[:view_triggers]).to eq(PgSqlTriggers::Permissions::VIEWER)
      expect(PgSqlTriggers::Permissions::ACTIONS[:apply_trigger]).to eq(PgSqlTriggers::Permissions::OPERATOR)
      expect(PgSqlTriggers::Permissions::ACTIONS[:drop_trigger]).to eq(PgSqlTriggers::Permissions::ADMIN)
    end
  end

  describe ".can?" do
    let(:actor) { { type: "User", id: 1 } }

    context "when custom permission checker is configured" do
      before do
        @original_checker = PgSqlTriggers.permission_checker
        PgSqlTriggers.permission_checker = ->(_actor, action, _environment) { action == :view_triggers }
      end

      after do
        PgSqlTriggers.permission_checker = @original_checker
      end

      it "uses custom checker" do
        expect(described_class.can?(actor, :view_triggers)).to be true
        expect(described_class.can?(actor, :drop_trigger)).to be false
      end

      it "passes environment to checker" do
        checker = ->(_actor, _action, environment) { environment == "production" }
        PgSqlTriggers.permission_checker = checker
        expect(described_class.can?(actor, :view_triggers, environment: "production")).to be true
        expect(described_class.can?(actor, :view_triggers, environment: "development")).to be false
        PgSqlTriggers.permission_checker = @original_checker
      end
    end

    context "when no custom checker configured" do
      before do
        @original_checker = PgSqlTriggers.permission_checker
        PgSqlTriggers.permission_checker = nil
      end

      after do
        PgSqlTriggers.permission_checker = @original_checker
      end

      it "allows all permissions by default" do
        expect(described_class.can?(actor, :view_triggers)).to be true
        expect(described_class.can?(actor, :drop_trigger)).to be true
      end
    end
  end

  describe ".check!" do
    let(:actor) { { type: "User", id: 1 } }

    context "when permission is granted" do
      before do
        @original_checker = PgSqlTriggers.permission_checker
        PgSqlTriggers.permission_checker = ->(_actor, _action, _environment) { true }
      end

      after do
        PgSqlTriggers.permission_checker = @original_checker
      end

      it "returns true" do
        expect(described_class.check!(actor, :view_triggers)).to be true
      end
    end

    context "when permission is denied" do
      before do
        @original_checker = PgSqlTriggers.permission_checker
        PgSqlTriggers.permission_checker = ->(_actor, _action, _environment) { false }
      end

      after do
        PgSqlTriggers.permission_checker = @original_checker
      end

      it "raises PermissionError" do
        expect do
          described_class.check!(actor, :drop_trigger)
        end.to raise_error(PgSqlTriggers::PermissionError, /Permission denied/)
      end

      it "includes required permission level in error" do
        expect do
          described_class.check!(actor, :drop_trigger)
        end.to raise_error(PgSqlTriggers::PermissionError, /admin/)
      end
    end

    context "when action is unknown" do
      before do
        @original_checker = PgSqlTriggers.permission_checker
        PgSqlTriggers.permission_checker = ->(_actor, _action, _environment) { false }
      end

      after do
        PgSqlTriggers.permission_checker = @original_checker
      end

      it "includes unknown in error message" do
        expect do
          described_class.check!(actor, :unknown_action)
        end.to raise_error(PgSqlTriggers::PermissionError, /unknown/)
      end
    end
  end
end

RSpec.describe PgSqlTriggers::Permissions::Checker do
  describe ".can?" do
    it "delegates to PgSqlTriggers.permission_checker when configured" do
      custom_checker = ->(_actor, action, _env) { action == :allowed_action }
      original = PgSqlTriggers.permission_checker
      PgSqlTriggers.permission_checker = custom_checker

      actor = { type: "User", id: 1 }
      expect(described_class.can?(actor, :allowed_action)).to be true
      expect(described_class.can?(actor, :denied_action)).to be false

      PgSqlTriggers.permission_checker = original
    end

    it "defaults to true when no checker configured" do
      original = PgSqlTriggers.permission_checker
      PgSqlTriggers.permission_checker = nil

      actor = { type: "User", id: 1 }
      expect(described_class.can?(actor, :any_action)).to be true

      PgSqlTriggers.permission_checker = original
    end
  end

  describe ".check!" do
    it "calls can? and raises error if false" do
      original = PgSqlTriggers.permission_checker
      PgSqlTriggers.permission_checker = ->(_actor, _action, _env) { false }

      actor = { type: "User", id: 1 }
      expect do
        described_class.check!(actor, :drop_trigger)
      end.to raise_error(PgSqlTriggers::PermissionError)

      PgSqlTriggers.permission_checker = original
    end

    it "returns true if can? returns true" do
      original = PgSqlTriggers.permission_checker
      PgSqlTriggers.permission_checker = ->(_actor, _action, _env) { true }

      actor = { type: "User", id: 1 }
      expect(described_class.check!(actor, :view_triggers)).to be true

      PgSqlTriggers.permission_checker = original
    end
  end
end
