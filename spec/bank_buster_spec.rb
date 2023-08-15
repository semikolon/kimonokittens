require 'rspec'
require 'rspec/mocks'
require_relative '../bank_buster.rb'

describe BankBuster do
  let(:mock_driver) { instance_double("Ferrum::Browser") }
  let(:bank_buster) { BankBuster.new(driver: mock_driver) }

  describe '#parse' do
    it 'should do something' do
      # Add your test code here
    end
  end

  # Add more tests for other methods
end

describe BankPaymentsReader do
  describe '.parse_files' do
    it 'should do something' do
      # Add your test code here
    end
  end

  # Add more tests for other methods
end
