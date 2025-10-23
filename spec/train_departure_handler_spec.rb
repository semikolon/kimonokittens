require_relative 'spec_helper'
require 'rspec'
require 'webmock/rspec'
require 'active_support/time'
require_relative '../handlers/train_departure_handler'

RSpec.describe TrainDepartureHandler do
  let(:handler) { TrainDepartureHandler.new }
  let(:train_url) { 'https://transport.integration.sl.se/v1/sites/9527/departures' }
  let(:bus_url) { 'https://transport.integration.sl.se/v1/sites/7027/departures' }

  # Mock SL Transport API response data
  let(:mock_sl_train_data) do
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
        }
      ]
    }
  end

  let(:mock_sl_bus_data) do
    {
      'departures' => [
        {
          'destination' => 'Skärholmen',
          'direction' => 'Skärholmen',
          'direction_code' => 1,
          'scheduled' => (Time.now + 10.minutes).iso8601,
          'expected' => (Time.now + 10.minutes).iso8601,
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
    # Set up environment variables (allow real ENV access for proxy vars)
    allow(ENV).to receive(:[]).and_call_original

    # Reset handler state
    handler.instance_variable_set(:@train_data, nil)
    handler.instance_variable_set(:@bus_data, nil)
    handler.instance_variable_set(:@fetched_at, nil)
  end

  describe '#call' do
    context 'when SL Transport API responds successfully' do
      before do
        stub_request(:get, train_url)
          .to_return(status: 200, body: mock_sl_train_data.to_json, headers: { 'Content-Type' => 'application/json' })

        stub_request(:get, bus_url)
          .to_return(status: 200, body: mock_sl_bus_data.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns train/bus departures with correct structure' do
        status, headers, body = handler.call(nil)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('application/json')

        parsed_body = JSON.parse(body.first)
        expect(parsed_body).to have_key('trains')
        expect(parsed_body).to have_key('buses')
        expect(parsed_body).to have_key('deviations')
        expect(parsed_body['trains']).to be_an(Array)
        expect(parsed_body['buses']).to be_an(Array)
      end

      it 'makes requests to both train and bus endpoints' do
        handler.call(nil)

        expect(WebMock).to have_requested(:get, train_url).once
        expect(WebMock).to have_requested(:get, bus_url).once
      end

      it 'filters for northbound trains only' do
        status, headers, body = handler.call(nil)
        parsed_body = JSON.parse(body.first)

        # Should only include northbound trains (Märsta and Stockholm Central)
        # Handler filters internally but doesn't include 'direction' field in response
        expect(parsed_body['trains'].length).to eq(2)
        destinations = parsed_body['trains'].map { |t| t['destination'] }
        expect(destinations).to include('Märsta', 'Stockholm Central')
        expect(destinations).not_to include('Södertälje centrum') # southbound, should be filtered
      end

      it 'caches data for subsequent requests' do
        # First call
        handler.call(nil)

        # Reset WebMock to verify no new requests
        WebMock.reset!

        # Stub again so test doesn't fail if cache expired
        stub_request(:get, train_url).to_return(status: 200, body: mock_sl_train_data.to_json)
        stub_request(:get, bus_url).to_return(status: 200, body: mock_sl_bus_data.to_json)

        # Second call within cache window (10 seconds)
        handler.call(nil)

        # Should not have made new requests
        expect(WebMock).not_to have_requested(:get, train_url)
        expect(WebMock).not_to have_requested(:get, bus_url)
      end
    end

    context 'when SL Transport API returns server error' do
      before do
        stub_request(:get, train_url)
          .to_return(status: 500, body: 'Internal Server Error')

        stub_request(:get, bus_url)
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'uses fallback data when API fails' do
        expect { handler.call(nil) }.to output(/WARNING: SL Transport API failed/).to_stdout

        status, headers, body = handler.call(nil)
        expect(status).to eq(200)

        parsed_body = JSON.parse(body.first)
        expect(parsed_body['trains']).not_to be_empty
        expect(parsed_body['buses']).not_to be_empty
      end
    end

    context 'when network timeout occurs' do
      before do
        stub_request(:get, train_url)
          .to_raise(Net::ReadTimeout.new('execution expired'))

        stub_request(:get, bus_url)
          .to_raise(Net::ReadTimeout.new('execution expired'))
      end

      it 'uses fallback data when timeout occurs' do
        expect { handler.call(nil) }.to output(/ERROR: Exception calling SL Transport API/).to_stdout

        status, headers, body = handler.call(nil)
        expect(status).to eq(200)

        parsed_body = JSON.parse(body.first)
        expect(parsed_body['trains']).not_to be_empty
      end
    end

    context 'when connection error occurs' do
      before do
        stub_request(:get, train_url)
          .to_raise(SocketError.new('Connection refused'))

        stub_request(:get, bus_url)
          .to_raise(SocketError.new('Connection refused'))
      end

      it 'uses fallback data when connection fails' do
        expect { handler.call(nil) }.to output(/ERROR: Exception calling SL Transport API/).to_stdout

        status, headers, body = handler.call(nil)
        expect(status).to eq(200)

        parsed_body = JSON.parse(body.first)
        expect(parsed_body['trains']).not_to be_empty
      end
    end
  end

  describe '#transform_sl_transport_data' do
    it 'correctly transforms SL Transport API data' do
      transformed = handler.send(:transform_sl_transport_data, mock_sl_train_data)

      expect(transformed).to be_an(Array)
      expect(transformed.length).to eq(3) # All trains from mock data

      first_train = transformed.first
      expect(first_train).to have_key('destination')
      expect(first_train).to have_key('line_number')
      expect(first_train).to have_key('departure_time')
      expect(first_train).to have_key('direction')
      expect(first_train).to have_key('cancelled')
      expect(first_train).to have_key('deviation_note')
    end

    it 'determines direction correctly using direction_code' do
      transformed = handler.send(:transform_sl_transport_data, mock_sl_train_data)

      north_trains = transformed.select { |train| train['direction'] == 'north' }
      south_trains = transformed.select { |train| train['direction'] == 'south' }

      expect(north_trains.length).to eq(2) # Märsta and Stockholm Central
      expect(south_trains.length).to eq(1) # Södertälje centrum
      expect(north_trains.first['destination']).to eq('Märsta')
      expect(south_trains.first['destination']).to eq('Södertälje centrum')
    end

    it 'filters to only include trains' do
      transformed = handler.send(:transform_sl_transport_data, mock_sl_train_data)

      # Should only include trains
      expect(transformed.all? { |train| %w[41].include?(train['line_number']) }).to be true
    end
  end

  describe '#get_fallback_train_data' do
    it 'generates reasonable fallback departures' do
      fallback_data = handler.send(:get_fallback_train_data)

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
      fallback_data = handler.send(:get_fallback_train_data)

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
