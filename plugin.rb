# frozen_string_literal: true

# name: discourse-vkid-oauth
# about: VK ID (OAuth 2.1) authentication for Discourse
# meta_topic_id: 12987
# version: 2.0.0
# authors: Discourse community
# url: https://github.com/kaktaknet/discourse-vkid-oauth
# required_version: 2.7.0

# CRITICAL: enabled_site_setting MUST be before any require statements
enabled_site_setting :vkid_enabled

# Load custom OmniAuth strategy (OAuth 2.1 with PKCE)
require_relative "lib/omniauth/strategies/vkid"

# Load VK ID authenticator
require_relative "lib/vkid_authenticator"

# Register VK ID authentication provider
auth_provider(
  title: "VK ID",
  authenticator: VkidAuthenticator.new,
  message: "Sign in with VK ID",
  icon: "fab-vk"
)

# Register VK icon for login button
register_svg_icon "fab-vk" if respond_to?(:register_svg_icon)

# Register VK ID widget assets
register_asset "stylesheets/vkid-widget.scss"
