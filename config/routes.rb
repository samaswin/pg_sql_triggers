# frozen_string_literal: true

PgTriggers::Engine.routes.draw do
  root to: "dashboard#index"

  resources :triggers, only: [:index, :show] do
    member do
      post :enable
      post :disable
      post :drop
      post :re_execute
      get :diff
      post :test_syntax
      post :test_dry_run
      post :test_safe_execute
      post :test_function
    end
  end

  resources :tables, only: [:index, :show]

  resources :generator, only: [:new, :create] do
    collection do
      post :preview
      post :validate_table
      get :tables
    end
  end

  resources :sql_capsules, only: [:new, :create, :show] do
    member do
      post :execute
    end
  end
end
