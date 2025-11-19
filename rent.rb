require 'json'
require 'date'
require 'singleton'
require_relative 'lib/rent_config_store'
require_relative 'lib/roommate_store'
require_relative 'lib/rent_history'
require_relative 'lib/persistence'
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
      vattenavgift: 343,  # Monthly water fee (proportional to 754 kr/month total)
      va: 274,           # Monthly sewage fee (proportional to 754 kr/month total)
      larm: 137,        # Monthly alarm system fee (proportional to 754 kr/month total)
      drift_rakning: nil, # Quarterly invoice - stored in DB but NOT used in calculations
      saldo_innan: 0,    # Default to no previous balance
      extra_in: 0,       # Extra income that reduces total rent
      gas: 83            # Gas for stove: 500 kr per 6 months = 83 kr/month baseline
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
    # VIRTUAL POT SYSTEM: Always use consistent monthly accruals, never actual invoice amounts
    # - Building ops: vattenavgift + va + larm = 754 kr/month (saves up for quarterly invoices)
    # - Gas: 83 kr/month baseline (saves up for 500 kr refills every 6 months)
    # - drift_rakning stored in DB for tracking/projections but NOT used in billing
    # - Dashboard shows virtual pot balance and warns if insufficient for upcoming invoices
    def drift_total
      monthly_building_ops = vattenavgift + va + larm  # Provided values or 754 kr default
      monthly_gas = gas  # Always 83 kr

      # NEVER use drift_rakning amount here - it creates rent spikes and inflates annual average
      el + bredband + monthly_building_ops + monthly_gas
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

      # NEW: Save to database (single source of truth)
      unless history_options.fetch(:test_mode, false)
        config_repo = Persistence.rent_configs
        tenant_repo = Persistence.tenants
        ledger_repo = Persistence.rent_ledger

        # RentLedger period semantics: Use config month (not rent month)
        # Example: Oct config → period 2025-10-01 (not 2025-11-01)
        # The RentLedger model's period_swedish() method converts config→rent for display
        config_period = Time.utc(config.year, config.month, 1)

        config.to_h.each do |key, value|
          next if value.nil? || value == 0
          next if [:year, :month].include?(key)

          config_repo.upsert(key: key.to_s, value: value, period: config_period)
        end

        tenant_map = tenant_repo.all.each_with_object({}) do |tenant, memo|
          memo[tenant.name] = tenant.id
        end

        base_monthly_rent = config.kallhyra / roommates.size.to_f

        breakdown['Rent per Roommate'].each do |tenant_name, amount|
          tenant_id = tenant_map[tenant_name]
          next unless tenant_id

          roommate_config = roommates[tenant_name] || {}
          days_stayed = roommate_config[:days]
          room_adjustment = roommate_config[:room_adjustment] || 0

          ledger_repo.upsert_entry(
            tenant_id: tenant_id,
            period: config_period,  # Changed: Now uses config month (unified semantics)
            amount_due: amount,
            days_stayed: days_stayed,
            room_adjustment: room_adjustment,
            base_monthly_rent: base_monthly_rent,
            calculation_title: history_options[:title],
            calculation_date: Time.now.utc
          )
        end

        $pubsub&.publish('rent_data_updated')
      end

      # OLD: JSON file saving (DEPRECATED - database is now source of truth)
      # Keeping this code for compatibility during transition period
      # TODO: Remove after verifying database auto-save works in production
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
      # history.save(force: history_options.fetch(:force, false))  # DISABLED: Using database now

      breakdown
    end

    # Generates a user-friendly string summarizing the rent calculation
    #
    # @param roommates [Hash] Roommate configuration hash
    # @param config [Hash, Config] Configuration for the CONFIGURATION PERIOD
    #
    # CRITICAL TIMING CONCEPT:
    #   The config represents the CONFIG PERIOD (e.g., September) but the message
    #   displays rent for the FOLLOWING month (e.g., October).
    #
    # @example Swedish Rent Payment Timing
    #   # September 27: Generate message for October rent
    #   config = { year: 2025, month: 9 }  # September configuration period
    #   message = friendly_message(roommates: roommates, config: config)
    #   # Returns: "Hyran för oktober 2025 ska betalas innan 27 sep"
    #
    #   This message uses:
    #   - September electricity bills (arrears)
    #   - October base rent (advance)
    #   - Result: Total due for October housing
    #
    # @return [String] Swedish-language rent summary message
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

    # Convenience method for handlers - fetches everything automatically
    #
    # @param year [Integer] Config period year (defaults to current)
    # @param month [Integer] Config period month (defaults to current)
    # @param repository [Object] Config repository (defaults to Persistence)
    # @return [Hash] Complete rent breakdown
    #
    # @example Current month rent (zero params)
    #   breakdown = RentCalculator.rent_breakdown_for_period
    #   # Uses current year/month, fetches config + roommates automatically
    #
    # @example Historical rent (testing/debugging)
    #   breakdown = RentCalculator.rent_breakdown_for_period(year: 2025, month: 9)
    def rent_breakdown_for_period(
      year: Time.now.year,
      month: Time.now.month,
      repository: Persistence.rent_configs
    )
      # Fetch config with automatic projection
      config = RentConfig.for_period(
        year: year,
        month: month,
        repository: repository,
        with_projection: true
      ).transform_keys(&:to_sym).transform_values(&:to_i)

      # Fetch roommates automatically
      roommates = extract_roommates_for_period(year, month)

      # Calculate breakdown
      rent_breakdown(roommates: roommates, config: config)
    end

    private

    # Extract roommates for a specific period
    # @param year [Integer] Config period year
    # @param month [Integer] Config period month
    # @return [Hash] Roommates hash for RentCalculator
    def extract_roommates_for_period(year, month)
      tenants = Persistence.tenants.all

      raise "Cannot calculate rent - no tenants found in database" if tenants.empty?

      period_start = Date.new(year, month, 1)
      period_end = Date.new(year, month, Helpers.days_in_month(year, month))

      tenants.each_with_object({}) do |tenant, hash|
        days_stayed = tenant.days_stayed_in_period(period_start, period_end)
        next if days_stayed <= 0

        hash[tenant.name] = {
          days: days_stayed,
          room_adjustment: (tenant.room_adjustment || 0).to_i
        }
      end
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
