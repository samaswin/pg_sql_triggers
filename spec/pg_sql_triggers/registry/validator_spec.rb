# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgTriggers::Registry::Validator do
  describe ".validate!" do
    it "validates registry entries" do
      expect(PgTriggers::Registry::Validator.validate!).to be true
    end
  end
end

