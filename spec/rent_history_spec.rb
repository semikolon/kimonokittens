require 'rspec'
require_relative '../lib/rent_history'

RSpec.describe RentHistory::Month do
  let(:year) { 2023 }
  let(:month_number) { 11 }
  let(:test_constants) do
    {
      kallhyra: 10_000,
      drift: 2_000,
      saldo_innan: 0,
      extra_in: 0
    }
  end
  let(:test_roommates) do
    {
      'Alice' => { days: 30, room_adjustment: -200 },
      'Bob' => { days: 15, room_adjustment: 0 }
    }
  end
  let(:test_results) do
    {
      'Alice' => 6000.00,
      'Bob' => 3000.00
    }
  end

  # Clean up test files before and after the entire suite
  before(:all) do
    FileUtils.rm_rf(RentHistory::Config.test_directory)
  end

  after(:all) do
    FileUtils.rm_rf(RentHistory::Config.test_directory)
  end

  describe 'initialization' do
    subject(:month) { described_class.new(year: year, month: month_number, test_mode: true) }

    it 'sets up metadata correctly' do
      expect(month.metadata['ruby_version']).to eq(RUBY_VERSION)
      expect(month.metadata['calculation_date']).to be_nil
      expect(month.metadata['version']).to be_nil
    end

    it 'initializes empty data structures' do
      expect(month.constants).to be_empty
      expect(month.roommates).to be_empty
      expect(month.final_results).to be_empty
    end
  end

  describe 'data storage' do
    subject(:month) { described_class.new(year: year, month: month_number, test_mode: true) }

    before do
      month.constants = test_constants
      month.roommates = test_roommates
      month.record_results(test_results)
    end

    it 'stores constants correctly' do
      expect(month.constants).to eq(test_constants)
    end

    it 'stores roommate data correctly' do
      expect(month.roommates).to eq(test_roommates)
    end

    it 'stores final results correctly' do
      expect(month.final_results).to eq(test_results)
    end

    it 'updates calculation date when recording results' do
      expect(month.metadata['calculation_date']).not_to be_nil
      expect { Time.parse(month.metadata['calculation_date']) }.not_to raise_error
    end
  end

  describe 'persistence' do
    subject(:month) { described_class.new(year: year, month: month_number, test_mode: true) }

    before do
      month.constants = test_constants
      month.roommates = test_roommates
      month.record_results(test_results)
    end

    it 'saves and loads data correctly' do
      month.save
      loaded = described_class.load(year: year, month: month_number, test_mode: true)

      expect(loaded.constants).to eq(test_constants)
      expect(loaded.roommates).to eq(test_roommates)
      expect(loaded.final_results).to eq(test_results)
    end

    it 'returns nil when loading non-existent file' do
      loaded = described_class.load(year: 1999, month: 1, test_mode: true)
      expect(loaded).to be_nil
    end

    it 'creates test directory if it does not exist' do
      FileUtils.rm_rf(RentHistory::Config.test_directory)
      expect { month.save }.not_to raise_error
      expect(File.directory?(RentHistory::Config.test_directory)).to be true
    end
  end

  describe 'version handling' do
    subject(:month) { described_class.new(year: year, month: month_number, version: 1, title: 'Test Version', test_mode: true) }

    before(:each) do
      FileUtils.rm_rf(RentHistory::Config.test_directory)
      month.constants = test_constants
      month.roommates = test_roommates
      month.record_results(test_results)
    end

    it 'includes version in metadata' do
      expect(month.metadata['version']).to eq(1)
      expect(month.metadata['title']).to eq('Test Version')
    end

    it 'includes version in filename when saving' do
      expect(month.filename).to include('_v1')
    end

    it 'converts string versions to integers' do
      month = described_class.new(year: year, month: month_number, version: "2", test_mode: true)
      expect(month.version).to eq(2)
      expect(month.metadata['version']).to eq(2)
    end

    it 'auto-increments version numbers' do
      # First save should be version 1
      first_month = described_class.new(year: year, month: month_number, test_mode: true)
      first_month.constants = test_constants
      first_month.roommates = test_roommates
      first_month.record_results(test_results)
      first_month.save
      expect(first_month.version).to eq(1)
      
      # Second save should be version 2
      second_month = described_class.new(year: year, month: month_number, test_mode: true)
      second_month.constants = test_constants
      second_month.roommates = test_roommates
      second_month.record_results(test_results)
      second_month.save
      expect(second_month.version).to eq(2)
    end

    it 'lists available versions as integers' do
      month.save
      versions = described_class.versions(year: year, month: month_number, test_mode: true)
      expect(versions).to contain_exactly(month.version.to_s)
    end

    it 'raises error when trying to overwrite existing version without force' do
      month.save
      expect {
        month.save
      }.to raise_error(RentHistory::VersionError)
    end

    it 'allows overwriting with force option' do
      month.save
      expect {
        month.save(force: true)
      }.not_to raise_error
    end
  end

  describe 'directory handling' do
    it 'uses test directory when test_mode is true' do
      month = described_class.new(year: year, month: month_number, test_mode: true)
      expect(month.send(:data_directory)).to eq(RentHistory::Config.test_directory)
    end

    it 'uses production directory when test_mode is false' do
      month = described_class.new(year: year, month: month_number, test_mode: false)
      expect(month.send(:data_directory)).to eq(RentHistory::Config.production_directory)
    end

    it 'raises DirectoryError when parent directory is not writable' do
      allow(File).to receive(:directory?).and_return(true)
      allow(File).to receive(:writable?).and_return(false)
      
      month = described_class.new(year: year, month: month_number, test_mode: true)
      expect {
        month.save
      }.to raise_error(RentHistory::DirectoryError)
    end
  end
end 