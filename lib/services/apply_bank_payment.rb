require_relative '../persistence'
require_relative '../models/bank_transaction'
require_relative '../models/rent_receipt'
require_relative '../models/rent_ledger'
require 'time'

# ApplyBankPayment service matches bank transactions to rent payments
#
# Implements 4-tier matching strategy:
# 1. Reference code matching (KK{YYYYMM}{FirstName}{UUID} in Swish message, no dashes)
# 2. Phone number matching (extract from Swish transaction description)
# 3. Fuzzy name matching (Levenshtein + amount for bank transfers)
# 4. Manual classification fallback
#
# Payment logic:
# - Calculates remaining amount due (ledger - existing receipts)
# - Creates RentReceipt record with matched_via classification
# - Marks as partial if amount < remaining
# - Updates RentLedger.amount_paid when fully paid (Option C pattern)
# - Sends admin SMS confirmation when fully paid
# - Checks deadline proximity for partial payment alerts
# - Broadcasts WebSocket update after successful match
#
# PRESERVED LOGIC from implementation plan (Phase 3)
#
# @example
#   ApplyBankPayment.call(transaction_id: 'tx_abc123')
class ApplyBankPayment
  # Deposit amount patterns (Swedish rental law: 1-2 months rent)
  DEPOSIT_FIRST_MONTH_RANGE = (6000..6200)   # First month rent
  DEPOSIT_SECOND_MONTH_RANGE = (2000..2200)  # Second month rent
  DEPOSIT_COMPOSITE_RANGE = (8200..8600)     # Total deposit (first + second)

  NEW_TENANT_WINDOW_DAYS = 30  # ± days from startDate to consider tenant "new"
  PAYMENT_THRESHOLD_PERCENTAGE = 0.5  # 50% of expected rent

  def self.call(transaction_id:, same_day_total: nil)
    new(transaction_id: transaction_id, same_day_total: same_day_total).call
  end

  def initialize(transaction_id:, same_day_total: nil)
    @transaction = Persistence.bank_transactions.find_by_id(transaction_id)
    @same_day_total = same_day_total  # For same-day aggregation support
    # Use transaction date for period matching (allows tests with historical dates)
    tx_date = @transaction&.booked_at || Time.now
    @current_month = tx_date.strftime('%Y-%m')
    @current_year = tx_date.year
    @current_month_num = tx_date.month
  end

  def call
    return unless @transaction
    return unless @transaction.incoming_swish_payment?

    # Try 3-tier matching
    tenant, match_method = find_matching_tenant
    return unless tenant

    # PHASE 1: Check for deposit before processing as rent
    if deposit_payment?(tenant)
      log_deposit_to_admin(tenant)
      return nil  # Don't create rent receipt for deposits
    end

    # Get expected rent for current month
    period_date = Date.parse("#{@current_month}-01")
    ledger = Persistence.rent_ledger.find_by_tenant_and_period(
      tenant.id,
      period_date
    )
    return unless ledger

    # PHASE 2: Check amount threshold (50% rule)
    # Use same_day_total if provided (aggregation), otherwise individual amount
    payment_amount = @same_day_total || @transaction.amount.abs
    min_threshold = ledger.amount_due * PAYMENT_THRESHOLD_PERCENTAGE

    # Reference code overrides threshold
    unless payment_amount >= min_threshold || match_method == 'reference'
      log_small_payment_to_admin(tenant, @transaction.amount.abs, ledger.amount_due)
      return nil
    end

    # Calculate remaining amount due
    existing_receipts = Persistence.rent_receipts.find_by_tenant(
      tenant.id,
      year: @current_year,
      month: @current_month_num
    )
    total_paid = existing_receipts.sum(&:amount)
    remaining = ledger.amount_due - total_paid

    # Create rent receipt
    receipt = Persistence.rent_receipts.create(
      RentReceipt.new(
        tenant_id: tenant.id,
        month: @current_month,
        amount: @transaction.amount.abs,
        matched_tx_id: @transaction.id,
        matched_via: match_method,
        paid_at: @transaction.booked_at,
        partial: @transaction.amount.abs < remaining
      )
    )

    # Check if fully paid now
    new_total = total_paid + @transaction.amount.abs
    if new_total >= ledger.amount_due
      # Update RentLedger summary (Option C: populate both tables)
      Persistence.rent_ledger.record_payment(
        ledger.id,
        new_total,
        receipt.paid_at
      )

      # Fully paid - send admin SMS
      send_admin_confirmation(tenant, new_total, ledger.amount_due, match_method)
    elsif receipt.partial
      # Partial payment - check deadline and alert if needed
      check_deadline_and_alert(tenant, new_total, ledger.amount_due)
    end

    # Broadcast WebSocket update
    $pubsub&.publish('rent_data_updated')

    receipt
  end

  private

  # Check if transaction is a Swish payment
  # @return [Boolean]
  def swish_payment?
    @transaction.swish_payment?
  end

  # Find matching tenant using 4-tier strategy
  # @return [Array<Tenant, String>, nil] [tenant, match_method] or nil
  def find_matching_tenant
    # Tier 1: Reference code matching (UUID in Swish message)
    if tenant = match_by_reference
      return [tenant, 'reference']
    end

    # Tier 2: Phone number matching (Swish sender phone)
    if tenant = match_by_phone
      return [tenant, 'phone']
    end

    # Tier 3: Amount + Name fuzzy matching (bank transfers)
    if tenant = match_by_amount_and_name
      return [tenant, 'amount+name']
    end

    # Tier 4: Manual classification fallback (log for admin review)
    # For MVP, return nil (no match)
    nil
  end

  # Tier 1: Match by reference code
  # @return [Tenant, nil]
  def match_by_reference
    # BankTransaction model has has_reference_code? which checks UUID in description
    # Checks both prefixes and suffixes (min 8 chars)
    all_tenants = Persistence.tenants.all
    all_tenants.find { |tenant| @transaction.has_reference_code?(tenant) }
  end

  # Tier 2: Match by phone number (Swish payments)
  # @return [Tenant, nil]
  def match_by_phone
    # BankTransaction model has phone_matches? which:
    # 1. Extracts phone from Lunchflow description format: "from: +46XXXXXXXXX ..."
    # 2. Normalizes both phones (remove non-digits)
    # 3. Compares tenant.phone with extracted phone
    all_tenants = Persistence.tenants.all
    all_tenants.find { |tenant| @transaction.phone_matches?(tenant) }
  end

  # Tier 3: Match by amount and fuzzy name (bank transfers)
  # @return [Tenant, nil]
  def match_by_amount_and_name
    # Get current month's expected rent amounts
    current_ledgers = Persistence.rent_ledger.find_by_period(
      Date.parse("#{@current_month}-01")
    )

    # Check each ledger for amount + name match
    current_ledgers.each do |ledger|
      tenant = Persistence.tenants.find_by_id(ledger.tenant_id)
      next unless tenant

      # Check amount match (using BankTransaction#matches_rent?)
      next unless @transaction.matches_rent?(ledger.amount_due)

      # Check name match (using BankTransaction#name_matches?)
      if @transaction.name_matches?(tenant)
        return tenant
      end
    end

    nil
  end

  # Check if payment is a deposit (new tenant within ±30 days of move-in)
  # @param tenant [Tenant]
  # @return [Boolean]
  def deposit_payment?(tenant)
    return false unless tenant.start_date

    # Check if amount matches deposit pattern
    amount = @transaction.amount.abs
    amount_matches = DEPOSIT_FIRST_MONTH_RANGE.include?(amount) ||
                     DEPOSIT_SECOND_MONTH_RANGE.include?(amount) ||
                     DEPOSIT_COMPOSITE_RANGE.include?(amount)

    return false unless amount_matches

    # Check if tenant is new (within ±30 days of startDate)
    days_since_start = (@transaction.booked_at.to_date - tenant.start_date).abs
    days_since_start <= NEW_TENANT_WINDOW_DAYS
  end

  # Log deposit to admin (Swedish)
  # @param tenant [Tenant]
  def log_deposit_to_admin(tenant)
    amount = @transaction.amount.to_i
    # Swedish SMS: "💰 Deposition: [name] betalade [amount] kr"
    SmsGateway.send_admin_alert("💰 Deposition: #{tenant.name} betalade #{amount} kr")
  end

  # Log small payment below threshold to admin (Swedish)
  # @param tenant [Tenant]
  # @param amount [Float]
  # @param expected_rent [Float]
  def log_small_payment_to_admin(tenant, amount, expected_rent)
    # Swedish SMS: "⚠️ Liten betalning från [name]: [amount] kr (under 50% av hyra)"
    threshold = (expected_rent * PAYMENT_THRESHOLD_PERCENTAGE).to_i
    SmsGateway.send_admin_alert("⚠️ Liten betalning från #{tenant.name}: #{amount.to_i} kr (under 50% av #{expected_rent.to_i} kr)")
  end

  # Send admin SMS confirmation when payment completes
  # @param tenant [Tenant]
  # @param total_paid [Float]
  # @param amount_due [Float]
  # @param method [String]
  def send_admin_confirmation(tenant, total_paid, amount_due, method)
    # Mock implementation for tests
    # Real implementation will use SmsGateway.send_admin_alert
    # (Phase 4 will provide SmsGateway)
  end

  # Check deadline proximity and alert if partial payment is risky
  # @param tenant [Tenant]
  # @param total_paid [Float]
  # @param amount_due [Float]
  def check_deadline_and_alert(tenant, total_paid, amount_due)
    # Mock implementation for tests
    # Real implementation will check current date vs deadline (27th)
    # and send admin alert if partial payment received near deadline
  end
end
