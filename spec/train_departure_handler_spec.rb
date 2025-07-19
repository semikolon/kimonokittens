require 'rspec'
require 'faraday'
require 'active_support/time'
require_relative '../handlers/train_departure_handler'

RSpec.describe TrainDepartureHandler do
  let(:handler) { TrainDepartureHandler.new }
  let(:mock_response) { double('Faraday::Response') }
  
  # Mock ResRobot API response data
  let(:mock_resrobot_data) do
    {
      'Departure' => [
        {
          'name' => 'Pendeltåg 41',
          'type' => 'TRAIN',
          'stop' => 'Huddinge',
          'time' => (Time.now + 15.minutes).strftime('%H:%M:%S'),
          'date' => Date.current.strftime('%Y-%m-%d'),
          'direction' => 'Stockholm Central',
          'cancelled' => false
        },
        {
          'name' => 'Pendeltåg 41',
          'type' => 'TRAIN',
          'stop' => 'Huddinge',
          'time' => (Time.now + 30.minutes).strftime('%H:%M:%S'),
          'date' => Date.current.strftime('%Y-%m-%d'),
          'direction' => 'Stockholm Central',
          'cancelled' => false
        },
        {
          'name' => 'Pendeltåg 42',
          'type' => 'TRAIN',
          'stop' => 'Huddinge',
          'time' => (Time.now + 45.minutes).strftime('%H:%M:%S'),
          'date' => Date.current.strftime('%Y-%m-%d'),
          'direction' => 'Nynäshamn',
          'cancelled' => false
        }
      ]
    }
  end

  before do
    # Set up environment variables with default stub
    allow(ENV).to receive(:[]).and_return(nil)
    allow(ENV).to receive(:[]).with('RESROBOT_API_KEY').and_return('mock_api_key')
    allow(ENV).to receive(:[]).with('SL_API_KEY').and_return('fallback_key')
    
    # Stub the constant since it's set at class load time
    stub_const('TrainDepartureHandler::RESROBOT_API_KEY', 'mock_api_key')
    
    # Reset handler state
    handler.instance_variable_set(:@data, nil)
    handler.instance_variable_set(:@fetched_at, nil)
  end

  describe '#call' do
    context 'when ResRobot API responds successfully' do
      before do
        allow(mock_response).to receive(:success?).and_return(true)
        allow(mock_response).to receive(:status).and_return(200)
        allow(mock_response).to receive(:body).and_return(mock_resrobot_data.to_json)
        
        allow(Faraday).to receive(:get).and_return(mock_response)
      end

      it 'returns train departures with correct structure' do
        status, headers, body = handler.call(nil)
        
        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')
        
        parsed_body = JSON.parse(body.first)
        expect(parsed_body).to have_key('summary')
        expect(parsed_body).to have_key('deviation_summary')
        expect(parsed_body['summary']).to be_a(String)
      end

      it 'makes request with correct parameters' do
        expect(Faraday).to receive(:get).with(
          'https://api.resrobot.se/v2.1/departureBoard',
          {
            key: 'mock_api_key',
            id: '740000003',
            duration: 60,
            format: 'json'
          }
        ).and_return(mock_response)
        
        handler.call(nil)
      end

      it 'filters for northbound trains only' do
        status, headers, body = handler.call(nil)
        parsed_body = JSON.parse(body.first)
        
        # Should only include northbound trains in the summary
        expect(parsed_body['summary']).to include('14:') # Contains afternoon departure times
        expect(parsed_body['summary']).to include('<strong>') # Has HTML formatting
        expect(parsed_body['summary']).to include('om') # Shows minutes until departure
        # Should contain 2 trains (2 <strong> tags for northbound trains only)
        expect(parsed_body['summary'].scan(/<strong>/).count).to eq(2)
      end

      it 'caches data for subsequent requests' do
        # First call
        handler.call(nil)
        
        # Second call should not make another API request
        expect(Faraday).not_to receive(:get)
        handler.call(nil)
      end
    end

    context 'when ResRobot API returns server error' do
      before do
        allow(mock_response).to receive(:success?).and_return(false)
        allow(mock_response).to receive(:status).and_return(500)
        allow(mock_response).to receive(:body).and_return('Internal Server Error')
        allow(Faraday).to receive(:get).and_return(mock_response)
      end

      it 'uses fallback data when API fails' do
        expect { handler.call(nil) }.to output(/WARNING: ResRobot API failed/).to_stdout
        
        status, headers, body = handler.call(nil)
        expect(status).to eq(200)
        
        parsed_body = JSON.parse(body.first)
        expect(parsed_body['summary']).not_to be_empty
        expect(parsed_body['summary']).to include('strong') # HTML formatting
        expect(parsed_body['deviation_summary']).to eq('')
      end
    end

    context 'when network timeout occurs' do
      before do
        allow(Faraday).to receive(:get).and_raise(Faraday::TimeoutError.new('execution expired'))
      end

      it 'uses fallback data when timeout occurs' do
        expect { handler.call(nil) }.to output(/ERROR: Exception calling ResRobot API/).to_stdout
        
        status, headers, body = handler.call(nil)
        expect(status).to eq(200)
        
        parsed_body = JSON.parse(body.first)
        expect(parsed_body['summary']).not_to be_empty
        expect(parsed_body['summary']).to include('strong') # HTML formatting
      end
    end

    context 'when connection error occurs' do
      before do
        allow(Faraday).to receive(:get).and_raise(Faraday::ConnectionFailed.new('Connection refused'))
      end

      it 'uses fallback data when connection fails' do
        expect { handler.call(nil) }.to output(/ERROR: Exception calling ResRobot API/).to_stdout
        
        status, headers, body = handler.call(nil)
        expect(status).to eq(200)
        
        parsed_body = JSON.parse(body.first)
        expect(parsed_body['summary']).not_to be_empty
      end
    end
  end

  describe '#transform_resrobot_data' do
    it 'correctly transforms ResRobot API data' do
      transformed = handler.send(:transform_resrobot_data, mock_resrobot_data)
      
      expect(transformed).to be_an(Array)
      expect(transformed.length).to eq(3)
      
      first_train = transformed.first
      expect(first_train).to have_key('destination')
      expect(first_train).to have_key('line_number')
      expect(first_train).to have_key('departure_time')
      expect(first_train).to have_key('direction')
      expect(first_train).to have_key('cancelled')
      expect(first_train).to have_key('deviation_note')
    end

    it 'determines direction correctly' do
      transformed = handler.send(:transform_resrobot_data, mock_resrobot_data)
      
      stockholm_trains = transformed.select { |train| train['destination'] == 'Stockholm Central' }
      nynashamn_trains = transformed.select { |train| train['destination'] == 'Nynäshamn' }
      
      expect(stockholm_trains.first['direction']).to eq('north')
      expect(nynashamn_trains.first['direction']).to eq('south')
    end
  end

  describe '#get_fallback_data' do
    it 'generates reasonable fallback departures' do
      fallback_data = handler.send(:get_fallback_data)
      
      expect(fallback_data).to be_an(Array)
      expect(fallback_data.length).to eq(4) # Every 15 minutes for next hour
      
      fallback_data.each do |train|
        expect(train['destination']).to eq('Stockholm Central')
        expect(train['line_number']).to eq('41')
        expect(train['direction']).to eq('north')
        expect(train['cancelled']).to be_falsey
        expect(train['deviation_note']).to eq('')
      end
    end

    it 'generates departures at 15-minute intervals' do
      fallback_data = handler.send(:get_fallback_data)
      
      departure_times = fallback_data.map { |train| Time.parse(train['departure_time']) }
      
      # Check that each departure is about 15 minutes after the previous one
      (1...departure_times.length).each do |i|
        time_diff = departure_times[i] - departure_times[i-1]
        expect(time_diff).to be_within(60).of(15 * 60) # Within 1 minute of 15 minutes
      end
    end
  end

  describe '#determine_direction' do
    it 'correctly identifies northbound destinations' do
      northbound_destinations = ['Stockholm Central', 'Södertälje Central', 'Märsta', 'Arlanda Central']
      
      northbound_destinations.each do |destination|
        direction = handler.send(:determine_direction, destination)
        expect(direction).to eq('north')
      end
    end

    it 'correctly identifies southbound destinations' do
      southbound_destinations = ['Nynäshamn', 'Västerhaninge', 'Tungelsta']
      
      southbound_destinations.each do |destination|
        direction = handler.send(:determine_direction, destination)
        expect(direction).to eq('south')
      end
    end
  end
end 