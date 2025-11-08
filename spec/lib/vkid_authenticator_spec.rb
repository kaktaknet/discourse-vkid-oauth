# frozen_string_literal: true

require 'rails_helper'

describe VkidAuthenticator do
  let(:authenticator) { VkidAuthenticator.new }
  let(:hash) do
    OmniAuth::AuthHash.new(
      provider: 'vkid',
      uid: '12345',
      info: {
        email: 'test@example.com',
        name: 'Ivan Petrov',
        first_name: 'Ivan',
        last_name: 'Petrov',
        phone: '+79991234567',
        image: 'https://sun1.userapi.com/test.jpg'
      },
      extra: {
        raw_info: {
          'user' => {
            'user_id' => '12345',
            'email' => 'test@example.com',
            'first_name' => 'Ivan',
            'last_name' => 'Petrov'
          }
        },
        id_token: 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NSIsImVtYWlsIjoidGVzdEBleGFtcGxlLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlfQ.test',
        id_token_claims: {
          'sub' => '12345',
          'email' => 'test@example.com',
          'email_verified' => true
        },
        scope: 'vkid.personal_info email phone'
      },
      credentials: {
        token: 'test_access_token'
      }
    )
  end

  describe '#name' do
    it 'returns vkid' do
      expect(authenticator.name).to eq('vkid')
    end
  end

  describe '#enabled?' do
    it 'returns true when setting is enabled' do
      SiteSetting.vkid_enabled = true
      expect(authenticator.enabled?).to be true
    end

    it 'returns false when setting is disabled' do
      SiteSetting.vkid_enabled = false
      expect(authenticator.enabled?).to be false
    end
  end

  describe '#after_authenticate' do
    before do
      SiteSetting.vkid_enabled = true
    end

    it 'creates a new user with correct attributes' do
      result = authenticator.after_authenticate(hash)

      expect(result.email).to eq('test@example.com')
      expect(result.email_valid).to be true
      expect(result.name).to eq('Ivan Petrov')
      expect(result.username).to match(/^ivan/)
      expect(result.avatar_url).to eq('https://sun1.userapi.com/test.jpg')
    end

    it 'stores extra data in UserAssociatedAccount' do
      result = authenticator.after_authenticate(hash)

      expect(result.extra_data).to include(
        vkid_user_id: '12345',
        vkid_first_name: 'Ivan',
        vkid_last_name: 'Petrov',
        vkid_phone: '+79991234567',
        vkid_scope: 'vkid.personal_info email phone'
      )
    end

    it 'verifies email when id_token has email_verified claim' do
      hash[:extra][:id_token_claims]['email_verified'] = true
      result = authenticator.after_authenticate(hash)

      expect(result.email_valid).to be true
    end

    it 'does not verify email when id_token lacks email_verified claim' do
      hash[:extra][:id_token_claims]['email_verified'] = false
      result = authenticator.after_authenticate(hash)

      expect(result.email_valid).to be false
    end

    it 'generates unique username from first_name' do
      result = authenticator.after_authenticate(hash)
      expect(result.username).to match(/^ivan/)
    end

    it 'handles username collisions by adding counter' do
      Fabricate(:user, username: 'ivan')

      result = authenticator.after_authenticate(hash)
      expect(result.username).to match(/^ivan_\d+$/)
    end

    it 'sanitizes username to remove invalid characters' do
      hash[:info][:first_name] = 'Иван-Петр@123'

      result = authenticator.after_authenticate(hash)
      expect(result.username).to match(/^[a-z0-9_]+$/)
    end

    it 'limits username to 20 characters' do
      hash[:info][:first_name] = 'VeryLongFirstNameThatExceedsLimit'

      result = authenticator.after_authenticate(hash)
      expect(result.username.length).to be <= 20
    end

    context 'migration from old vkontakte provider' do
      let!(:old_user) { Fabricate(:user, email: 'olduser@example.com') }
      let!(:old_account) do
        UserAssociatedAccount.create!(
          provider_name: 'vkontakte',
          provider_uid: '12345',
          user_id: old_user.id,
          info: { email: 'olduser@example.com' }
        )
      end

      it 'migrates existing user from vkontakte to vkid' do
        result = authenticator.after_authenticate(hash)

        expect(result.user).to eq(old_user)

        # Check that provider_name was updated
        old_account.reload
        expect(old_account.provider_name).to eq('vkid')
      end

      it 'logs migration event' do
        expect(Rails.logger).to receive(:info).with(/Migrating user from old vkontakte provider/)
        expect(Rails.logger).to receive(:info).with(/Successfully migrated account to vkid provider/)

        authenticator.after_authenticate(hash)
      end
    end

    context 'when email is missing' do
      before do
        hash[:info][:email] = nil
        hash[:extra][:id_token_claims]['email'] = nil
        hash[:extra][:raw_info]['user']['email'] = nil
      end

      it 'creates user with nil email' do
        result = authenticator.after_authenticate(hash)
        expect(result.email).to be_nil
      end

      it 'generates username from uid as fallback' do
        result = authenticator.after_authenticate(hash)
        expect(result.username).to eq('vkid_12345')
      end
    end
  end

  describe '#primary_email_verified?' do
    it 'returns true when id_token has email_verified=true' do
      hash[:extra][:id_token_claims]['email_verified'] = true
      expect(authenticator.primary_email_verified?(hash)).to be true
    end

    it 'returns false when id_token has email_verified=false' do
      hash[:extra][:id_token_claims]['email_verified'] = false
      expect(authenticator.primary_email_verified?(hash)).to be false
    end

    it 'returns false when email_verified claim is missing' do
      hash[:extra][:id_token_claims].delete('email_verified')
      expect(authenticator.primary_email_verified?(hash)).to be false
    end
  end

  describe '#description_for_user' do
    let(:user) { Fabricate(:user) }
    let!(:account) do
      UserAssociatedAccount.create!(
        provider_name: 'vkid',
        provider_uid: '12345',
        user_id: user.id,
        info: { 'name' => 'Ivan Petrov', 'email' => 'test@example.com' }
      )
    end

    it 'returns user name from associated account' do
      description = authenticator.description_for_user(user)
      expect(description).to eq('Ivan Petrov')
    end

    it 'falls back to email if name is missing' do
      account.update!(info: { 'email' => 'test@example.com' })
      description = authenticator.description_for_user(user)
      expect(description).to eq('test@example.com')
    end

    it 'returns empty string if no associated account' do
      account.destroy!
      description = authenticator.description_for_user(user)
      expect(description).to eq('')
    end
  end

  describe '#register_middleware' do
    it 'configures OmniAuth with vkid provider' do
      builder = double('OmniAuth::Builder')

      expect(builder).to receive(:provider).with(
        :vkid,
        SiteSetting.vkid_client_id,
        SiteSetting.vkid_client_secret,
        scope: SiteSetting.vkid_scope
      )

      authenticator.register_middleware(builder)
    end
  end
end
