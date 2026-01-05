# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::PermissionsHelper do
  # Create a test class that includes the helper module
  # This allows us to test the helper methods directly
  let(:test_class) do
    Class.new do
      include PgSqlTriggers::PermissionsHelper

      attr_accessor :actor, :environment

      def current_actor
        @actor || { type: "User", id: "123" }
      end

      def current_environment
        @environment || "test"
      end
    end
  end

  let(:helper_instance) { test_class.new }

  describe "#can?" do
    let(:actor) { { type: "User", id: "123" } }
    let(:environment) { "production" }

    before do
      helper_instance.actor = actor
      helper_instance.environment = environment
    end

    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :view_triggers, environment: environment)
          .and_return(true)
      end

      it "returns true" do
        expect(helper_instance.can?(:view_triggers)).to be true
      end

      it "calls PgSqlTriggers::Permissions.can? with correct arguments" do
        helper_instance.can?(:view_triggers)
        expect(PgSqlTriggers::Permissions).to have_received(:can?)
          .with(actor, :view_triggers, environment: environment)
      end

      it "handles string action" do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, "view_triggers", environment: environment)
          .and_return(true)
        expect(helper_instance.can?("view_triggers")).to be true
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :drop_trigger, environment: environment)
          .and_return(false)
      end

      it "returns false" do
        expect(helper_instance.can?(:drop_trigger)).to be false
      end

      it "calls PgSqlTriggers::Permissions.can? with correct arguments" do
        helper_instance.can?(:drop_trigger)
        expect(PgSqlTriggers::Permissions).to have_received(:can?)
          .with(actor, :drop_trigger, environment: environment)
      end
    end
  end

  describe "#can_view_triggers?" do
    let(:actor) { { type: "User", id: "123" } }
    let(:environment) { "production" }

    before do
      helper_instance.actor = actor
      helper_instance.environment = environment
    end

    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :view_triggers, environment: environment)
          .and_return(true)
      end

      it "returns true" do
        expect(helper_instance.can_view_triggers?).to be true
      end

      it "calls can? with :view_triggers" do
        allow(helper_instance).to receive(:can?).with(:view_triggers).and_return(true)
        helper_instance.can_view_triggers?
        expect(helper_instance).to have_received(:can?).with(:view_triggers)
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :view_triggers, environment: environment)
          .and_return(false)
      end

      it "returns false" do
        expect(helper_instance.can_view_triggers?).to be false
      end
    end
  end

  describe "#can_enable_disable_triggers?" do
    let(:actor) { { type: "User", id: "123" } }
    let(:environment) { "production" }

    before do
      helper_instance.actor = actor
      helper_instance.environment = environment
    end

    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :enable_trigger, environment: environment)
          .and_return(true)
      end

      it "returns true" do
        expect(helper_instance.can_enable_disable_triggers?).to be true
      end

      it "calls can? with :enable_trigger" do
        allow(helper_instance).to receive(:can?).with(:enable_trigger).and_return(true)
        helper_instance.can_enable_disable_triggers?
        expect(helper_instance).to have_received(:can?).with(:enable_trigger)
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :enable_trigger, environment: environment)
          .and_return(false)
      end

      it "returns false" do
        expect(helper_instance.can_enable_disable_triggers?).to be false
      end
    end
  end

  describe "#can_drop_triggers?" do
    let(:actor) { { type: "User", id: "123" } }
    let(:environment) { "production" }

    before do
      helper_instance.actor = actor
      helper_instance.environment = environment
    end

    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :drop_trigger, environment: environment)
          .and_return(true)
      end

      it "returns true" do
        expect(helper_instance.can_drop_triggers?).to be true
      end

      it "calls can? with :drop_trigger" do
        allow(helper_instance).to receive(:can?).with(:drop_trigger).and_return(true)
        helper_instance.can_drop_triggers?
        expect(helper_instance).to have_received(:can?).with(:drop_trigger)
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :drop_trigger, environment: environment)
          .and_return(false)
      end

      it "returns false" do
        expect(helper_instance.can_drop_triggers?).to be false
      end
    end
  end

  describe "#can_execute_sql?" do
    let(:actor) { { type: "User", id: "123" } }
    let(:environment) { "production" }

    before do
      helper_instance.actor = actor
      helper_instance.environment = environment
    end

    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql, environment: environment)
          .and_return(true)
      end

      it "returns true" do
        expect(helper_instance.can_execute_sql?).to be true
      end

      it "calls can? with :execute_sql" do
        allow(helper_instance).to receive(:can?).with(:execute_sql).and_return(true)
        helper_instance.can_execute_sql?
        expect(helper_instance).to have_received(:can?).with(:execute_sql)
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :execute_sql, environment: environment)
          .and_return(false)
      end

      it "returns false" do
        expect(helper_instance.can_execute_sql?).to be false
      end
    end
  end

  describe "#can_generate_triggers?" do
    let(:actor) { { type: "User", id: "123" } }
    let(:environment) { "production" }

    before do
      helper_instance.actor = actor
      helper_instance.environment = environment
    end

    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :generate_trigger, environment: environment)
          .and_return(true)
      end

      it "returns true" do
        expect(helper_instance.can_generate_triggers?).to be true
      end

      it "calls can? with :generate_trigger" do
        allow(helper_instance).to receive(:can?).with(:generate_trigger).and_return(true)
        helper_instance.can_generate_triggers?
        expect(helper_instance).to have_received(:can?).with(:generate_trigger)
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :generate_trigger, environment: environment)
          .and_return(false)
      end

      it "returns false" do
        expect(helper_instance.can_generate_triggers?).to be false
      end
    end
  end

  describe "#can_apply_triggers?" do
    let(:actor) { { type: "User", id: "123" } }
    let(:environment) { "production" }

    before do
      helper_instance.actor = actor
      helper_instance.environment = environment
    end

    context "when permission is granted" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :apply_trigger, environment: environment)
          .and_return(true)
      end

      it "returns true" do
        expect(helper_instance.can_apply_triggers?).to be true
      end

      it "calls can? with :apply_trigger" do
        allow(helper_instance).to receive(:can?).with(:apply_trigger).and_return(true)
        helper_instance.can_apply_triggers?
        expect(helper_instance).to have_received(:can?).with(:apply_trigger)
      end
    end

    context "when permission is denied" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?)
          .with(actor, :apply_trigger, environment: environment)
          .and_return(false)
      end

      it "returns false" do
        expect(helper_instance.can_apply_triggers?).to be false
      end
    end
  end
end
