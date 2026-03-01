# frozen_string_literal: true

begin
  PgSqlTriggers::Engine.routes.draw do
    root to: "dashboard#index"
    get "dashboard", to: "dashboard#index", as: "dashboard"

    resources :tables, only: %i[index show]

    resources :migrations, only: [] do
      collection do
        post :up
        post :down
        post :redo
      end
    end

    resources :triggers, only: [:show] do
      member do
        post :enable
        post :disable
        post :drop
        post :re_execute
      end
    end

    resources :audit_logs, only: [:index]
  end
rescue ArgumentError => e
  # Ignore duplicate route errors (routes may already be drawn in tests)
  raise unless e.message.include?("already in use")
end
