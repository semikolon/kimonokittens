require 'rspec'
require 'faraday'
require_relative '../handlers/strava_workouts_handler'

RSpec.describe StravaWorkoutsHandler do
  let(:handler) { StravaWorkoutsHandler.new }
  let(:mock_response) { double('Faraday::Response') }
  
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
    # Set up environment variables
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
        allow(mock_response).to receive(:success?).and_return(true)
        allow(mock_response).to receive(:status).and_return(200)
        allow(mock_response).to receive(:body).and_return(mock_stats_data.to_json)
        
        allow(Faraday).to receive(:get).and_return(mock_response)
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
        expect(Faraday).to receive(:get).with(
          'https://www.strava.com/api/v3/athletes/6878181/stats',
          {},
          { 'Authorization' => 'Bearer mock_access_token' }
        ).and_return(mock_response)
        
        handler.call(nil)
      end
    end

    context 'when access token is expired (401 response)' do
      let(:unauthorized_response) { double('Faraday::Response', status: 401, success?: false) }
      let(:refresh_response) { double('Faraday::Response', success?: true, body: { access_token: 'new_token', refresh_token: 'new_refresh' }.to_json) }

      before do
        allow(mock_response).to receive(:success?).and_return(true)
        allow(mock_response).to receive(:status).and_return(200)
        allow(mock_response).to receive(:body).and_return(mock_stats_data.to_json)
        
        # First call returns 401, second call (after refresh) succeeds
        allow(Faraday).to receive(:get).and_return(unauthorized_response, mock_response)
        allow(Faraday).to receive(:post).with('https://www.strava.com/oauth/token').and_return(refresh_response)
        allow(File).to receive(:write)
      end

      it 'refreshes token and retries successfully' do
        status, headers, body = handler.call(nil)
        
        expect(status).to eq(200)
        expect(Faraday).to have_received(:get).twice
        expect(Faraday).to have_received(:post).once
      end
    end

    context 'when Strava API returns server error' do
      before do
        allow(mock_response).to receive(:success?).and_return(false)
        allow(mock_response).to receive(:status).and_return(500)
        allow(Faraday).to receive(:get).and_return(mock_response)
      end

      it 'returns 500 status with error message' do
        status, headers, body = handler.call(nil)
        
        expect(status).to eq(500)
        expect(headers['Content-Type']).to eq('application/json')
        
        parsed_body = JSON.parse(body.first)
        expect(parsed_body['error']).to eq('Failed to fetch stats from Strava')
      end
    end

    context 'when network timeout occurs' do
      before do
        allow(Faraday).to receive(:get).and_raise(Faraday::TimeoutError.new('execution expired'))
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
        allow(Faraday).to receive(:get).and_raise(Faraday::ConnectionFailed.new('Connection refused'))
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
      double('Faraday::Response', 
        success?: true, 
        body: { 
          access_token: 'new_access_token',
          refresh_token: 'new_refresh_token'
        }.to_json
      )
    end

    before do
      allow(Faraday).to receive(:post).and_return(refresh_response)
      allow(File).to receive(:write)
    end

    it 'makes correct token refresh request' do
      handler.send(:refresh_access_token)
      
      expect(Faraday).to have_received(:post).with('https://www.strava.com/oauth/token')
      expect(File).to have_received(:write).with('.refresh_token', 'new_refresh_token')
    end

    context 'when token refresh fails' do
      before do
        allow(refresh_response).to receive(:success?).and_return(false)
      end

      it 'raises an error' do
        expect { handler.send(:refresh_access_token) }.to raise_error('Failed to refresh Strava access token')
      end
    end
  end
end 