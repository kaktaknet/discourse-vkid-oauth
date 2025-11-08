# frozen_string_literal: true

# Rake tasks for VK ID plugin migration
#
# Usage:
#   rake vkid:migrate_users           - Migrate all users from vkontakte to vkid
#   rake vkid:migration_status        - Check migration status
#   rake vkid:rollback_migration      - Rollback migration (vkid -> vkontakte)

namespace :vkid do
  desc "Migrate all users from old vkontakte provider to new vkid provider"
  task migrate_users: :environment do
    puts "Starting VK ID migration..."
    puts "=" * 60

    # Find all users with old vkontakte provider
    old_accounts = UserAssociatedAccount.where(provider_name: 'vkontakte')
    total_count = old_accounts.count

    if total_count == 0
      puts "No users found with 'vkontakte' provider."
      puts "Migration not needed or already completed."
      exit 0
    end

    puts "Found #{total_count} users to migrate."
    puts ""

    migrated = 0
    failed = 0
    errors = []

    old_accounts.find_each do |account|
      begin
        # Update provider_name from 'vkontakte' to 'vkid'
        account.update!(provider_name: 'vkid')

        migrated += 1
        print "."
        print "\n" if migrated % 50 == 0
      rescue => e
        failed += 1
        error_msg = "Failed to migrate user_id=#{account.user_id}: #{e.message}"
        errors << error_msg
        puts "\n⚠️  #{error_msg}"
      end
    end

    puts "\n"
    puts "=" * 60
    puts "Migration completed!"
    puts "✅ Successfully migrated: #{migrated} users"
    puts "❌ Failed: #{failed} users" if failed > 0
    puts ""

    if errors.any?
      puts "Errors encountered:"
      errors.each { |err| puts "  - #{err}" }
      puts ""
    end

    puts "Migration summary saved to log/vkid_migration_#{Time.now.to_i}.log"

    # Write summary to log file
    File.open("log/vkid_migration_#{Time.now.to_i}.log", 'w') do |f|
      f.puts "VK ID Migration Summary"
      f.puts "Timestamp: #{Time.now}"
      f.puts "=" * 60
      f.puts "Total accounts: #{total_count}"
      f.puts "Migrated: #{migrated}"
      f.puts "Failed: #{failed}"
      f.puts ""
      if errors.any?
        f.puts "Errors:"
        errors.each { |err| f.puts "  #{err}" }
      end
    end
  end

  desc "Check VK ID migration status"
  task migration_status: :environment do
    vkontakte_count = UserAssociatedAccount.where(provider_name: 'vkontakte').count
    vkid_count = UserAssociatedAccount.where(provider_name: 'vkid').count

    puts "VK ID Migration Status"
    puts "=" * 60
    puts "Old provider (vkontakte): #{vkontakte_count} users"
    puts "New provider (vkid):      #{vkid_count} users"
    puts ""

    if vkontakte_count == 0
      puts "✅ Migration complete! All users have been migrated to vkid."
    else
      puts "⚠️  #{vkontakte_count} users still on old vkontakte provider."
      puts "   Run 'rake vkid:migrate_users' to migrate them."
    end

    puts "=" * 60
  end

  desc "Rollback VK ID migration (vkid -> vkontakte)"
  task rollback_migration: :environment do
    puts "WARNING: This will rollback all vkid users to vkontakte provider."
    puts "This should only be used if you need to revert to the old plugin."
    print "Are you sure you want to continue? (yes/no): "

    response = STDIN.gets.chomp.downcase

    unless response == 'yes'
      puts "Rollback cancelled."
      exit 0
    end

    puts ""
    puts "Starting rollback..."
    puts "=" * 60

    vkid_accounts = UserAssociatedAccount.where(provider_name: 'vkid')
    total_count = vkid_accounts.count

    if total_count == 0
      puts "No users found with 'vkid' provider."
      exit 0
    end

    puts "Found #{total_count} users to rollback."
    puts ""

    rolled_back = 0
    failed = 0

    vkid_accounts.find_each do |account|
      begin
        account.update!(provider_name: 'vkontakte')
        rolled_back += 1
        print "."
        print "\n" if rolled_back % 50 == 0
      rescue => e
        failed += 1
        puts "\n⚠️  Failed to rollback user_id=#{account.user_id}: #{e.message}"
      end
    end

    puts "\n"
    puts "=" * 60
    puts "Rollback completed!"
    puts "✅ Successfully rolled back: #{rolled_back} users"
    puts "❌ Failed: #{failed} users" if failed > 0
    puts "=" * 60
  end

  desc "Verify VK ID plugin configuration"
  task verify_config: :environment do
    puts "VK ID Plugin Configuration Check"
    puts "=" * 60

    checks = []

    # Check if plugin is enabled
    checks << {
      name: "Plugin enabled",
      status: SiteSetting.vkid_enabled,
      value: SiteSetting.vkid_enabled ? "✅ Yes" : "❌ No"
    }

    # Check client_id
    client_id_present = SiteSetting.vkid_client_id.present?
    checks << {
      name: "Client ID configured",
      status: client_id_present,
      value: client_id_present ? "✅ Set (#{SiteSetting.vkid_client_id.length} chars)" : "❌ Not set"
    }

    # Check client_secret
    secret_present = SiteSetting.vkid_client_secret.present?
    checks << {
      name: "Client Secret configured",
      status: secret_present,
      value: secret_present ? "✅ Set (#{SiteSetting.vkid_client_secret.length} chars)" : "❌ Not set"
    }

    # Check scope
    scope = SiteSetting.vkid_scope
    scope_valid = scope.present? && scope.include?('vkid.personal_info')
    checks << {
      name: "Scope configured",
      status: scope_valid,
      value: scope_valid ? "✅ #{scope}" : "❌ Invalid or missing"
    }

    # Display results
    checks.each do |check|
      puts "#{check[:value]} - #{check[:name]}"
    end

    puts ""
    puts "=" * 60

    if checks.all? { |c| c[:status] }
      puts "✅ All configuration checks passed!"
    else
      puts "⚠️  Some configuration issues detected."
      puts "   Please review your VK ID settings in Admin -> Settings -> Login"
    end

    puts "=" * 60
  end
end
