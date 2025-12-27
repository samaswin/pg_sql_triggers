# frozen_string_literal: true

module PgTriggers
  module Generator
    class Form
      include ActiveModel::Model

      attr_accessor :trigger_name, :table_name, :function_name,
                    :version, :enabled, :condition,
                    :generate_function_stub, :events, :environments,
                    :function_body

      validates :trigger_name, presence: true, format: { with: /\A[a-z0-9_]+\z/, message: "must contain only lowercase letters, numbers, and underscores" }
      validates :table_name, presence: true
      validates :function_name, presence: true, format: { with: /\A[a-z0-9_]+\z/, message: "must contain only lowercase letters, numbers, and underscores" }
      validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
      validates :function_body, presence: true
      validate :at_least_one_event
      validate :function_name_matches_body

      def initialize(attributes = {})
        super
        @version ||= 1
        # Convert enabled to boolean (Rails checkboxes send "0" or "1" as strings)
        # Default to true for UI-generated triggers
        @enabled = case @enabled
                   when false, "0", 0 then false
                   when true, "1", 1 then true
                   else true  # Default to true (including nil case)
                   end
        @generate_function_stub = true if @generate_function_stub.nil?
        @events ||= []
        @environments ||= []
      end

      def default_function_body
        func_name = function_name.presence || 'function_name'
        <<~SQL.chomp
          CREATE OR REPLACE FUNCTION #{func_name}()
          RETURNS TRIGGER AS $$
          BEGIN
            -- Your trigger logic here
            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;
        SQL
      end

      private

      def at_least_one_event
        if events.blank? || events.reject(&:blank?).empty?
          errors.add(:events, "must include at least one event")
        end
      end

      def function_name_matches_body
        return if function_name.blank? || function_body.blank?

        # Check if function_body contains the function_name in a CREATE FUNCTION statement
        # Look for pattern: CREATE [OR REPLACE] FUNCTION function_name
        function_pattern = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:[^\(\s]+\.)?#{Regexp.escape(function_name)}\s*\(/i
        unless function_body.match?(function_pattern)
          errors.add(:function_body, "should define function '#{function_name}' (expected: CREATE [OR REPLACE] FUNCTION #{function_name}(...)")
        end
      end
    end
  end
end
