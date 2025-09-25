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
      extra_in: 0,       # Extra income that reduces total rent
      gas: 0             # Gas for stove as additional cost
    }.freeze

    attr_reader :year, :month, :kallhyra, :el, :bredband, :vattenavgift,
                :va, :larm, :drift_rakning, :saldo_innan, :extra_in, :gas

    def initialize(params = {})
      # Convert Config to hash if needed, then merge with defaults
      params_hash = params.is_a?(Config) ? params.to_h : params
      
      # Prioritize year and month from params, and ensure they are integers
      @year = (params_hash[:year] || DEFAULTS[:year])&.to_i
      @month = (params_hash[:month] || DEFAULTS[:month])&.to_i

      params_with_defaults = DEFAULTS.merge(params_hash)

      @kallhyra = params_with_defaults[:kallhyra]
      @el = params_with_defaults[:el]
      @bredband = params_with_defaults[:bredband]
      @vattenavgift = (params_with_defaults[:vattenavgift].nil? || params_with_defaults[:vattenavgift].zero?) ? DEFAULTS[:vattenavgift] : params_with_defaults[:vattenavgift]
      @va = (params_with_defaults[:va].nil? || params_with_defaults[:va].zero?) ? DEFAULTS[:va] : params_with_defaults[:va]
      @larm = (params_with_defaults[:larm].nil? || params_with_defaults[:larm].zero?) ? DEFAULTS[:larm] : params_with_defaults[:larm]
      @drift_rakning = params_with_defaults[:drift_rakning]
      @saldo_innan = params_with_defaults[:saldo_innan]
      @extra_in = params_with_defaults[:extra_in]
      @gas = params_with_defaults[:gas] || 0
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
      el + bredband + monthly_fees + gas
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
        extra_in: @extra_in,
        gas: @gas
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
    def initialize(roommates, total_days)
      @roommates = roommates
      @total_days = total_days
    end

    # Calculates prorated adjustments for each roommate and the total adjustment sum.
    # A positive adjustment is a surcharge, a negative one is a discount.
    def calculate
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
      total_days = config.days_in_month

      weight_calculator = WeightCalculator.new(roommates, total_days)
      weights, total_weight = weight_calculator.calculate

      adjustment_calculator = AdjustmentCalculator.new(roommates, total_days)
      prorated_adjustments, total_adjustment = adjustment_calculator.calculate

      # Start with the total cost, then subtract the sum of all adjustments.
      # This effectively redistributes the cost/benefit of adjustments across everyone.
      # A discount (negative adjustment) increases the amount others pay.
      # A surcharge (positive adjustment) decreases the amount others pay.
      distributable_rent = config.total_rent - total_adjustment
      rent_per_weight_point = distributable_rent / total_weight

      base_rents = {}
      final_rents = {}

      weights.each do |name, weight|
        base_rents[name] = weight * rent_per_weight_point
      end

      base_rents.each do |name, base_rent|
        adjustment = prorated_adjustments[name] || 0
        final_rents[name] = base_rent + adjustment
      end

      # Return simple hash of roommate names to rent amounts
      final_rents
    end

    # Provides a detailed breakdown of the rent calculation, with final amounts rounded.
    # This method is for display and saving, not for intermediate calculations.
    def rent_breakdown(roommates:, config: {})
      config = Config.new(config) unless config.is_a?(Config)
      total_days = config.days_in_month

      # Recalculate the detailed breakdown
      weight_calculator = WeightCalculator.new(roommates, total_days)
      weights, total_weight = weight_calculator.calculate

      adjustment_calculator = AdjustmentCalculator.new(roommates, total_days)
      prorated_adjustments, total_adjustment = adjustment_calculator.calculate

      distributable_rent = config.total_rent - total_adjustment
      rent_per_weight_point = distributable_rent / total_weight

      final_rents = calculate_rent(roommates: roommates, config: config)

      # Round only the final rent amounts for display (integer kronor)
      rounded_rents = final_rents.transform_values { |rent| rent.round }

      # Ensure the sum of rounded rents covers the total
      total_rounded = rounded_rents.values.sum
      total_rent = config.total_rent
      remainder = total_rent - total_rounded

      # Convert remainder to an integer to avoid calling `.times` on a Float
      remainder_int = remainder.round

      # Distribute remainder more fairly - prioritize those with higher fractional parts
      if remainder_int != 0
        # Calculate fractional parts for fair distribution
        fractional_parts = final_rents.map do |name, rent|
          [name, rent - rent.floor]
        end.sort_by { |_name, fraction| -fraction }  # Sort by highest fraction first
        
        # Distribute remainder starting with highest fractional parts
        remainder_int.abs.times do |i|
          name = fractional_parts[i % fractional_parts.size][0]
          if remainder_int > 0
            rounded_rents[name] += 1
          else
            rounded_rents[name] -= 1
          end
        end
      end

      # Re-round after remainder correction to ensure integers
      rounded_rents.transform_values!(&:round)

      # Optional equalization of small differences: if the max-min is less than 10 kr,
      # set everyone to the same highest amount to avoid tiny discrepancies.
      if rounded_rents.size > 1
        min_amt = rounded_rents.values.min
        max_amt = rounded_rents.values.max
        if (max_amt - min_amt).abs < 10 && max_amt != min_amt
          rounded_rents.keys.each { |k| rounded_rents[k] = max_amt }
        end
      end

      # Build the breakdown with string keys for compatibility with tests
      result = {
        'Kallhyra' => config.kallhyra,
        'El' => config.el,
        'Bredband' => config.bredband,
        'Drift total' => config.drift_total,
        'Total' => total_rent,
        'Rent per Roommate' => rounded_rents
      }

      # Add individual cost components based on config
      if config.drift_rakning && config.drift_rakning > 0
        result['Kvartalsfaktura drift'] = config.drift_rakning
      else
        result['Vattenavgift'] = config.vattenavgift
        result['VA'] = config.va
        result['Larm'] = config.larm
      end

      # Add gas if non-zero
      result['Gasol'] = config.gas if config.gas != 0
      
      # Add balances if non-zero
      result['Saldo innan'] = config.saldo_innan if config.saldo_innan != 0
      result['Extra in'] = config.extra_in if config.extra_in != 0

      # Add detailed calculation info
      result.merge!({
        config: config.to_h,
        rents: rounded_rents,
        total_rent: total_rent,
        total_paid: rounded_rents.values.sum,
        calculation_details: {
          total_weight: total_weight.round(4),
          rent_per_weight_point: rent_per_weight_point.round(2),
          prorated_adjustments: prorated_adjustments.transform_values { |adj| adj.round(2) },
          total_adjustment: total_adjustment.round(2),
          distributable_rent: distributable_rent.round(2)
        }
      })

      # Ensure returned hash uses string keys
      result.transform_keys(&:to_s)
    end

    # Calculates and saves the rent for a given month to a JSON file.
    # This is intended to be the main entry point for generating a month's rent.
    def calculate_and_save(roommates:, config: {}, history_options: {})
      config = Config.new(config) unless config.is_a?(Config)
      breakdown = rent_breakdown(roommates: roommates, config: config)

      history = RentHistory::Month.new(
        year: config.year, month: config.month,
        version: history_options[:version],
        title: history_options[:title],
        test_mode: history_options.fetch(:test_mode, false)
      )

      history.constants = config.to_h
      history.roommates = roommates
      # Record only the roommate amounts, not the entire breakdown
      history.record_results(breakdown['Rent per Roommate'])
      history.save(force: history_options.fetch(:force, false))

      breakdown
    end

    # Generates a user-friendly string summarizing the rent calculation.
    def friendly_message(roommates:, config: {})
      config = Config.new(config) unless config.is_a?(Config)
      breakdown = rent_breakdown(roommates: roommates, config: config)
      rents = breakdown['Rent per Roommate']
      total_days = config.days_in_month

      # The message shows the NEXT month (what we're paying for)
      # Since rent is paid in advance, January rent is paid in December
      next_month = config.month == 12 ? 1 : config.month + 1
      next_year = config.month == 12 ? config.year + 1 : config.year
      month_name = Helpers.swedish_month_name(next_month)
      
      # Due date is 27th of the current month (before the rent month)
      due_abbr = Helpers.swedish_month_abbr(config.month)
      header = "*Hyran för #{month_name} #{next_year}* ska betalas innan 27 #{due_abbr}"

      # Group by rent amount and collect info about days
      grouped = {}
      rents.each do |name, amount|
        days = roommates[name][:days] || total_days
        grouped[amount] ||= []
        grouped[amount] << { name: name, days: days }
      end

      # If everyone pays the same
      if grouped.size == 1
        amount = grouped.keys.first
        return "#{header}\n*#{amount} kr* för alla"
      end

      # Build message with grouped amounts
      message_lines = []
      grouped.sort_by { |amt, _| -amt }.each do |amount, people|
        if people.size == 1
          person = people.first
          if person[:days] != total_days
            days_text = person[:days] == 1 ? "dags" : "dagars"
            message_lines << "#{person[:name]}: #{amount} kr (#{person[:days]} #{days_text} boende)"
          else
            message_lines << "#{person[:name]}: #{amount} kr"
          end
        else
          # Group multiple people with same amount
          # Check if all have same days
          all_same_days = people.map { |p| p[:days] }.uniq.size == 1
          if all_same_days && people.first[:days] == total_days
            # All full month, no notation needed
            names = people.map { |p| p[:name] }.join(', ')
            message_lines << "#{names}: #{amount} kr"
          else
            # Mixed or all prorated - show individually
            people.each do |person|
              if person[:days] != total_days
                days_text = person[:days] == 1 ? "dags" : "dagars"
                message_lines << "#{person[:name]}: #{amount} kr (#{person[:days]} #{days_text} boende)"
              else
                message_lines << "#{person[:name]}: #{amount} kr"
              end
            end
          end
        end
      end

      "#{header}\n\n#{message_lines.join("\n")}"
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
