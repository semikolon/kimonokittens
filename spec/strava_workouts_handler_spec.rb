require_relative 'spec_helper'
require 'rspec'
require 'webmock/rspec'
require_relative '../handlers/strava_workouts_handler'

RSpec.describe StravaWorkoutsHandler do
  let(:handler) { StravaWorkoutsHandler.new }
  let(:stats_url) { 'https://www.strava.com/api/v3/athletes/6878181/stats' }
  let(:token_url) { 'https://www.strava.com/oauth/token' }

  # Mock Strava API response data
  let(:mock_stats_data) do
    {
      'recent_run_totals' => {
        'count' => 5,
        'distance' => 25000.0,
        'moving_time' => 7200,
        'elapsed_time' => 7800
      },
      'ytd_run_totals' => {
        'count' => 50,
        'distance' => 250000.0,
        'moving_time' => 72000,
        'elapsed_time' => 78000
      }
    }
  end

  before do
    # Set up environment variables (allow real ENV access for proxy vars)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('STRAVA_ACCESS_TOKEN').and_return('mock_access_token')
    allow(ENV).to receive(:[]).with('STRAVA_REFRESH_TOKEN').and_return('mock_refresh_token')
    allow(ENV).to receive(:[]).with('STRAVA_CLIENT_ID').and_return('mock_client_id')
    allow(ENV).to receive(:[]).with('STRAVA_CLIENT_SECRET').and_return('mock_client_secret')

    # Mock file operations
    allow(File).to receive(:exist?).with('.refresh_token').and_return(false)
  end

  describe '#call' do
    context 'when Strava API responds successfully' do
      before do
        stub_request(:get, stats_url)
          .with(headers: { 'Authorization' => 'Bearer mock_access_token' })
          .to_return(status: 200, body: mock_stats_data.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns transformed stats with 200 status' do
        status, headers, body = handler.call(nil)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')

        parsed_body = JSON.parse(body.first)
        expect(parsed_body).to have_key('runs')
        expect(parsed_body['runs']).to include('25.0 km')
        expect(parsed_body['runs']).to include('250.0 km')
      end

      it 'makes request with proper authorization header' do
        handler.call(nil)

        expect(WebMock).to have_requested(:get, stats_url)
          .with(headers: { 'Authorization' => 'Bearer mock_access_token' })
      end
    end

    context 'when access token is expired (401 response)' do
      let(:token_refresh_response) do
        {
          access_token: 'new_access_token',
          refresh_token: 'new_refresh_token'
        }.to_json
      end

      before do
        # First request returns 401
        stub_request(:get, stats_url)
          .with(headers: { 'Authorization' => 'Bearer mock_access_token' })
          .to_return(status: 401)

        # Token refresh
        stub_request(:post, token_url)
          .to_return(status: 200, body: token_refresh_response, headers: { 'Content-Type' => 'application/json' })

        # Retry with new token succeeds
        stub_request(:get, stats_url)
          .with(headers: { 'Authorization' => 'Bearer new_access_token' })
          .to_return(status: 200, body: mock_stats_data.to_json, headers: { 'Content-Type' => 'application/json' })

        allow(File).to receive(:write)
      end

      it 'refreshes token and retries successfully' do
        status, headers, body = handler.call(nil)

        expect(status).to eq(200)
        expect(WebMock).to have_requested(:get, stats_url).twice
        expect(WebMock).to have_requested(:post, token_url).once
      end
    end

    context 'when Strava API returns server error' do
      before do
        stub_request(:get, stats_url)
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'returns 500 status with error message' do
        status, headers, body = handler.call(nil)

        expect(status).to eq(500)
        expect(headers['Content-Type']).to eq('application/json')

        parsed_body = JSON.parse(body.first)
        expect(parsed_body['error']).to eq('Failed to fetch stats from Strava (500): Internal Server Error')
      end
    end

    context 'when network timeout occurs' do
      before do
        stub_request(:get, stats_url)
          .to_raise(Net::ReadTimeout.new('execution expired'))
      end

      it 'returns 504 status with timeout error' do
        status, headers, body = handler.call(nil)

        expect(status).to eq(504)
        expect(headers['Content-Type']).to eq('application/json')

        parsed_body = JSON.parse(body.first)
        expect(parsed_body['error']).to include('Strava API error')
        expect(parsed_body['error']).to include('execution expired')
      end
    end

    context 'when connection error occurs' do
      before do
        stub_request(:get, stats_url)
          .to_raise(SocketError.new('Connection refused'))
      end

      it 'returns 504 status with connection error' do
        status, headers, body = handler.call(nil)

        expect(status).to eq(504)
        expect(headers['Content-Type']).to eq('application/json')

        parsed_body = JSON.parse(body.first)
        expect(parsed_body['error']).to include('Strava API error')
        expect(parsed_body['error']).to include('Connection refused')
      end
    end
  end

  describe '#transform_stats' do
    it 'correctly transforms Strava stats into readable format' do
      transformed = handler.send(:transform_stats, mock_stats_data)

      expect(transformed).to have_key(:runs)
      expect(transformed[:runs]).to include('<strong>25.0 km</strong>')
      expect(transformed[:runs]).to include('<strong>250.0 km</strong>')
      expect(transformed[:runs]).to include('5.0 km per tur')
      expect(transformed[:runs]).to include('4:48 min/km')
    end
  end

  describe '#refresh_access_token' do
    let(:refresh_response) do
      {
        access_token: 'new_access_token',
        refresh_token: 'new_refresh_token'
      }.to_json
    end

    before do
      stub_request(:post, token_url)
        .to_return(status: 200, body: refresh_response, headers: { 'Content-Type' => 'application/json' })
      allow(File).to receive(:write)
    end

    it 'makes correct token refresh request' do
      handler.send(:refresh_access_token)

      expect(WebMock).to have_requested(:post, token_url)
      expect(File).to have_received(:write).with('.refresh_token', 'new_refresh_token')
    end

    context 'when token refresh fails' do
      before do
        stub_request(:post, token_url)
          .to_return(status: 401, body: 'Unauthorized')
      end

      it 'raises an error' do
        expect { handler.send(:refresh_access_token) }.to raise_error('Failed to refresh Strava access token')
      end
    end
  end
end
