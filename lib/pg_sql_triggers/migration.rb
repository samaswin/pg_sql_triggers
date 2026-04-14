# frozen_string_literal: true

module PgSqlTriggers
  class Migration < ActiveRecord::Migration[6.1]
    # Base class for trigger migrations
    # Similar to ActiveRecord::Migration but for trigger-specific migrations
    #
    # Cannot use `delegate` here: ActiveRecord::Migration defines a class-method
    # `delegate` (schema DSL) that shadows Module's `delegate` on Rails 8+.
    def execute(...)
      connection.execute(...)
    end
  end
end
