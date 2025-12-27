# frozen_string_literal: true

module PgTriggers
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
