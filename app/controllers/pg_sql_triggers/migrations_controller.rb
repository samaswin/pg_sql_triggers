# frozen_string_literal: true

module PgSqlTriggers
  # Controller for managing trigger migrations via web UI
  # Provides actions to run migrations up, down, and redo
  class MigrationsController < ApplicationController
    def up
      # Check kill switch before running migration
      check_kill_switch(operation: :ui_migration_up, confirmation: params[:confirmation_text])

      target_version = params[:version]&.to_i
      PgSqlTriggers::Migrator.ensure_migrations_table!

      if target_version
        PgSqlTriggers::Migrator.run_up(target_version)
        flash[:success] = "Migration #{target_version} applied successfully."
      else
        pending = PgSqlTriggers::Migrator.pending_migrations
        if pending.any?
          PgSqlTriggers::Migrator.run_up
          count = pending.count
          flash[:success] = "Applied #{count} pending migration(s) successfully."
        else
          flash[:info] = "No pending migrations to apply."
        end
      end
      redirect_to root_path
    rescue PgSqlTriggers::KillSwitchError => e
      flash[:error] = e.message
      redirect_to root_path
    rescue StandardError => e
      Rails.logger.error("Migration up failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to apply migration: #{e.message}"
      redirect_to root_path
    end

    def down
      # Check kill switch before rolling back migration
      check_kill_switch(operation: :ui_migration_down, confirmation: params[:confirmation_text])

      target_version = params[:version]&.to_i
      PgSqlTriggers::Migrator.ensure_migrations_table!

      current_version = PgSqlTriggers::Migrator.current_version
      if current_version.zero?
        flash[:warning] = "No migrations to rollback."
        redirect_to root_path
        return
      end

      if target_version
        PgSqlTriggers::Migrator.run_down(target_version)
        flash[:success] = "Migration version #{target_version} rolled back successfully."
      else
        # Rollback one migration by default
        PgSqlTriggers::Migrator.run_down
        flash[:success] = "Rolled back last migration successfully."
      end
      redirect_to root_path
    rescue PgSqlTriggers::KillSwitchError => e
      flash[:error] = e.message
      redirect_to root_path
    rescue StandardError => e
      Rails.logger.error("Migration down failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to rollback migration: #{e.message}"
      redirect_to root_path
    end

    def redo
      # Check kill switch before redoing migration
      check_kill_switch(operation: :ui_migration_redo, confirmation: params[:confirmation_text])

      target_version = params[:version]&.to_i
      PgSqlTriggers::Migrator.ensure_migrations_table!

      if target_version
        PgSqlTriggers::Migrator.run_down(target_version)
        PgSqlTriggers::Migrator.run_up(target_version)
        flash[:success] = "Migration #{target_version} redone successfully."
      else
        current_version = PgSqlTriggers::Migrator.current_version
        if current_version.zero?
          flash[:warning] = "No migrations to redo."
          redirect_to root_path
          return
        end

        PgSqlTriggers::Migrator.run_down
        PgSqlTriggers::Migrator.run_up
        flash[:success] = "Last migration redone successfully."
      end
      redirect_to root_path
    rescue PgSqlTriggers::KillSwitchError => e
      flash[:error] = e.message
      redirect_to root_path
    rescue StandardError => e
      Rails.logger.error("Migration redo failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to redo migration: #{e.message}"
      redirect_to root_path
    end
  end
end
