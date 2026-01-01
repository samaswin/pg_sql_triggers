# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Engine do
  describe "configuration" do
    it "isolates namespace" do
      expect(described_class.isolated?).to be true
    end

    it "configures generators" do
      expect(described_class.config.generators.test_framework).to eq(:rspec)
      expect(described_class.config.generators.fixture_replacement).to eq(:factory_bot)
      if described_class.config.generators.factory_bot
        expect(described_class.config.generators.factory_bot.dir).to eq("spec/factories")
      end
    end
  end

  describe "assets configuration" do
    let(:app) { double("Rails::Application") }
    let(:config) { double("Rails::Application::Configuration") }
    # rubocop:enable RSpec/VerifiedDoubles
    let(:paths_array) { [] }
    let(:precompile_array) { [] }
    let(:assets) do
      # rubocop:disable RSpec/VerifiedDoubles
      assets_double = double("Assets")
      # rubocop:enable RSpec/VerifiedDoubles
      # Make precompile return the actual array so += works
      allow(assets_double).to receive_messages(paths: paths_array, precompile: precompile_array)
      # Allow precompile= to be called and update the array (needed for += operation)
      allow(assets_double).to receive(:precompile=) do |value|
        precompile_array.replace(value)
      end
      assets_double
    end

    before do
      allow(app).to receive(:config).and_return(config)
    end

    it "adds asset paths when assets are available" do
      allow(config).to receive(:respond_to?).with(:assets).and_return(true)
      allow(config).to receive(:assets).and_return(assets)

      initializer = described_class.initializers.find { |i| i.name == "pg_sql_triggers.assets" }
      expect(initializer).to be_present

      initializer.block.call(app)

      expect(paths_array).to include(described_class.root.join("app/assets/stylesheets").to_s)
      expect(paths_array).to include(described_class.root.join("app/assets/javascripts").to_s)
      expect(precompile_array).to include("pg_sql_triggers/application.css")
      expect(precompile_array).to include("pg_sql_triggers/application.js")
    end

    it "skips asset configuration when assets not available" do
      allow(config).to receive(:respond_to?).with(:assets).and_return(false)

      initializer = described_class.initializers.find { |i| i.name == "pg_sql_triggers.assets" }
      expect(initializer).to be_present

      expect { initializer.block.call(app) }.not_to raise_error
    end
  end

  describe "rake tasks" do
    it "loads rake tasks" do
      # Verify the task file exists
      task_file = described_class.root.join("lib/tasks/trigger_migrations.rake")
      expect(File.exist?(task_file)).to be true

      # Verify rake tasks are configured (Rails Engine automatically loads rake tasks)
      expect(described_class.respond_to?(:rake_tasks)).to be true
    end
  end
end
