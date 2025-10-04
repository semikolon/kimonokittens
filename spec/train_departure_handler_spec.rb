require_relative 'spec_helper'
require 'rspec'
require 'faraday'
require 'active_support/time'
require_relative '../handlers/train_departure_handler'

RSpec.describe TrainDepartureHandler do
  let(:handler) { TrainDepartureHandler.new }
  let(:mock_response) { double('Faraday::Response') }
  
  # Mock SL Transport API response data
  let(:mock_sl_transport_data) do
    {
      'departures' => [
        {
          'destination' => 'Märsta',
          'direction' => 'Märsta',
          'direction_code' => 2,
          'scheduled' => (Time.now + 15.minutes).iso8601,
          'expected' => (Time.now + 15.minutes).iso8601,
          'line' => {
            'designation' => '41',
            'transport_mode' => 'TRAIN'
          },
          'deviations' => []
        },
        {
          'destination' => 'Stockholm Central',
          'direction' => 'Märsta',
          'direction_code' => 2,
          'scheduled' => (Time.now + 30.minutes).iso8601,
          'expected' => (Time.now + 30.minutes).iso8601,
          'line' => {
            'designation' => '41',
            'transport_mode' => 'TRAIN'
          },
          'deviations' => []
        },
        {
          'destination' => 'Södertälje centrum',
          'direction' => 'Södertälje centrum',
          'direction_code' => 1,
          'scheduled' => (Time.now + 45.minutes).iso8601,
          'expected' => (Time.now + 45.minutes).iso8601,
          'line' => {
            'designation' => '41',
            'transport_mode' => 'TRAIN'
          },
          'deviations' => []
        },
        {
          'destination' => 'Skärholmen',
          'direction' => 'Skärholmen',
          'direction_code' => 1,
          'scheduled' => (Time.now + 50.minutes).iso8601,
          'expected' => (Time.now + 50.minutes).iso8601,
          'line' => {
            'designation' => '744',
            'transport_mode' => 'BUS'
          },
          'deviations' => []
        }
      ]
    }
  end

  before do
    # Reset handler state
    handler.instance_variable_set(:@data, nil)
    handler.instance_variable_set(:@fetched_at, nil)
  end

  describe '#call' do
    context 'when SL Transport API responds successfully' do
      before do
        allow(mock_response).to receive(:success?).and_return(true)
        allow(mock_response).to receive(:status).and_return(200)
        allow(mock_response).to receive(:body).and_return(mock_sl_transport_data.to_json)

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

      it 'makes request with correct URL' do
        expect(Faraday).to receive(:get).with(
          'https://transport.integration.sl.se/v1/sites/9527/departures'
        ).and_return(mock_response)

        handler.call(nil)
      end

      it 'filters for northbound trains only' do
        status, headers, body = handler.call(nil)
        parsed_body = JSON.parse(body.first)

        # Should only include northbound trains in the summary
        expect(parsed_body['summary']).to include('<strong>') # Has HTML formatting
        expect(parsed_body['summary']).to include('om') # Shows minutes until departure
        # Should contain 2 trains (2 <strong> tags for northbound trains only)
        expect(parsed_body['summary'].scan(/<strong>/).count).to eq(2)
        # Summary should not be empty
        expect(parsed_body['summary']).not_to be_empty
      end

      it 'caches data for subsequent requests' do
        # First call
        handler.call(nil)
        
        # Second call should not make another API request
        expect(Faraday).not_to receive(:get)
        handler.call(nil)
      end
    end

    context 'when SL Transport API returns server error' do
      before do
        allow(mock_response).to receive(:success?).and_return(false)
        allow(mock_response).to receive(:status).and_return(500)
        allow(mock_response).to receive(:body).and_return('Internal Server Error')
        allow(Faraday).to receive(:get).and_return(mock_response)
      end

      it 'uses fallback data when API fails' do
        expect { handler.call(nil) }.to output(/WARNING: SL Transport API failed/).to_stdout
        
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
        expect { handler.call(nil) }.to output(/ERROR: Exception calling SL Transport API/).to_stdout
        
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
        expect { handler.call(nil) }.to output(/ERROR: Exception calling SL Transport API/).to_stdout
        
        status, headers, body = handler.call(nil)
        expect(status).to eq(200)
        
        parsed_body = JSON.parse(body.first)
        expect(parsed_body['summary']).not_to be_empty
      end
    end
  end

  describe '#transform_sl_transport_data' do
    it 'correctly transforms SL Transport API data' do
      transformed = handler.send(:transform_sl_transport_data, mock_sl_transport_data)

      expect(transformed).to be_an(Array)
      expect(transformed.length).to eq(3) # Only trains, excludes the bus

      first_train = transformed.first
      expect(first_train).to have_key('destination')
      expect(first_train).to have_key('line_number')
      expect(first_train).to have_key('departure_time')
      expect(first_train).to have_key('direction')
      expect(first_train).to have_key('cancelled')
      expect(first_train).to have_key('deviation_note')
    end

    it 'determines direction correctly using direction_code' do
      transformed = handler.send(:transform_sl_transport_data, mock_sl_transport_data)

      north_trains = transformed.select { |train| train['direction'] == 'north' }
      south_trains = transformed.select { |train| train['direction'] == 'south' }

      expect(north_trains.length).to eq(2) # Märsta and Stockholm Central
      expect(south_trains.length).to eq(1) # Södertälje centrum
      expect(north_trains.first['destination']).to eq('Märsta')
      expect(south_trains.first['destination']).to eq('Södertälje centrum')
    end

    it 'filters out non-train transport modes' do
      transformed = handler.send(:transform_sl_transport_data, mock_sl_transport_data)

      # Should only include trains, not the bus (744 Skärholmen)
      destinations = transformed.map { |train| train['destination'] }
      expect(destinations).not_to include('Skärholmen')
      expect(transformed.all? { |train| %w[41].include?(train['line_number']) }).to be true
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