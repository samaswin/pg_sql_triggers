# frozen_string_literal: true

module PgTriggers
  # Controller for managing trigger migrations via web UI
  # Provides actions to run migrations up, down, and redo
  class MigrationsController < ApplicationController
    def up
      target_version = params[:version]&.to_i
      PgTriggers::Migrator.ensure_migrations_table!

      if target_version
        PgTriggers::Migrator.run_up(target_version)
        flash[:success] = "Migration #{target_version} applied successfully."
      else
        pending = PgTriggers::Migrator.pending_migrations
        if pending.any?
          PgTriggers::Migrator.run_up
          count = pending.count
          flash[:success] = "Applied #{count} pending migration(s) successfully."
        else
          flash[:info] = 'No pending migrations to apply.'
        end
      end
      redirect_to root_path
    rescue StandardError => e
      Rails.logger.error("Migration up failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to apply migration: #{e.message}"
      redirect_to root_path
    end

    def down
      target_version = params[:version]&.to_i
      PgTriggers::Migrator.ensure_migrations_table!

      current_version = PgTriggers::Migrator.current_version
      if current_version.zero?
        flash[:warning] = 'No migrations to rollback.'
        redirect_to root_path
        return
      end

      if target_version
        PgTriggers::Migrator.run_down(target_version)
        flash[:success] = "Migration version #{target_version} rolled back successfully."
      else
        # Rollback one migration by default
        PgTriggers::Migrator.run_down
        flash[:success] = 'Rolled back last migration successfully.'
      end
      redirect_to root_path
    rescue StandardError => e
      Rails.logger.error("Migration down failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to rollback migration: #{e.message}"
      redirect_to root_path
    end

    def redo
      target_version = params[:version]&.to_i
      PgTriggers::Migrator.ensure_migrations_table!

      if target_version
        PgTriggers::Migrator.run_down(target_version)
        PgTriggers::Migrator.run_up(target_version)
        flash[:success] = "Migration #{target_version} redone successfully."
      else
        current_version = PgTriggers::Migrator.current_version
        if current_version.zero?
          flash[:warning] = 'No migrations to redo.'
          redirect_to root_path
          return
        end

        PgTriggers::Migrator.run_down
        PgTriggers::Migrator.run_up
        flash[:success] = 'Last migration redone successfully.'
      end
      redirect_to root_path
    rescue StandardError => e
      Rails.logger.error("Migration redo failed: #{e.message}\n#{e.backtrace.join("\n")}")
      flash[:error] = "Failed to redo migration: #{e.message}"
      redirect_to root_path
    end
  end
end
