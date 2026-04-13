# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Registry::Validator do
  # Builds a DSL definition JSON blob with sensible defaults; accepts overrides.
  def valid_definition(overrides = {})
    {
      "name" => "test_trigger",
      "table_name" => "users",
      "events" => ["insert"],
      "function_name" => "test_function",
      "timing" => "before",
      "for_each" => "row",
      "version" => 1,
      "enabled" => true,
      "environments" => [],
      "condition" => nil,
      "depends_on" => []
    }.merge(overrides).to_json
  end

  describe ".validate!" do
    context "with no DSL triggers in the registry" do
      it "returns true" do
        expect(described_class.validate!).to be true
      end
    end

    context "with a valid DSL trigger" do
      before { create(:trigger_registry, source: "dsl", definition: valid_definition) }

      it "returns true" do
        expect(described_class.validate!).to be true
      end

      it "accepts all valid timing values" do
        %w[before after instead_of].each do |timing|
          create(:trigger_registry, source: "dsl", definition: valid_definition("timing" => timing))
        end
        expect(described_class.validate!).to be true
      end

      it "accepts all valid event types" do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition("events" => %w[insert update delete truncate]))
        expect(described_class.validate!).to be true
      end
    end

    context "with a non-DSL trigger that has invalid definition data" do
      before do
        create(:trigger_registry, source: "manual_sql",
                                  definition: valid_definition("table_name" => nil, "events" => [], "function_name" => nil))
      end

      it "ignores non-DSL triggers and returns true" do
        expect(described_class.validate!).to be true
      end
    end

    context "with a DSL trigger missing table_name in its definition" do
      before { create(:trigger_registry, source: "dsl", definition: valid_definition("table_name" => nil)) }

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /missing table_name/)
      end
    end

    context "with a DSL trigger with empty events" do
      before { create(:trigger_registry, source: "dsl", definition: valid_definition("events" => [])) }

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /events cannot be empty/)
      end
    end

    context "with a DSL trigger with invalid events" do
      before { create(:trigger_registry, source: "dsl", definition: valid_definition("events" => %w[insert upsert])) }

      it "raises ValidationError naming the invalid event" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /invalid events/)
      end
    end

    context "with a DSL trigger listing columns without an update event" do
      before do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition("events" => ["insert"], "columns" => ["email"]))
      end

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /columns require an update event/)
      end
    end

    context "with a DSL trigger with an invalid column identifier" do
      before do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition("events" => ["update"], "columns" => ["bad-name"]))
      end

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /invalid column name/)
      end
    end

    context "with a DSL trigger using UPDATE OF columns" do
      before do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition("events" => ["update"], "columns" => %w[email name]))
      end

      it "returns true" do
        expect(described_class.validate!).to be true
      end
    end

    context "with a DSL trigger missing function_name" do
      before { create(:trigger_registry, source: "dsl", definition: valid_definition("function_name" => nil)) }

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /missing function_name/)
      end
    end

    context "with a DSL trigger with an invalid timing value" do
      before { create(:trigger_registry, source: "dsl", definition: valid_definition("timing" => "during")) }

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /invalid timing/)
      end
    end

    context "with a DSL trigger with valid for_each values" do
      it "accepts 'row'" do
        create(:trigger_registry, source: "dsl", definition: valid_definition("for_each" => "row"))
        expect(described_class.validate!).to be true
      end

      it "accepts 'statement'" do
        create(:trigger_registry, source: "dsl", definition: valid_definition("for_each" => "statement"))
        expect(described_class.validate!).to be true
      end
    end

    context "with a DSL trigger with an invalid for_each value" do
      before { create(:trigger_registry, source: "dsl", definition: valid_definition("for_each" => "column")) }

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /invalid for_each/)
      end
    end

    context "with multiple validation errors in one trigger" do
      before do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition("table_name" => nil, "events" => [], "function_name" => nil))
      end

      it "raises ValidationError and reports all errors" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError) do |error|
            expect(error.context[:errors].size).to be >= 3
          end
      end
    end

    context "with a DSL trigger whose definition JSON is unparseable" do
      before { create(:trigger_registry, source: "dsl", definition: "not valid json {{{") }

      it "raises ValidationError for the effectively empty definition" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError)
      end
    end

    context "with deferrable set without constraint_trigger" do
      before do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition("deferrable" => "deferrable", "constraint_trigger" => false))
      end

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /constraint_trigger/)
      end
    end

    context "with constraint_trigger and before timing" do
      before do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition(
                                    "constraint_trigger" => true,
                                    "timing" => "before",
                                    "events" => ["insert"]
                                  ))
      end

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /constraint triggers must use after timing/)
      end
    end

    context "with constraint_trigger and TRUNCATE event" do
      before do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition(
                                    "constraint_trigger" => true,
                                    "timing" => "after",
                                    "events" => ["truncate"]
                                  ))
      end

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /cannot use TRUNCATE/)
      end
    end

    context "with initially set but deferrable not deferrable" do
      before do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition(
                                    "constraint_trigger" => true,
                                    "timing" => "after",
                                    "deferrable" => "not_deferrable",
                                    "initially" => "deferred"
                                  ))
      end

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /initially requires deferrable/)
      end
    end

    context "with valid constraint deferrable trigger" do
      before do
        create(:trigger_registry, source: "dsl",
                                  definition: valid_definition(
                                    "constraint_trigger" => true,
                                    "timing" => "after",
                                    "deferrable" => "deferrable",
                                    "initially" => "deferred",
                                    "events" => ["insert"]
                                  ))
      end

      it "returns true" do
        expect(described_class.validate!).to be true
      end
    end

    context "with valid depends_on chain (alphabetical order)" do
      before do
        create(:trigger_registry, source: "dsl",
                                  trigger_name: "a_users_log",
                                  definition: valid_definition(
                                    "name" => "a_users_log",
                                    "depends_on" => []
                                  ))
        create(:trigger_registry, source: "dsl",
                                  trigger_name: "z_users_audit",
                                  definition: valid_definition(
                                    "name" => "z_users_audit",
                                    "depends_on" => ["a_users_log"]
                                  ))
      end

      it "returns true" do
        expect(described_class.validate!).to be true
      end
    end

    context "with depends_on referencing an unknown trigger" do
      before do
        create(:trigger_registry, source: "dsl",
                                  trigger_name: "z_orphan",
                                  definition: valid_definition("name" => "z_orphan", "depends_on" => ["missing_other"]))
      end

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /unknown trigger 'missing_other'/)
      end
    end

    context "with depends_on violating alphabetical order" do
      before do
        create(:trigger_registry, source: "dsl",
                                  trigger_name: "a_child",
                                  definition: valid_definition("name" => "a_child", "depends_on" => ["z_parent"]))
        create(:trigger_registry, source: "dsl",
                                  trigger_name: "z_parent",
                                  definition: valid_definition("name" => "z_parent", "depends_on" => []))
      end

      it "raises ValidationError" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError, /must sort before/)
      end
    end

    context "with depends_on circular chain" do
      before do
        create(:trigger_registry, source: "dsl",
                                  trigger_name: "pad_00",
                                  definition: valid_definition("name" => "pad_00", "depends_on" => ["pad_02"]))
        create(:trigger_registry, source: "dsl",
                                  trigger_name: "pad_01",
                                  definition: valid_definition("name" => "pad_01", "depends_on" => ["pad_00"]))
        create(:trigger_registry, source: "dsl",
                                  trigger_name: "pad_02",
                                  definition: valid_definition("name" => "pad_02", "depends_on" => ["pad_01"]))
      end

      it "raises ValidationError for cycle or order" do
        expect { described_class.validate! }
          .to raise_error(PgSqlTriggers::ValidationError) do |err|
            expect(err.context[:errors].join).to match(/circular|must sort before/)
          end
      end
    end
  end

  describe ".related_triggers_for_show" do
    it "returns prerequisites and dependents" do
      parent = create(:trigger_registry, :dsl_source,
                      trigger_name: "parent_tr",
                      definition: valid_definition("name" => "parent_tr"))
      child = create(:trigger_registry, :dsl_source,
                     trigger_name: "zz_child_tr",
                     definition: valid_definition(
                       "name" => "zz_child_tr",
                       "depends_on" => ["parent_tr"]
                     ))

      result = described_class.related_triggers_for_show(child)
      expect(result[:prerequisites].map(&:trigger_name)).to eq(["parent_tr"])
      expect(result[:dependents].map(&:trigger_name)).to eq([])

      reverse = described_class.related_triggers_for_show(parent)
      expect(reverse[:prerequisites]).to eq([])
      expect(reverse[:dependents].map(&:trigger_name)).to eq(["zz_child_tr"])
    end
  end

  describe ".trigger_order_validation_errors" do
    it "returns the same dependency errors as validate! without raising" do
      create(:trigger_registry, source: "dsl",
                                trigger_name: "bad_order",
                                definition: valid_definition("name" => "bad_order", "depends_on" => ["missing"]))

      errors = described_class.trigger_order_validation_errors
      expect(errors.join).to match(/unknown trigger/)
    end
  end
end
