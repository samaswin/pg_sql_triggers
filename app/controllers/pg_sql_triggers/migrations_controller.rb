# frozen_string_literal: true

module PgSqlTriggers
  # Controller for managing trigger migrations via web UI
  # Provides actions to run migrations up, down, and redo
  class MigrationsController < ApplicationController
    before_action :check_operator_permission

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

      current_version = PgSqlTriggers::Migrator.current_version
      if current_version.zero?
        flash[:warning] = "No migrations to redo."
        redirect_to root_path
        return
      end

      if target_version
        redo_target_migration(target_version, current_version)
      else
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

    private

    def check_operator_permission
      return if PgSqlTriggers::Permissions.can?(current_actor, :apply_trigger)

      redirect_to root_path, alert: "Insufficient permissions. Operator role required."
    end

    def redo_target_migration(target_version, current_version)
      # For redo, we need to rollback the specific migration and re-apply it
      # If target_version is the current version, rollback the last migration
      # Otherwise, rollback to one version before target, then run up to target
      if current_version == target_version
        # Rollback the last migration (which is the target)
        PgSqlTriggers::Migrator.run_down
      elsif current_version > target_version
        rollback_to_before_target(target_version)
      else
        # Target version is not applied yet, just run it up
        PgSqlTriggers::Migrator.run_up(target_version)
        flash[:success] = "Migration #{target_version} redone successfully."
        redirect_to root_path
        return
      end

      # Now run up to the target version
      PgSqlTriggers::Migrator.run_up(target_version)
      flash.now[:success] = "Migration #{target_version} redone successfully."
    end

    def rollback_to_before_target(target_version)
      # Rollback to one version before target (this will rollback target_version too)
      # Find the migration just before target_version
      all_migrations = PgSqlTriggers::Migrator.migrations.sort_by(&:version)
      prev_migration = all_migrations.find { |m| m.version < target_version }
      if prev_migration
        # Rollback to the previous migration (this rolls back target_version)
        PgSqlTriggers::Migrator.run_down(prev_migration.version)
      else
        # No previous migration, target_version is the first migration
        # Rollback all migrations until we're below target_version
        rollback_until_below_target(target_version)
      end
    end

    def rollback_until_below_target(target_version)
      while PgSqlTriggers::Migrator.current_version >= target_version
        PgSqlTriggers::Migrator.run_down
        break if PgSqlTriggers::Migrator.current_version.zero?
      end
    end
  end
end
