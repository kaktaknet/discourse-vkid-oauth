# frozen_string_literal: true

require 'rails_helper'

describe OmniAuth::Strategies::Vkid do
  let(:app) { ->(env) { [200, env, 'app'] } }
  let(:strategy) { OmniAuth::Strategies::Vkid.new(app, 'client_id', 'client_secret') }
  let(:request) { double('Request') }

  before do
    allow(strategy).to receive(:request).and_return(request)
    allow(strategy).to receive(:session).and_return({})
  end

  describe 'basic configuration' do
    it 'has correct name' do
      expect(strategy.options.name).to eq('vkid')
    end

    it 'has correct site' do
      expect(strategy.options.client_options.site).to eq('https://id.vk.ru')
    end

    it 'has correct authorize_url' do
      expect(strategy.options.client_options.authorize_url).to eq('/authorize')
    end

    it 'has correct token_url' do
      expect(strategy.options.client_options.token_url).to eq('/oauth2/auth')
    end

    it 'uses request_body auth scheme' do
      expect(strategy.options.client_options.auth_scheme).to eq(:request_body)
    end

    it 'has PKCE enabled by default' do
      expect(strategy.options.pkce).to be true
    end
  end

  describe '#authorize_params' do
    let(:session) { {} }

    before do
      allow(strategy).to receive(:session).and_return(session)
    end

    it 'includes PKCE parameters' do
      params = strategy.authorize_params

      expect(params).to include(:code_challenge)
      expect(params).to include(:code_challenge_method)
      expect(params[:code_challenge_method]).to eq('S256')
    end

    it 'stores code_verifier in session' do
      strategy.authorize_params

      expect(session['omniauth.vkid.pkce.verifier']).not_to be_nil
      expect(session['omniauth.vkid.pkce.verifier'].length).to be >= 43
    end

    it 'generates valid SHA256 challenge' do
      params = strategy.authorize_params
      verifier = session['omniauth.vkid.pkce.verifier']

      expected_challenge = Base64.urlsafe_encode64(
        Digest::SHA256.digest(verifier),
        padding: false
      )

      expect(params[:code_challenge]).to eq(expected_challenge)
    end

    it 'includes response_type=code' do
      params = strategy.authorize_params
      expect(params[:response_type]).to eq('code')
    end

    it 'includes state parameter' do
      params = strategy.authorize_params
      expect(params[:state]).not_to be_nil
      expect(params[:state].length).to eq(32) # hex(16) = 32 chars
    end

    it 'includes default scope' do
      params = strategy.authorize_params
      expect(params[:scope]).to eq('vkid.personal_info email phone')
    end

    it 'allows custom scope' do
      strategy.options[:scope] = 'vkid.personal_info email'
      params = strategy.authorize_params

      expect(params[:scope]).to eq('vkid.personal_info email')
    end

    it 'includes prompt=login' do
      params = strategy.authorize_params
      expect(params[:prompt]).to eq('login')
    end
  end

  describe '#token_params' do
    let(:session) { { 'omniauth.vkid.pkce.verifier' => 'test_verifier_12345' } }

    before do
      allow(strategy).to receive(:session).and_return(session)
      allow(request).to receive(:params).and_return({ 'device_id' => 'device_123' })
    end

    it 'includes code_verifier from session' do
      params = strategy.token_params

      expect(params[:code_verifier]).to eq('test_verifier_12345')
    end

    it 'removes code_verifier from session after use' do
      strategy.token_params

      expect(session['omniauth.vkid.pkce.verifier']).to be_nil
    end

    it 'includes device_id from callback params' do
      params = strategy.token_params

      expect(params[:device_id]).to eq('device_123')
    end

    it 'removes client_secret from params (sent via header)' do
      params = strategy.token_params

      expect(params).not_to have_key(:client_secret)
    end

    it 'handles missing device_id gracefully' do
      allow(request).to receive(:params).and_return({})
      params = strategy.token_params

      expect(params[:device_id]).to be_nil
    end
  end

  describe '#uid' do
    before do
      allow(strategy).to receive(:raw_info).and_return({
        'user' => { 'user_id' => '12345' }
      })
      allow(strategy).to receive(:id_token_claims).and_return({})
    end

    it 'returns user_id from raw_info' do
      expect(strategy.uid).to eq('12345')
    end

    it 'falls back to id_token sub claim' do
      allow(strategy).to receive(:raw_info).and_return({})
      allow(strategy).to receive(:id_token_claims).and_return({ 'sub' => '67890' })

      expect(strategy.uid).to eq('67890')
    end
  end

  describe '#info' do
    before do
      allow(strategy).to receive(:raw_info).and_return({
        'user' => {
          'email' => 'test@example.com',
          'first_name' => 'Ivan',
          'last_name' => 'Petrov',
          'phone' => '+79991234567',
          'avatar' => 'https://example.com/avatar.jpg'
        }
      })
      allow(strategy).to receive(:id_token_claims).and_return({})
    end

    it 'returns correct email' do
      expect(strategy.info[:email]).to eq('test@example.com')
    end

    it 'combines first_name and last_name into name' do
      expect(strategy.info[:name]).to eq('Ivan Petrov')
    end

    it 'returns first_name' do
      expect(strategy.info[:first_name]).to eq('Ivan')
    end

    it 'returns last_name' do
      expect(strategy.info[:last_name]).to eq('Petrov')
    end

    it 'returns phone' do
      expect(strategy.info[:phone]).to eq('+79991234567')
    end

    it 'returns avatar URL' do
      expect(strategy.info[:image]).to eq('https://example.com/avatar.jpg')
    end

    it 'handles missing last_name' do
      allow(strategy).to receive(:raw_info).and_return({
        'user' => { 'first_name' => 'Ivan' }
      })

      expect(strategy.info[:name]).to eq('Ivan')
    end
  end

  describe '#extra' do
    let(:raw_info) { { 'user' => { 'user_id' => '12345' } } }
    let(:id_token_claims) { { 'sub' => '12345', 'email_verified' => true } }
    let(:access_token) do
      double('AccessToken', params: {
        'id_token' => 'test.jwt.token',
        'scope' => 'vkid.personal_info email'
      })
    end

    before do
      allow(strategy).to receive(:raw_info).and_return(raw_info)
      allow(strategy).to receive(:id_token_claims).and_return(id_token_claims)
      allow(strategy).to receive(:access_token).and_return(access_token)
    end

    it 'includes raw_info' do
      expect(strategy.extra[:raw_info]).to eq(raw_info)
    end

    it 'includes id_token' do
      expect(strategy.extra[:id_token]).to eq('test.jwt.token')
    end

    it 'includes id_token_claims' do
      expect(strategy.extra[:id_token_claims]).to eq(id_token_claims)
    end

    it 'includes scope' do
      expect(strategy.extra[:scope]).to eq('vkid.personal_info email')
    end
  end

  describe '#id_token_claims' do
    let(:access_token) do
      double('AccessToken', params: {
        'id_token' => 'header.eyJzdWIiOiIxMjM0NSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlfQ.signature'
      })
    end

    before do
      allow(strategy).to receive(:access_token).and_return(access_token)
    end

    it 'parses JWT payload correctly' do
      claims = strategy.send(:id_token_claims)

      expect(claims['sub']).to eq('12345')
      expect(claims['email_verified']).to be true
    end

    it 'returns empty hash if id_token is missing' do
      allow(access_token).to receive(:params).and_return({})

      claims = strategy.send(:id_token_claims)
      expect(claims).to eq({})
    end

    it 'handles invalid JWT gracefully' do
      allow(access_token).to receive(:params).and_return({ 'id_token' => 'invalid.jwt' })
      allow(Rails.logger).to receive(:error)

      claims = strategy.send(:id_token_claims)
      expect(claims).to eq({})
    end
  end

  describe 'logging' do
    it 'logs authorization start in authorize_params' do
      expect(Rails.logger).to receive(:info).with(/\[VK ID\] Authorization started/)

      strategy.authorize_params
    end

    it 'logs token exchange in token_params' do
      allow(strategy).to receive(:session).and_return({ 'omniauth.vkid.pkce.verifier' => 'test' })
      allow(request).to receive(:params).and_return({ 'device_id' => 'test_device' })
      expect(Rails.logger).to receive(:info).with(/\[VK ID\] Token exchange/)

      strategy.token_params
    end
  end

  describe 'error handling' do
    it 'logs and handles callback phase errors' do
      error = StandardError.new('Test error')
      allow(strategy).to receive(:request_phase).and_raise(error)
      allow(Rails.logger).to receive(:error)

      expect(Rails.logger).to receive(:error).with(/\[VK ID\] Request phase error/)

      expect {
        strategy.request_phase
      }.to raise_error(StandardError)
    end
  end
end
