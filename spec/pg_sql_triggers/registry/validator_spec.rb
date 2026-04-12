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
      "version" => 1,
      "enabled" => true,
      "environments" => [],
      "condition" => nil
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
  end
end
