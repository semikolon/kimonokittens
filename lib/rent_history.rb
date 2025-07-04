require 'json'
require 'fileutils'
require 'time'

# Usage:
# 1. Creating and saving a new month's rent data:
#    ```ruby
#    # Create a new month instance
#    november = RentHistory::Month.new(
#      year: 2024,
#      month: 11,
#      title: "November Calculation"  # Optional
#    )
#    
#    # Set up the base costs
#    november.constants = {
#      kallhyra: 10_000,  # Base rent
#      drift: 2_000,      # Additional costs
#      saldo_innan: 0,    # Balance from previous month
#      extra_in: 0        # Any extra income/costs
#    }
#    
#    # Set up the roommates with their days stayed and room adjustments
#    november.roommates = {
#      'Alice' => { days: 30, room_adjustment: -200 },  # Negative for discount
#      'Bob' => { days: 30, room_adjustment: 0 }        # Zero for no adjustment
#    }
#    
#    # Record the results from your calculation
#    november.record_results({
#      'Alice' => 5800.00,
#      'Bob' => 6000.00
#    })
#    
#    # Save to file (will auto-increment version number)
#    november.save  # Saves to project_root/data/rent_history/2024_11_v1.json
#    ```
#
# 2. Loading past data:
#    ```ruby
#    # Load latest version for a month
#    october = RentHistory::Month.load(
#      year: 2024,
#      month: 10
#    )
#    
#    # Access the data
#    puts october.title        # Optional version title
#    puts october.constants    # Configuration used
#    puts october.roommates    # Roommate data
#    puts october.final_results # Final rent amounts
#    ```
#
# Important notes:
# - Files are stored in two possible locations:
#   - Production: project_root/data/rent_history/YYYY_MM_vN.json (default)
#   - Test: project_root/spec/data/rent_history/YYYY_MM_vN.json (when test_mode: true)
# - See README.md for detailed documentation on:
#   - Version management and naming
#   - Error handling and recovery
#   - Testing practices
#   - Historical record keeping

module RentHistory
  class Error < StandardError; end
  class VersionError < Error; end
  class DirectoryError < Error; end

  # Configuration management for RentHistory
  class Config
    class << self
      attr_accessor :production_directory

      def setup
        @production_directory = File.expand_path(File.join(File.dirname(__FILE__), '..', 'data', 'rent_history'))
        ensure_directory!(@production_directory)
      end

      def test_directory
        path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec', 'data', 'rent_history'))
        ensure_directory!(path)
        path
      end

      def ensure_directory!(dir)
        expanded_path = File.expand_path(dir)
        FileUtils.mkdir_p(File.dirname(expanded_path))
        
        parent_dir = File.dirname(expanded_path)
        unless File.directory?(parent_dir) && File.writable?(parent_dir)
          raise DirectoryError, "Parent directory #{parent_dir} does not exist or is not writable"
        end
        
        FileUtils.mkdir_p(expanded_path) unless File.exist?(expanded_path)
        
        unless File.writable?(expanded_path)
          raise DirectoryError, "Directory #{expanded_path} is not writable"
        end
      end
    end
  end

  # Initialize default configuration
  Config.setup

  # The Month class handles storing rent data and results.
  # It stores:
  # 1. Input data (constants, roommates)
  # 2. Final results (rent per roommate)
  # 3. Basic metadata (calculation date, version, title)
  class Month
    attr_accessor :constants, :roommates, :title, :file_path
    attr_reader :year, :month, :metadata, :final_results, :version

    def initialize(year:, month:, version: nil, title: nil, test_mode: false)
      @year = year
      @month = month
      @version = version&.to_i
      @title = title
      @test_mode = test_mode
      @metadata = {
        'calculation_date' => nil,
        'version' => version&.to_i,
        'title' => title,
        'ruby_version' => RUBY_VERSION
      }
      @constants = {}
      @roommates = {}
      @final_results = {}
    end

    # Records the final results of a rent calculation
    def record_results(results)
      @final_results = results
      @metadata['calculation_date'] = Time.now.iso8601
    end

    # Save the current state to a JSON file
    def save(version: nil, force: false)
      @version = determine_version(version)
      @metadata['version'] = @version
      @metadata['title'] = @title

      ensure_directory!
      
      if File.exist?(file_path) && !force
        raise VersionError, "File #{file_path} already exists. Use force: true to overwrite."
      end

      File.write(file_path, JSON.pretty_generate({
        'metadata' => @metadata,
        'constants' => @constants,
        'roommates' => @roommates,
        'final_results' => @final_results
      }))
    end

    # Load a month's data from a JSON file
    def self.load(year:, month:, version: nil, test_mode: false)
      if version.nil?
        versions = self.versions(year: year, month: month, test_mode: test_mode)
        version = versions.map(&:to_i).max if versions.any?
      end

      instance = new(year: year, month: month, version: version, test_mode: test_mode)
      return nil unless File.exist?(instance.file_path)

      data = JSON.parse(File.read(instance.file_path))
      instance.instance_variable_set(:@metadata, data['metadata'])
      instance.instance_variable_set(:@constants, symbolize_keys(data['constants']))
      instance.instance_variable_set(:@roommates, transform_roommates(data['roommates']))
      instance.instance_variable_set(:@final_results, symbolize_keys(data['final_results']))
      instance.instance_variable_set(:@version, data['metadata']['version'])
      instance.title = data['metadata']['title']
      instance
    end

    # List all available versions for a given month
    def self.versions(year:, month:, test_mode: false)
      base_dir = test_mode ? Config.test_directory : Config.production_directory
      pattern = File.join(base_dir, "#{year}_#{month.to_s.rjust(2, '0')}_v*.json")
      Dir.glob(pattern).map do |file|
        if file =~ /_v(\d+)\.json$/
          $1
        end
      end.compact.sort_by(&:to_i).map(&:to_s)
    end

    # Get the filename that would be used to save this month's data
    def filename
      base = "#{@year}_#{@month.to_s.rjust(2, '0')}"
      base += "_v#{@version}"  # Always include version
      "#{base}.json"
    end

    def file_path
      File.join(data_directory, filename)
    end

    protected

    private

    def data_directory
      @test_mode ? Config.test_directory : Config.production_directory
    end

    def ensure_directory!
      Config.ensure_directory!(data_directory)
    end

    def next_available_version
      existing = self.class.versions(year: @year, month: @month, test_mode: @test_mode)
      return 1 if existing.empty?
      existing.map(&:to_i).max + 1
    end

    def determine_version(version)
      return version if version
      return @version if @version
      next_available_version
    end

    def self.symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)
      hash.transform_keys(&:to_sym).transform_values do |value|
        value.is_a?(Hash) ? symbolize_keys(value) : value
      end
    end

    def self.transform_roommates(roommates)
      return {} unless roommates
      roommates.transform_values do |data|
        symbolize_keys(data)
      end
    end
  end
end 