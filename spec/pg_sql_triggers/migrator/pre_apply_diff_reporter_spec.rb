# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Migrator::PreApplyDiffReporter do
  describe ".format" do
    context "when no differences" do
      let(:no_diff_result) do
        {
          has_differences: false,
          functions: [],
          triggers: []
        }
      end

      it "returns appropriate message" do
        result = described_class.format(no_diff_result, migration_name: "test_migration")
        expect(result).to be_a(String)
        expect(result).to include("No differences")
      end
    end
  end

  describe ".format_summary" do
    context "when no differences" do
      let(:no_diff_result) do
        {
          has_differences: false,
          functions: [],
          triggers: []
        }
      end

      it "returns appropriate message" do
        result = described_class.format_summary(no_diff_result)
        expect(result).to be_a(String)
        expect(result).to include("No differences")
      end
    end
  end
end

