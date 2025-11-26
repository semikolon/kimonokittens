require 'date'
require 'json'

# BankTransaction domain model representing a bank transaction from Lunch Flow API
#
# Encapsulates business logic for:
# - Swish payment detection
# - Rent amount matching (±1 SEK tolerance)
# - Tenant matching via reference code or name fuzzy matching
#
# PRESERVED LOGIC from implementation plan (3-tier matching)
#
# @example Create transaction from Lunch Flow API response
#   tx = BankTransaction.new(
#     external_id: 'lf_tx_abc123',
#     account_id: '4065',
#     booked_at: DateTime.parse('2025-11-15T10:30:00Z'),
#     amount: 7045.0,
#     currency: 'SEK',
#     description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
#     counterparty: 'Sanna Benemar',
#     raw_json: { id: 'lf_tx_abc123', merchant: 'Swish' }
#   )
class BankTransaction
  attr_reader :id, :external_id, :account_id, :booked_at, :amount, :currency,
              :description, :counterparty, :raw_json, :created_at

  def initialize(id: nil, external_id:, account_id:, booked_at:, amount:, currency:,
                 description: nil, counterparty: nil, raw_json:, created_at: nil)
    @id = id
    @external_id = external_id
    @account_id = account_id
    @booked_at = parse_datetime(booked_at)
    @amount = parse_amount(amount)
    @currency = currency
    @description = description || ''  # Default to empty string (DB constraint NOT NULL)
    @counterparty = counterparty
    @raw_json = parse_json(raw_json)
    @created_at = created_at
    validate!
  end

  # Check if transaction is a Swish payment
  #
  # UPDATED Nov 15, 2025: Real Lunchflow data uses merchant field
  #
  # @return [Boolean] True if merchant contains "Swish" (Mottagen/Skickad)
  #
  # @example Real Lunchflow format
  #   tx.raw_json = { merchant: 'Swish Mottagen', ... }
  #   tx.swish_payment?  # => true
  def swish_payment?
    merchant = raw_json.dig('merchant')
    return false unless merchant

    merchant.to_s.upcase.include?('SWISH')
  end

  # Check if transaction amount matches expected rent amount
  #
  # PRESERVED LOGIC from implementation plan (amount matching with tolerance)
  #
  # Uses ±1 SEK tolerance to account for rounding differences
  #
  # @param expected_amount [Numeric] Expected rent amount
  # @return [Boolean] True if amount matches within tolerance
  #
  # @example
  #   tx.amount = 7045.0
  #   tx.matches_rent?(7045.0)  # => true
  #   tx.matches_rent?(7046.0)  # => true (within tolerance)
  #   tx.matches_rent?(7100.0)  # => false
  def matches_rent?(expected_amount)
    tolerance = 1.0
    diff = (amount.abs - expected_amount.to_f.abs).abs
    diff <= tolerance
  end

  # Check if transaction belongs to a specific tenant
  #
  # PRESERVED LOGIC from implementation plan (Tier 1 & 2 matching)
  #
  # Two matching strategies:
  # 1. Reference code matching (Tier 1): Check if description contains tenant ID suffix
  # 2. Name fuzzy matching (Tier 2): Check if counterparty name matches tenant name
  #
  # @param tenant [Tenant] Tenant to match against
  # @return [Boolean] True if transaction belongs to tenant
  #
  # @example Reference code matching
  #   tx.description = "SWISH SANNA BENEMAR KK202511Sannacmhqe9enc"
  #   tenant.id = "cmhqe9enc0000wopipuxgc3kw"
  #   tx.belongs_to_tenant?(tenant)  # => true (ID suffix matches)
  #
  # @example Name fuzzy matching
  #   tx.counterparty = "Sanna Benemar"
  #   tenant.name = "Sanna Juni Benemar"
  #   tx.belongs_to_tenant?(tenant)  # => true (80%+ similarity)
  # Check if transaction has reference code for tenant (Tier 1 matching)
  # @param tenant [Tenant] Tenant to check
  # @return [Boolean] True if description contains tenant UUID
  def has_reference_code?(tenant)
    return false unless description && tenant.id

    # Reference format: KK{YYYYMM}{FirstName}{shortUUID} (no dashes for iPhone compatibility)
    # Example: KK202511Sannacmhqe9enc
    # The shortUUID could be a prefix of the tenant ID (various lengths)
    # Check both:
    # 1. If description contains any prefix of tenant ID (min 8 chars to avoid false positives)
    # 2. If description contains any suffix of tenant ID (min 8 chars)

    # Check prefixes (e.g., "cmhqe9enc" from "cmhqe9enc0000wopipuxgc3kw")
    (8..tenant.id.length).each do |len|
      prefix = tenant.id[0, len]
      return true if description.include?(prefix)
    end

    # Check suffixes (e.g., last 13 chars)
    (8..tenant.id.length).each do |len|
      suffix = tenant.id[-len..-1]
      return true if description.include?(suffix)
    end

    false
  end

  # Extract phone number from description field (Swish payments)
  # @return [String, nil] Phone number in E.164 format (+46XXXXXXXXX) or nil if not found
  #
  # @example Lunchflow format
  #   tx.description = "from: +46702894437 1803968388237103, reference: ..."
  #   tx.extract_phone_number  # => "+46702894437"
  def extract_phone_number
    return nil unless description

    # Lunchflow format: "from: +46XXXXXXXXX ..."
    match = description.match(/from:\s*(\+46\d{9})/)
    match ? match[1] : nil
  end

  # Check if extracted phone number matches tenant (Tier 2 matching - Swish)
  # @param tenant [Tenant] Tenant to check
  # @return [Boolean] True if extracted phone matches tenant phone
  #
  # @example
  #   tx.description = "from: +46702894437 ..."
  #   tenant.phone = "+46702894437"
  #   tx.phone_matches?(tenant)  # => true
  def phone_matches?(tenant)
    return false unless tenant.phone_e164

    phone = extract_phone_number
    return false unless phone

    # Normalize both phones (remove spaces, compare)
    normalize_phone(phone) == normalize_phone(tenant.phone_e164)
  end

  # Check if counterparty name matches tenant (Tier 3 matching - bank transfers)
  # @param tenant [Tenant] Tenant to check
  # @return [Boolean] True if counterparty name fuzzy-matches tenant name
  def name_matches?(tenant)
    return false unless counterparty && tenant.name
    fuzzy_name_match?(tenant.name, counterparty)
  end

  # Legacy method for backwards compatibility - checks ALL matching strategies
  # @param tenant [Tenant] Tenant to check
  # @return [Boolean] True if reference code OR phone OR name matches
  def belongs_to_tenant?(tenant)
    has_reference_code?(tenant) || phone_matches?(tenant) || name_matches?(tenant)
  end

  # Serialize transaction to hash for API responses / JSON serialization
  # @return [Hash] Hash representation of transaction
  def to_h
    {
      id: id,
      externalId: external_id,
      accountId: account_id,
      bookedAt: booked_at,
      amount: amount,
      currency: currency,
      description: description,
      counterparty: counterparty,
      rawJson: raw_json,
      createdAt: created_at
    }
  end

  private

  # Parse datetime from various input types
  # @param value [DateTime, Time, String, nil] Datetime input
  # @return [DateTime]
  def parse_datetime(value)
    return value if value.is_a?(DateTime)
    return value.to_datetime if value.is_a?(Time)
    DateTime.parse(value.to_s)
  end

  # Parse amount from various input types
  # @param value [Numeric, String] Amount input
  # @return [Float]
  def parse_amount(value)
    return value.to_f if value.is_a?(Numeric)
    value.to_s.to_f
  end

  # Parse JSON from string or return hash as-is
  # @param value [Hash, String] JSON string or Hash
  # @return [Hash]
  def parse_json(value)
    return value if value.is_a?(Hash)
    return {} if value.nil?
    JSON.parse(value)
  end

  # Normalize phone number for comparison
  # @param phone [String] Phone number in any format
  # @return [String] Normalized phone with only digits
  #
  # @example
  #   normalize_phone("+46 70 123 45 67")  # => "46701234567"
  #   normalize_phone("+46701234567")      # => "46701234567"
  def normalize_phone(phone)
    phone.to_s.gsub(/\D/, '')  # Remove all non-digits
  end

  # Fuzzy match two names using Levenshtein distance
  #
  # PRESERVED LOGIC from implementation plan (with enhanced matching)
  #
  # Uses three strategies:
  # 1. Full name match (70% similarity threshold)
  # 2. Token-based matching (all words from shorter name must appear in longer name)
  # 3. Initial matching (single letter followed by period matches full name starting with that letter)
  #
  # @param name_a [String] First name
  # @param name_b [String] Second name
  # @return [Boolean] True if names match
  def fuzzy_name_match?(name_a, name_b)
    # Normalize: lowercase, remove special chars for Levenshtein
    a = name_a.downcase.gsub(/[^a-z]/, '')
    b = name_b.downcase.gsub(/[^a-z]/, '')

    # Strategy 1: Levenshtein distance (70% threshold for full names with middle names)
    distance = levenshtein_distance(a, b)
    max_len = [a.length, b.length].max
    similarity = 1.0 - (distance.to_f / max_len)
    return true if similarity > 0.7

    # Strategy 2: Token-based matching with initial support
    tokens_a = name_a.downcase.split(/\s+/)
    tokens_b = name_b.downcase.split(/\s+/)

    shorter_tokens = tokens_a.length < tokens_b.length ? tokens_a : tokens_b
    longer_tokens = tokens_a.length < tokens_b.length ? tokens_b : tokens_a

    # Check if all tokens from shorter name appear in longer name (with initial matching)
    shorter_tokens.all? do |short_token|
      # Remove periods for comparison
      short_clean = short_token.gsub('.', '')

      # Check if it's an initial (single letter)
      if short_clean.length == 1
        # Match against first letter of any token in longer name
        longer_tokens.any? { |long_token| long_token.start_with?(short_clean) }
      else
        # Regular substring match
        longer_tokens.any? { |long_token| long_token.include?(short_clean) }
      end
    end
  end

  # Calculate Levenshtein distance between two strings
  # @param a [String] First string
  # @param b [String] Second string
  # @return [Integer] Edit distance
  def levenshtein_distance(a, b)
    return b.length if a.empty?
    return a.length if b.empty?

    # Create distance matrix
    d = Array.new(a.length + 1) { Array.new(b.length + 1) }

    # Initialize first row and column
    (0..a.length).each { |i| d[i][0] = i }
    (0..b.length).each { |j| d[0][j] = j }

    # Fill matrix
    (1..a.length).each do |i|
      (1..b.length).each do |j|
        cost = a[i - 1] == b[j - 1] ? 0 : 1
        d[i][j] = [
          d[i - 1][j] + 1,      # deletion
          d[i][j - 1] + 1,      # insertion
          d[i - 1][j - 1] + cost # substitution
        ].min
      end
    end

    d[a.length][b.length]
  end

  def validate!
    raise ArgumentError, "external_id required" if external_id.nil? || external_id.to_s.empty?
    raise ArgumentError, "booked_at required" if booked_at.nil?
    raise ArgumentError, "amount required" if amount.nil?
  end
end
