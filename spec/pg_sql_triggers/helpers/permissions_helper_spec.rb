# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::PermissionsHelper do
  # Create a test class that includes the helper
  let(:helper_class) do
    Class.new do
      include PgSqlTriggers::PermissionsHelper

      attr_accessor :current_actor, :current_environment

      def initialize
        @current_actor = { type: "User", id: 1 }
        @current_environment = "test"
      end
    end
  end

  let(:helper) { helper_class.new }

  before do
    allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
  end

  describe "#can?" do
    it "delegates to PgSqlTriggers::Permissions.can?" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        helper.current_actor,
        :view_triggers,
        environment: helper.current_environment
      ).and_return(true)
      expect(helper.can?(:view_triggers)).to be true
    end

    it "passes current_environment" do
      helper.current_environment = "production"
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        anything,
        :view_triggers,
        environment: "production"
      ).and_return(false)
      expect(helper.can?(:view_triggers)).to be false
    end

    it "works with different actions" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        anything,
        :drop_trigger,
        environment: anything
      ).and_return(true)
      expect(helper.can?(:drop_trigger)).to be true
    end
  end

  describe "#can_view_triggers?" do
    it "checks view_triggers permission" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        helper.current_actor,
        :view_triggers,
        environment: helper.current_environment
      ).and_return(true)
      expect(helper.can_view_triggers?).to be true
    end
  end

  describe "#can_enable_disable_triggers?" do
    it "checks enable_trigger permission" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        helper.current_actor,
        :enable_trigger,
        environment: helper.current_environment
      ).and_return(true)
      expect(helper.can_enable_disable_triggers?).to be true
    end
  end

  describe "#can_drop_triggers?" do
    it "checks drop_trigger permission" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        helper.current_actor,
        :drop_trigger,
        environment: helper.current_environment
      ).and_return(true)
      expect(helper.can_drop_triggers?).to be true
    end
  end

  describe "#can_execute_sql?" do
    it "checks execute_sql permission" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        helper.current_actor,
        :execute_sql,
        environment: helper.current_environment
      ).and_return(true)
      expect(helper.can_execute_sql?).to be true
    end
  end

  describe "#can_generate_triggers?" do
    it "checks generate_trigger permission" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        helper.current_actor,
        :generate_trigger,
        environment: helper.current_environment
      ).and_return(true)
      expect(helper.can_generate_triggers?).to be true
    end
  end

  describe "#can_apply_triggers?" do
    it "checks apply_trigger permission" do
      expect(PgSqlTriggers::Permissions).to receive(:can?).with(
        helper.current_actor,
        :apply_trigger,
        environment: helper.current_environment
      ).and_return(true)
      expect(helper.can_apply_triggers?).to be true
    end
  end
end

