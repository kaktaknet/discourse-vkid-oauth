# frozen_string_literal: true

# VK ID Authenticator for Discourse
# Implements OAuth 2.1 authentication with VK ID (id.vk.ru)
# Supports automatic migration from legacy vkontakte provider
class VkidAuthenticator < Auth::ManagedAuthenticator
  # Provider name (must match OmniAuth strategy name)
  def name
    'vkid'
  end

  # Check if VK ID authentication is enabled
  def enabled?
    SiteSetting.vkid_enabled
  end

  # Register custom VK ID OmniAuth strategy
  # IMPORTANT: No HTTP requests here - this runs at Discourse startup
  def register_middleware(omniauth)
    omniauth.provider :vkid,
      SiteSetting.vkid_client_id,
      SiteSetting.vkid_client_secret,
      scope: SiteSetting.vkid_scope || 'vkid.personal_info email phone'
  end

  # Process authentication after OAuth flow completes
  # Handles user creation, updates, and migration from old provider
  # @param auth_token [OmniAuth::AuthHash] Authentication data from VK ID
  # @param existing_account [User] Existing user if already linked
  # @return [Auth::Result] Authentication result
  def after_authenticate(auth_token, existing_account: nil)
    Rails.logger.info("[VK ID Authenticator] Processing auth for uid=#{auth_token.uid}")

    # CRITICAL: Always call super to execute base authentication logic
    result = super

    # Extract email from user_info or id_token
    result.email = auth_token.info.email

    # IMPORTANT: VK ID guarantees verified email only if 'email' is in scope
    # Check both id_token email_verified claim and scope presence
    result.email_valid = auth_token.extra.dig(:id_token_claims, 'email_verified') ||
                        (auth_token.extra.dig(:scope)&.include?('email'))

    # Generate unique username
    result.username = generate_username(auth_token)
    result.name = auth_token.info.name

    # Store additional data in UserAssociatedAccount
    # This data is accessible via UserAssociatedAccount.find_by(provider_name: 'vkid')
    result.extra_data = {
      vkid_user_id: auth_token.uid.to_s,
      vkid_first_name: auth_token.info.first_name,
      vkid_last_name: auth_token.info.last_name,
      vkid_phone: auth_token.info.phone,
      vkid_scope: auth_token.extra.dig(:scope)
    }

    Rails.logger.info("[VK ID Authenticator] Auth result: email=#{result.email}, username=#{result.username}, email_valid=#{result.email_valid}")

    # MIGRATION: Check if user exists under old 'vkontakte' provider
    # This allows seamless transition from old plugin to new VK ID
    if existing_account.nil? && result.user.nil?
      migrated_user = migrate_from_old_provider(auth_token.uid)
      if migrated_user
        Rails.logger.info("[VK ID Authenticator] Migrated user from old vkontakte provider: user_id=#{migrated_user.id}")
        result.user = migrated_user
      end
    end

    result
  end

  # Determine if email from provider is verified
  # VK ID uses id_token claims for verification status
  # @param auth_token [OmniAuth::AuthHash] Authentication data
  # @return [Boolean] True if email is verified
  def primary_email_verified?(auth_token)
    verified = auth_token.extra.dig(:id_token_claims, 'email_verified') == true

    Rails.logger.info("[VK ID Authenticator] Email verification check: #{verified}")
    verified
  end

  # Return description for user preferences page
  # Shows user's VK name or email
  # @param user [User] Discourse user
  # @return [String] User description
  def description_for_user(user)
    info = UserAssociatedAccount.find_by(
      provider_name: name,
      user_id: user.id
    )&.info

    return "" if info.nil?

    # Display name or email
    info["name"] || info["email"] || ""
  end

  private

  # Generate unique username from VK ID data
  # Tries first_name, email prefix, or fallback to vkid_<uid>
  # @param auth_token [OmniAuth::AuthHash] Authentication data
  # @return [String] Unique username
  def generate_username(auth_token)
    # Try different sources for username
    username = auth_token.info.first_name&.downcase ||
               auth_token.info.email&.split('@')&.first ||
               "vkid_#{auth_token.uid}"

    # Clean invalid characters (Discourse allows: a-z, A-Z, 0-9, _)
    username = username.gsub(/[^a-zA-Z0-9_]/, '_')

    # Discourse max username length is 20 characters
    username = username[0...20]

    # Ensure uniqueness
    ensure_unique_username(username)
  end

  # Ensure username is unique in database
  # Appends counter if username already exists
  # @param username [String] Desired username
  # @return [String] Unique username
  def ensure_unique_username(username)
    original = username
    counter = 1

    while User.exists?(username: username)
      username = "#{original}_#{counter}"
      counter += 1

      # Protection against infinite loop
      break if counter > 1000
    end

    username
  end

  # Migrate user from old 'vkontakte' provider to new 'vkid'
  # Searches for existing UserAssociatedAccount with same uid
  # @param vkid_uid [String] VK user ID
  # @return [User, nil] Migrated user or nil
  def migrate_from_old_provider(vkid_uid)
    old_account = UserAssociatedAccount.find_by(
      provider_name: 'vkontakte',
      provider_uid: vkid_uid.to_s
    )

    return nil unless old_account

    Rails.logger.info("[VK ID Authenticator] Found old vkontakte account for uid=#{vkid_uid}, user_id=#{old_account.user_id}")

    # Update provider_name to new 'vkid'
    # This preserves all user data and associations
    old_account.update!(provider_name: 'vkid')

    Rails.logger.info("[VK ID Authenticator] Successfully migrated account to vkid provider")

    old_account.user
  rescue => e
    Rails.logger.error("[VK ID Authenticator] Migration failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end
end
