# frozen_string_literal: true

begin
  PgSqlTriggers::Engine.routes.draw do
    root to: "dashboard#index"
    get "dashboard", to: "dashboard#index", as: "dashboard"

    resources :tables, only: %i[index show]

    resources :generator, only: %i[new create] do
      collection do
        post :preview
        post :validate_table
        get :tables
      end
    end

    resources :sql_capsules, only: %i[new create show] do
      member do
        post :execute
      end
    end

    resources :migrations, only: [] do
      collection do
        post :up
        post :down
        post :redo
      end
    end
  end
rescue ArgumentError => e
  # Ignore duplicate route errors (routes may already be drawn in tests)
  raise unless e.message.include?("already in use")
end
