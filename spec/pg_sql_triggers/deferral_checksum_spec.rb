# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::DeferralChecksum do
  describe ".parts" do
    it "returns zeros for non-constraint triggers" do
      expect(described_class.parts(constraint_trigger: false, deferrable: :deferrable, initially: :deferred))
        .to eq(["0", "", ""])
    end

    it "normalizes omitted deferrable on constraint triggers to not_deferrable" do
      expect(described_class.parts(constraint_trigger: true, deferrable: nil, initially: nil))
        .to eq(["1", "not_deferrable", ""])
    end

    it "includes initially only when deferrable" do
      expect(described_class.parts(constraint_trigger: true, deferrable: :deferrable, initially: :deferred))
        .to eq(%w[1 deferrable deferred])

      expect(described_class.parts(constraint_trigger: true, deferrable: :deferrable, initially: nil))
        .to eq(%w[1 deferrable immediate])
    end
  end

  describe ".parts_from_db" do
    it "treats missing tgconstraint as non-constraint" do
      expect(described_class.parts_from_db({})).to eq(["0", "", ""])
    end

    it "maps pg_trigger flags to checksum segments" do
      row = {
        "tgconstraint" => 1,
        "tgdeferrable" => true,
        "tginitdeferred" => false
      }
      expect(described_class.parts_from_db(row)).to eq(%w[1 deferrable immediate])
    end
  end
end
