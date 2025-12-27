# frozen_string_literal: true

module PgSqlTriggers
  class Migration < ActiveRecord::Migration[6.0]
    # Base class for trigger migrations
    # Similar to ActiveRecord::Migration but for trigger-specific migrations

    def execute(sql)
      connection.execute(sql)
    end
  end
end
