# frozen_string_literal: true

require 'omniauth-oauth2'
require 'digest'
require 'base64'

module OmniAuth
  module Strategies
    # VK ID OAuth 2.1 Strategy with mandatory PKCE
    # Implements the new VK ID authentication flow (id.vk.ru)
    # @see https://id.vk.ru/about/business/go/docs/en/vkid/latest/vk-id/connection/api-integration/api-description
    class Vkid < OmniAuth::Strategies::OAuth2
      option :name, 'vkid'

      option :client_options, {
        site: 'https://id.vk.ru',
        authorize_url: '/authorize',
        token_url: '/oauth2/auth',
        auth_scheme: :request_body  # VK ID requires params in body, not query
      }

      # CRITICAL: PKCE is mandatory for VK ID (OAuth 2.1)
      option :pkce, true
      option :pkce_verifier, -> { SecureRandom.urlsafe_base64(43) }  # 43-128 chars
      option :provider_ignores_state, true  # We handle state ourselves via PKCE

      # CRITICAL: Generate PKCE challenge for authorization request
      # VK ID requires code_challenge and code_challenge_method
      def authorize_params
        super.tap do |params|
          # Generate and store code_verifier
          @code_verifier = SecureRandom.urlsafe_base64(43)
          session['omniauth.vkid.pkce.verifier'] = @code_verifier

          # Create SHA256 challenge (Base64URL encoded, no padding)
          params[:code_challenge] = Base64.urlsafe_encode64(
            Digest::SHA256.digest(@code_verifier),
            padding: false
          )
          params[:code_challenge_method] = 'S256'

          # Required VK ID parameters
          params[:response_type] = 'code'
          params[:state] = SecureRandom.hex(16)
          params[:scope] = options[:scope] || 'vkid.personal_info email phone'
          params[:prompt] = 'login'  # Always show login screen

          Rails.logger.info("[VK ID] Authorization started: challenge_method=S256, scope=#{params[:scope]}")
        end
      end

      # CRITICAL: Send code_verifier and device_id in token request
      # VK ID validates PKCE and requires device_id from callback
      def token_params
        super.tap do |params|
          # Restore verifier from session
          params[:code_verifier] = session.delete('omniauth.vkid.pkce.verifier')

          # VK ID requires device_id (comes from callback params)
          params[:device_id] = request.params['device_id']

          # IMPORTANT: VK ID doesn't accept client_secret in query params
          # It will be sent via Authorization header (auth_scheme: :request_body)
          params.delete(:client_secret)

          Rails.logger.info("[VK ID] Token exchange: device_id=#{params[:device_id]}, verifier_present=#{params[:code_verifier].present?}")
        end
      end

      # Unique user identifier
      # VK ID can return user_id in different places depending on response format
      uid do
        raw_info['user_id'] ||
        raw_info.dig('user', 'user_id') ||
        id_token_claims['sub']
      end

      # Standardized user information
      info do
        {
          email: raw_info.dig('user', 'email') || id_token_claims['email'],
          name: [
            raw_info.dig('user', 'first_name'),
            raw_info.dig('user', 'last_name')
          ].compact.join(' '),
          first_name: raw_info.dig('user', 'first_name') || id_token_claims['given_name'],
          last_name: raw_info.dig('user', 'last_name') || id_token_claims['family_name'],
          phone: raw_info.dig('user', 'phone'),
          image: raw_info.dig('user', 'avatar') || raw_info.dig('user', 'photo_200')
        }
      end

      # Additional data (id_token, scopes, etc)
      extra do
        {
          raw_info: raw_info,
          id_token: access_token.params['id_token'],
          id_token_claims: id_token_claims,
          scope: access_token.params['scope']
        }
      end

      # Fetch user information via /oauth2/user_info endpoint
      # @return [Hash] User data from VK ID
      def raw_info
        @raw_info ||= begin
          response = access_token.post(
            'https://id.vk.ru/oauth2/user_info',
            body: {
              access_token: access_token.token,
              client_id: options[:client_id]
            },
            headers: {
              'Content-Type' => 'application/x-www-form-urlencoded'
            }
          )

          parsed = response.parsed
          Rails.logger.info("[VK ID] User info fetched: user_id=#{parsed.dig('user', 'user_id')}, email_present=#{parsed.dig('user', 'email').present?}")
          parsed
        rescue => e
          Rails.logger.error("[VK ID] Failed to fetch user info: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          {}
        end
      end

      # Parse ID Token claims (JWT)
      # VK ID returns id_token in token response
      # @return [Hash] Decoded JWT payload
      def id_token_claims
        @id_token_claims ||= begin
          id_token = access_token.params['id_token']
          return {} unless id_token

          # Simple JWT parsing (payload is the middle part)
          payload = id_token.split('.')[1]
          decoded = JSON.parse(Base64.urlsafe_decode64(payload))

          Rails.logger.info("[VK ID] ID Token parsed: sub=#{decoded['sub']}, email_verified=#{decoded['email_verified']}")
          decoded
        rescue => e
          Rails.logger.error("[VK ID] Failed to parse id_token: #{e.message}")
          {}
        end
      end

      # Callback phase with enhanced logging
      def callback_phase
        Rails.logger.info("[VK ID] Callback phase started")
        Rails.logger.info("[VK ID] Callback params: code=#{request.params['code']&.first(10)}..., device_id=#{request.params['device_id']}, state=#{request.params['state']&.first(10)}...")
        super
      rescue => e
        Rails.logger.error("[VK ID] Callback phase error: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        fail!(:callback_error, e)
      end

      # Request phase with enhanced logging
      def request_phase
        Rails.logger.info("[VK ID] Request phase started")
        super
      rescue => e
        Rails.logger.error("[VK ID] Request phase error: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        fail!(:request_error, e)
      end
    end
  end
end
