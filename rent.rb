require 'json'
require 'date'
require 'singleton'
require_relative 'lib/rent_config_store'
require_relative 'lib/roommate_store'
require_relative 'lib/rent_history'
require 'awesome_print'

# RentCalculator handles fair distribution of rent and costs among roommates.
# The calculation follows these key principles:
#
# **Payment Structure:**
# - Base rent (kallhyra) is paid in advance for the upcoming month
# - Operational costs (el, etc.) are paid in arrears for the previous month
# - Due date is the 27th of each month
#
# 1. Weight-based Distribution:
#    - Each roommate's share is weighted by their days stayed
#    - Weight = days_stayed / total_days_in_month
#    - This ensures fair distribution for partial months
#
# 2. Room Adjustments:
#    - Adjustments (like discounts for smaller rooms) are prorated by days stayed
#    - Prorated adjustment = full_adjustment * (days_stayed / total_days)
#    - The total adjustment amount is redistributed among all roommates based on their weights
#    - This ensures the total rent amount is always maintained
#
# 3. Cost Components:
#    - Base rent (kallhyra)
#    - Electricity (el)
#    - Internet (bredband)
#    - Operational costs, handled in two ways:
#      a) Monthly fees (vattenavgift + va + larm)
#      b) Quarterly invoice (drift_rakning) when available
#    - Previous balance (saldo_innan) is subtracted
#    - Extra income (extra_in) is subtracted
#
# 4. Calculation Flow:
#    a) Calculate each roommate's weight based on days stayed
#    b) Calculate total rent to distribute
#    c) Get base rent amounts using weights
#    d) Apply and redistribute prorated adjustments
#    e) Round only the final results (ceiling)
#
# 5. Precision Handling:
#    - All intermediate calculations maintain full floating-point precision
#    - Only the final per-roommate amounts are rounded
#    - Ceiling rounding ensures total rent is fully covered
#
module RentCalculator
  class Error < StandardError; end
  class ValidationError < Error; end

  # Helper methods for date calculations and formatting
  module Helpers
    SWEDISH_MONTHS = {
      1 => 'januari', 2 => 'februari', 3 => 'mars', 4 => 'april',
      5 => 'maj', 6 => 'juni', 7 => 'juli', 8 => 'augusti',
      9 => 'september', 10 => 'oktober', 11 => 'november', 12 => 'december'
    }.freeze

    SWEDISH_ABBR_MONTHS = {
      1 => 'jan', 2 => 'feb', 3 => 'mar', 4 => 'apr',
      5 => 'maj', 6 => 'jun', 7 => 'jul', 8 => 'aug',
      9 => 'sep', 10 => 'okt', 11 => 'nov', 12 => 'dec'
    }.freeze

    # Get the number of days in a given month/year
    def self.days_in_month(year, month)
      Date.new(year, month, -1).day
    end

    # Get Swedish month name
    def self.swedish_month_name(month)
      SWEDISH_MONTHS[month] || month.to_s
    end

    # Get Swedish month abbreviation
    def self.swedish_month_abbr(month)
      SWEDISH_ABBR_MONTHS[month] || month.to_s
    end
  end

  # Configuration class to handle all input parameters
  # Validates and provides access to all cost components
  # Handles the logic for monthly fees vs quarterly invoice
  class Config
    DEFAULTS = {
      kallhyra: 24_530,
      el: 1_324 + 276,
      bredband: 400,
      vattenavgift: 375,  # Monthly water fee (part of quarterly invoice)
      va: 300,           # Monthly sewage fee (part of quarterly invoice)
      larm: 150,        # Monthly alarm system fee (part of quarterly invoice)
      drift_rakning: nil, # Quarterly invoice (~2600 kr) that replaces the above monthly fees
      saldo_innan: 0,    # Default to no previous balance
      extra_in: 0        # Extra income that reduces total rent
    }.freeze

    attr_reader :year, :month, :kallhyra, :el, :bredband, :vattenavgift,
                :va, :larm, :drift_rakning, :saldo_innan, :extra_in

    def initialize(params = {})
      # Convert Config to hash if needed, then merge with defaults
      params_hash = params.is_a?(Config) ? params.to_h : params
      params_with_defaults = DEFAULTS.merge(params_hash)

      @year = params_with_defaults[:year]
      @month = params_with_defaults[:month]
      @kallhyra = params_with_defaults[:kallhyra]
      @el = params_with_defaults[:el]
      @bredband = params_with_defaults[:bredband]
      @vattenavgift = params_with_defaults[:vattenavgift]
      @va = params_with_defaults[:va]
      @larm = params_with_defaults[:larm]
      @drift_rakning = params_with_defaults[:drift_rakning]
      @saldo_innan = params_with_defaults[:saldo_innan]
      @extra_in = params_with_defaults[:extra_in]
      validate!
    end

    def days_in_month
      return 30 unless @year && @month
      Date.new(@year, @month, -1).day
    end

    # Calculate total operational costs (drift)
    # Note: When drift_rakning (quarterly invoice) is present, it replaces the monthly fees
    # Monthly fees (vattenavgift, va, larm) are used to save up for the quarterly invoice
    def drift_total
      monthly_fees = if drift_rakning && drift_rakning > 0
        drift_rakning  # Use quarterly invoice when present
      else
        vattenavgift + va + larm  # Otherwise use sum of monthly fees
      end
      el + bredband + monthly_fees
    end

    # Calculate total rent to be distributed among roommates
    def total_rent
      kallhyra + drift_total - saldo_innan - extra_in
    end

    def to_h
      {
        year: @year,
        month: @month,
        kallhyra: @kallhyra,
        el: @el,
        bredband: @bredband,
        vattenavgift: @vattenavgift,
        va: @va,
        larm: @larm,
        drift_rakning: @drift_rakning,
        saldo_innan: @saldo_innan,
        extra_in: @extra_in
      }
    end

    private

    def validate!
      [:kallhyra, :el, :bredband].each do |required|
        value = send(required)
        raise ValidationError, "#{required} must be a positive number" unless value.is_a?(Numeric) && value >= 0
      end
    end
  end

  # Handles weight calculations for roommates
  class WeightCalculator
    def initialize(roommates, total_days)
      @roommates = roommates
      @total_days = total_days
      validate!
    end

    def calculate
      weights = {}
      total_weight = 0.0

      @roommates.each do |name, info|
        # Default to full month if days not specified
        days = info[:days] || @total_days
        weight = days.to_f / @total_days
        weights[name] = weight
        total_weight += weight
      end

      [weights, total_weight]
    end

    private

    def validate!
      raise ValidationError, "No roommates provided" if @roommates.empty?
      
      @roommates.each do |name, info|
        # Skip validation if days not specified (will default to full month)
        next unless info[:days]
        unless info[:days].is_a?(Numeric) && info[:days] > 0 && info[:days] <= @total_days
          raise ValidationError, "Invalid days for #{name}: must be between 1 and #{@total_days}"
        end
      end
    end
  end

  # Handles room adjustments and their redistribution
  class AdjustmentCalculator
    def initialize(roommates, weights, total_weight, total_days)
      @roommates = roommates
      @weights = weights
      @total_weight = total_weight
      @total_days = total_days
    end

    def calculate_prorated_adjustments
      prorated_adjustments = Hash.new(0)
      total_adjustment = 0.0

      @roommates.each do |name, info|
        next unless info[:room_adjustment]
        
        days = info[:days] || @total_days
        prorated = info[:room_adjustment] * (days.to_f / @total_days)
        prorated_adjustments[name] = prorated
        total_adjustment += prorated
      end

      [prorated_adjustments, total_adjustment]
    end
  end

  class << self
    # Calculates rent for each roommate based on their days stayed and adjustments.
    # All calculations maintain full floating-point precision until the final results.
    # Only the final amounts in rent_breakdown are rounded, preferring ceiling to ensure
    # total rent is fully covered.
    def calculate_rent(roommates:, config: {})
      config = Config.new(config) unless config.is_a?(Config)
      weight_calculator = WeightCalculator.new(roommates, config.days_in_month)
      weights, total_weight = weight_calculator.calculate

      adjustment_calculator = AdjustmentCalculator.new(
        roommates, weights, total_weight, config.days_in_month
      )
      prorated_adjustments, total_adjustment = adjustment_calculator.calculate_prorated_adjustments

      # Calculate total rent and adjust it by the sum of all adjustments
      total_rent = config.total_rent
      adjusted_total_rent = total_rent - total_adjustment

      # Calculate base rent per weight unit from the adjusted total
      cost_per_weight = adjusted_total_rent / total_weight
      
      # Calculate final rents for each roommate
      final_rents = {}
      weights.each do |name, weight|
        base_rent = cost_per_weight * weight
        final_rents[name] = base_rent + prorated_adjustments[name]
      end

      final_rents
    end

    # Returns a complete breakdown of the rent calculation
    # This is where final rounding occurs
    def rent_breakdown(roommates:, config: {})
      config = Config.new(config) unless config.is_a?(Config)
      rents = calculate_rent(roommates: roommates, config: config)

      # Round final results here, using ceiling to ensure total rent is covered
      rounded_rents = rents.transform_values { |amount| amount.ceil(2) }

      breakdown = config.to_h
      breakdown.merge!(
        'drift_total' => config.drift_total,
        'total_rent' => config.total_rent,
        'total_distributed' => rounded_rents.values.sum.round(2),
        'rent_per_roommate' => rounded_rents
      ).transform_keys(&:to_s)
    end

    # Calculate and save rent breakdown to history
    def calculate_and_save(roommates:, config: {}, history_options: {})
      config = Config.new(config) unless config.is_a?(Config)
      results = rent_breakdown(roommates: roommates, config: config)

      if config.year && config.month
        month = RentHistory::Month.new(
          year: config.year,
          month: config.month,
          version: history_options[:version],
          title: history_options[:title],
          test_mode: history_options.fetch(:test_mode, false)
        )
        
        month.constants = config.to_h
        month.roommates = roommates
        month.record_results(results['rent_per_roommate'])
        month.save(force: history_options.fetch(:force, false))
      end

      results
    end

    # Generate a friendly message for Messenger
    def friendly_message(roommates:, config: {})
      config = Config.new(config) unless config.is_a?(Config)
      breakdown = rent_breakdown(roommates: roommates, config: config)
      rents = breakdown['rent_per_roommate']

      # Group rents by amount
      rent_groups = rents.group_by { |_, amount| amount }
      
      # Get the next month for the rent period
      next_month = config.month ? config.month + 1 : Time.now.month + 1
      next_year = config.year || Time.now.year
      
      # Adjust year if next_month is January
      if next_month > 12
        next_month = 1
        next_year += 1
      end
      
      # Get the current month for the due date
      due_month = config.month || Time.now.month
      due_year = config.year || Time.now.year
      
      # Build the message
      message = "*Hyran för #{Helpers.swedish_month_name(next_month)} #{next_year}* ska betalas innan 27 #{Helpers.swedish_month_abbr(due_month)} och blir:\n"
      
      if rent_groups.size == 1
        # Everyone pays the same
        message += "*#{format('%.2f', rent_groups.keys.first)} kr* för alla"
      else
        # Different rents - find the most common amount (full rent) and the exceptions
        sorted_groups = rent_groups.sort_by { |amount, names| [-names.size, -amount] }
        
        message_parts = sorted_groups.map do |amount, names|
          "*#{format('%.2f', amount)} kr* för #{names.map(&:first).join(' och ')}"
        end

        message += message_parts.join(' och ')
      end
      
      message
    end
  end
end

# Example usage when run directly
if __FILE__ == $0
  # Current configuration
  config = {
    kallhyra: 24530,
    el: 2103 + 1074, # Vattenfall + Fortum
    bredband: 400,
    vattenavgift: 375,
    va: 300,
    larm: 150,
    saldo_innan: 0,
    extra_in: 0
  }

  # Current roommates
  roommates = {
    'Fredrik' => {},
    'Elvira' => {},
    'Rasmus' => {},
    'Adam' => {}
  }

  # Calculate using the RentCalculator module
  results = RentCalculator.rent_breakdown(roommates: roommates, config: config)

  # Print results
  ap results
end
