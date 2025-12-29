# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::ApplicationRecord do
  describe "class configuration" do
    it "is an abstract class" do
      expect(described_class.abstract_class).to be true
    end

    it "inherits from ActiveRecord::Base" do
      expect(described_class.superclass).to eq(ActiveRecord::Base)
    end
  end

  describe "inheritance" do
    it "can be used as a base class for models" do
      # Test that TriggerRegistry inherits from ApplicationRecord
      expect(PgSqlTriggers::TriggerRegistry.superclass).to eq(described_class)
    end

    it "prevents direct instantiation" do
      # Abstract classes cannot be instantiated directly
      expect { described_class.new }.to raise_error(NotImplementedError)
    end
  end

  describe "model behavior" do
    it "provides ActiveRecord functionality to subclasses" do
      # TriggerRegistry should have ActiveRecord methods
      expect(PgSqlTriggers::TriggerRegistry).to respond_to(:create!)
      expect(PgSqlTriggers::TriggerRegistry).to respond_to(:find_by)
      expect(PgSqlTriggers::TriggerRegistry).to respond_to(:all)
    end
  end
end
