# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Registry::Validator do
  describe ".validate!" do
    it "validates registry entries" do
      expect(described_class.validate!).to be true
    end
  end
end
