# Model Migration Plan: Full Domain Model Architecture

**Date:** October 21, 2025
**Status:** 🚧 IN PROGRESS
**Approach:** Full immediate migration (Option A)
**Timeline:** Single session (~4-6 hours)

---

## Executive Summary

**Goal:** Migrate from anemic repository pattern to rich domain models across all 4 database tables.

**Current Problem:**
- Domain logic scattered across RentDb, handlers, and calculation classes
- No clear ownership of business rules
- Mixed patterns create cognitive overhead
- Difficult for LLMs to understand API structure

**Solution:**
- Create proper domain models for all tables (ElectricityBill, RentConfig, Tenant, RentLedger)
- Extract domain logic from RentDb → models
- Establish repository pattern for persistence
- Service layer for multi-table transactions
- 100% preservation of rent calculation logic

**Future Benefit:**
- LLM-friendly API structure (clear domain concepts)
- Better testability (unit test domain logic without DB)
- Clearer code ownership
- Easier onboarding for future developers

---

## Current State Analysis

### Domain Logic Inventory

**ElectricityBill** (currently in RentDb):
- Billing period calculation (40 lines, critical timing logic)
- Deduplication logic
- Storage with CUID generation
- **Future needs**: Aggregation, RentConfig sync

**RentConfig** (currently in RentDb):
- Key classification (PERIOD_SPECIFIC_KEYS vs PERSISTENT_KEYS)
- Default values
- Carry-forward logic for persistent keys
- Complex retrieval with temporal queries
- **~80 lines of business logic**

**Tenant** (currently in rent.rb + RentDb):
- Room adjustment calculations
- Prorated adjustments based on days stayed
- Start/departure date logic
- **Scattered across multiple files**

**RentLedger** (currently minimal):
- Audit trail fields
- Payment tracking
- **Mostly persistence, but foundation for future business rules**

### Files Currently Holding Domain Logic

```
lib/rent_db.rb             - 341 lines (all 4 tables + domain logic)
rent.rb                    - Tenant/roommate calculations
handlers/*_handler.rb      - Some business rules
deployment/*_migration.rb  - Billing period logic (duplicated)
```

---

## Target Architecture

### Directory Structure

```
lib/
├── models/
│   ├── electricity_bill.rb      # Domain model
│   ├── rent_config.rb            # Domain model
│   ├── tenant.rb                 # Domain model
│   ├── rent_ledger.rb            # Domain model
│   └── period.rb                 # Value object
├── repositories/
│   ├── electricity_bill_repository.rb
│   ├── rent_config_repository.rb
│   ├── tenant_repository.rb
│   └── rent_ledger_repository.rb
├── services/
│   ├── apply_electricity_bill.rb    # Transaction orchestration
│   └── calculate_rent.rb            # Multi-table rent calculation
└── rent_db.rb                       # CONNECTION ONLY (no domain logic)
```

### Model Responsibilities

**Domain Models (PORO - Plain Old Ruby Objects):**
- Business logic
- Validations
- Calculations
- NO database access
- 100% unit testable

**Repositories:**
- CRUD operations via Sequel
- Hydrate DB rows → domain objects
- Dehydrate domain objects → DB rows
- NO business logic

**Services:**
- Multi-table transactions
- Orchestrate repositories
- Use domain objects for calculations
- Transaction boundaries

**RentDb:**
- Sequel connection management ONLY
- Thread-safe connection pool
- No domain logic (remove all calculation methods)

---

## Migration Strategy

### Phase 1: Foundation (30 min)

**1.1 Create Period Value Object**
```ruby
# lib/models/period.rb
class Period
  attr_reader :start_date, :end_date

  def initialize(start_date, end_date)
    @start_date = start_date
    @end_date = end_date
    validate!
  end

  def days
    (end_date - start_date).to_i + 1
  end

  def valid?
    start_date.is_a?(Date) &&
    end_date.is_a?(Date) &&
    start_date <= end_date
  end

  private

  def validate!
    raise ArgumentError, "Invalid period" unless valid?
  end
end
```

**1.2 Create Base Repository**
```ruby
# lib/repositories/base_repository.rb
class BaseRepository
  attr_reader :db, :dataset

  def initialize(db: RentDb.db)
    @db = db
    @dataset = db[table_name]
  end

  def table_name
    raise NotImplementedError
  end

  def transaction(&block)
    db.transaction(&block)
  end
end
```

---

### Phase 2: ElectricityBill (60 min)

**Priority:** Highest - has immediate automation needs

**2.1 Domain Model**
```ruby
# lib/models/electricity_bill.rb
class ElectricityBill
  attr_reader :id, :provider, :bill_date, :amount, :bill_period

  def initialize(id: nil, provider:, bill_date:, amount:, bill_period: nil)
    @id = id
    @provider = provider
    @bill_date = bill_date
    @amount = amount
    @bill_period = bill_period || self.class.calculate_bill_period(bill_date)
    validate!
  end

  # Class method: Calculate consumption period from due date
  def self.calculate_bill_period(due_date)
    # PRESERVED LOGIC from rent_db.rb:57-74
  end

  # Class method: Aggregate bills for a config period
  def self.aggregate_for_period(period, repository:)
    repository.find_by_period(period).sum(&:amount)
  end

  # Instance method: Sync to RentConfig
  def sync_to_rent_config(config_repo)
    total = self.class.aggregate_for_period(bill_period, repository: config_repo)
    # Update RentConfig via service
  end

  private

  def validate!
    raise ArgumentError, "Provider required" if provider.to_s.empty?
    raise ArgumentError, "Amount must be positive" unless amount.to_f > 0
    raise ArgumentError, "Bill date required" unless bill_date.is_a?(Date)
  end
end
```

**2.2 Repository**
```ruby
# lib/repositories/electricity_bill_repository.rb
class ElectricityBillRepository < BaseRepository
  def table_name
    :ElectricityBill
  end

  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  def find_by_period(period)
    dataset.where(billPeriod: period).map { |row| hydrate(row) }
  end

  def create(bill)
    id = dataset.insert(dehydrate(bill))
    bill.dup.tap { |b| b.instance_variable_set(:@id, id) }
  end

  def store_with_deduplication(provider:, amount:, due_date:)
    # PRESERVED LOGIC from rent_db.rb:277-310
  end

  private

  def hydrate(row)
    ElectricityBill.new(
      id: row[:id],
      provider: row[:provider],
      bill_date: row[:billDate],
      amount: row[:amount],
      bill_period: row[:billPeriod]
    )
  end

  def dehydrate(bill)
    {
      id: bill.id || Cuid.generate,
      provider: bill.provider,
      billDate: bill.bill_date,
      amount: bill.amount,
      billPeriod: bill.bill_period,
      createdAt: Time.now.utc,
      updatedAt: Time.now.utc
    }
  end
end
```

---

### Phase 3: RentConfig (60 min)

**Priority:** High - complex business logic

**3.1 Domain Model**
```ruby
# lib/models/rent_config.rb
class RentConfig
  # PRESERVED CONSTANTS from rent_db.rb:107-117
  PERIOD_SPECIFIC_KEYS = %w[el drift_rakning saldo_innan extra_in].freeze
  PERSISTENT_KEYS = %w[kallhyra bredband vattenavgift va larm].freeze

  DEFAULTS = {
    kallhyra: 24530,
    bredband: 400,
    vattenavgift: 375,
    va: 300,
    larm: 150
  }.freeze

  attr_reader :key, :value, :period

  def initialize(key:, value:, period:)
    @key = key
    @value = value
    @period = period
    validate!
  end

  def period_specific?
    PERIOD_SPECIFIC_KEYS.include?(key)
  end

  def persistent?
    PERSISTENT_KEYS.include?(key)
  end

  # Class method: Get config for a specific period
  def self.for_period(year:, month:, repository:)
    # PRESERVED LOGIC from rent_db.rb:152-184
    # Returns hash matching current API
  end

  private

  def validate!
    raise ArgumentError, "Key required" if key.to_s.empty?
    raise ArgumentError, "Period required" unless period.is_a?(Time)
  end
end
```

**3.2 Repository**
```ruby
# lib/repositories/rent_config_repository.rb
class RentConfigRepository < BaseRepository
  def table_name
    :RentConfig
  end

  def find_by_key_and_period(key, period)
    row = dataset.where(key: key, period: period).first
    row && hydrate(row)
  end

  def find_latest_for_key(key, before_period)
    row = dataset
      .where(key: key)
      .where { period <= before_period }
      .order(Sequel.desc(:period))
      .first
    row && hydrate(row)
  end

  def create(config)
    # PRESERVED LOGIC from rent_db.rb:207-220
  end

  private

  def hydrate(row)
    RentConfig.new(
      key: row[:key],
      value: row[:value],
      period: row[:period]
    )
  end

  def dehydrate(config)
    {
      id: Cuid.generate,
      key: config.key,
      value: config.value,
      period: config.period,
      createdAt: Time.now.utc,
      updatedAt: Time.now.utc
    }
  end
end
```

---

### Phase 4: Tenant (45 min)

**Priority:** Medium - scattered logic needs consolidation

**4.1 Domain Model**
```ruby
# lib/models/tenant.rb
class Tenant
  attr_reader :id, :name, :email, :room_adjustment, :start_date, :departure_date

  def initialize(id: nil, name:, email:, room_adjustment: nil, start_date: nil, departure_date: nil)
    @id = id
    @name = name
    @email = email
    @room_adjustment = room_adjustment
    @start_date = start_date
    @departure_date = departure_date
    validate!
  end

  # Calculate days stayed in a given period
  def days_stayed_in_period(period_start, period_end)
    return 0 if departure_date && departure_date < period_start
    return 0 if start_date && start_date > period_end

    actual_start = [start_date || period_start, period_start].max
    actual_end = [departure_date || period_end, period_end].min

    (actual_end - actual_start).to_i + 1
  end

  # Calculate prorated room adjustment for a period
  def prorated_adjustment(total_days_in_month, days_stayed)
    return 0 unless room_adjustment
    room_adjustment * (days_stayed.to_f / total_days_in_month)
  end

  def active_on?(date)
    (start_date.nil? || start_date <= date) &&
    (departure_date.nil? || departure_date >= date)
  end

  private

  def validate!
    raise ArgumentError, "Name required" if name.to_s.empty?
    raise ArgumentError, "Email required" if email.to_s.empty?
  end
end
```

**4.2 Repository**
```ruby
# lib/repositories/tenant_repository.rb
class TenantRepository < BaseRepository
  def table_name
    :Tenant
  end

  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  def find_by_email(email)
    row = dataset.where(email: email).first
    row && hydrate(row)
  end

  def find_active_on(date)
    dataset
      .where { (startDate <= date) | (startDate =~ nil) }
      .where { (departureDate >= date) | (departureDate =~ nil) }
      .map { |row| hydrate(row) }
  end

  def all
    dataset.order(:name).map { |row| hydrate(row) }
  end

  private

  def hydrate(row)
    Tenant.new(
      id: row[:id],
      name: row[:name],
      email: row[:email],
      room_adjustment: row[:roomAdjustment],
      start_date: row[:startDate],
      departure_date: row[:departureDate]
    )
  end

  def dehydrate(tenant)
    {
      id: tenant.id || Cuid.generate,
      name: tenant.name,
      email: tenant.email,
      roomAdjustment: tenant.room_adjustment,
      startDate: tenant.start_date,
      departureDate: tenant.departure_date,
      createdAt: Time.now.utc,
      updatedAt: Time.now.utc
    }
  end
end
```

---

### Phase 5: RentLedger (30 min)

**Priority:** Low - mostly persistence, minimal logic

**5.1 Domain Model**
```ruby
# lib/models/rent_ledger.rb
class RentLedger
  attr_reader :id, :tenant_id, :period, :amount_due, :amount_paid,
              :payment_date, :days_stayed, :room_adjustment,
              :base_monthly_rent, :calculation_title, :calculation_date

  def initialize(id: nil, tenant_id:, period:, amount_due:, amount_paid: 0,
                 payment_date: nil, days_stayed: nil, room_adjustment: nil,
                 base_monthly_rent: nil, calculation_title: nil, calculation_date: nil)
    @id = id
    @tenant_id = tenant_id
    @period = period
    @amount_due = amount_due
    @amount_paid = amount_paid
    @payment_date = payment_date
    @days_stayed = days_stayed
    @room_adjustment = room_adjustment
    @base_monthly_rent = base_monthly_rent
    @calculation_title = calculation_title
    @calculation_date = calculation_date
    validate!
  end

  def paid?
    amount_paid >= amount_due
  end

  def outstanding
    amount_due - amount_paid
  end

  private

  def validate!
    raise ArgumentError, "Tenant ID required" if tenant_id.to_s.empty?
    raise ArgumentError, "Period required" unless period.is_a?(Time)
    raise ArgumentError, "Amount due required" unless amount_due.is_a?(Numeric)
  end
end
```

**5.2 Repository**
```ruby
# lib/repositories/rent_ledger_repository.rb
class RentLedgerRepository < BaseRepository
  def table_name
    :RentLedger
  end

  def find_by_tenant_and_period(tenant_id, period)
    row = dataset.where(tenantId: tenant_id, period: period).first
    row && hydrate(row)
  end

  def find_by_period(period)
    dataset.where(period: period).map { |row| hydrate(row) }
  end

  def create(ledger_entry)
    dataset.insert(dehydrate(ledger_entry))
    ledger_entry
  end

  private

  def hydrate(row)
    RentLedger.new(
      id: row[:id],
      tenant_id: row[:tenantId],
      period: row[:period],
      amount_due: row[:amountDue],
      amount_paid: row[:amountPaid],
      payment_date: row[:paymentDate],
      days_stayed: row[:daysStayed],
      room_adjustment: row[:roomAdjustment],
      base_monthly_rent: row[:baseMonthlyRent],
      calculation_title: row[:calculationTitle],
      calculation_date: row[:calculationDate]
    )
  end

  def dehydrate(ledger_entry)
    {
      id: ledger_entry.id || Cuid.generate,
      tenantId: ledger_entry.tenant_id,
      period: ledger_entry.period,
      amountDue: ledger_entry.amount_due,
      amountPaid: ledger_entry.amount_paid,
      paymentDate: ledger_entry.payment_date,
      daysStayed: ledger_entry.days_stayed,
      roomAdjustment: ledger_entry.room_adjustment,
      baseMonthlyRent: ledger_entry.base_monthly_rent,
      calculationTitle: ledger_entry.calculation_title,
      calculationDate: ledger_entry.calculation_date,
      createdAt: Time.now.utc
    }
  end
end
```

---

### Phase 6: Service Layer (45 min)

**6.1 Apply Electricity Bill Service**
```ruby
# lib/services/apply_electricity_bill.rb
class ApplyElectricityBill
  def self.call(bill:, electricity_repo:, config_repo:)
    electricity_repo.transaction do
      # Store bill (with deduplication)
      stored_bill = electricity_repo.create(bill)

      # Aggregate all bills for this period
      total = ElectricityBill.aggregate_for_period(
        bill.bill_period,
        repository: electricity_repo
      )

      # Update RentConfig with aggregated total
      config = RentConfig.new(
        key: 'el',
        value: total,
        period: bill.bill_period
      )
      config_repo.create(config)

      stored_bill
    end
  end
end
```

**6.2 Calculate Rent Service**
```ruby
# lib/services/calculate_rent.rb
class CalculateRent
  def self.call(year:, month:, repositories:)
    # Fetch config
    config = RentConfig.for_period(
      year: year,
      month: month,
      repository: repositories[:rent_config]
    )

    # Fetch active tenants
    period_start = Date.new(year, month, 1)
    tenants = repositories[:tenant].find_active_on(period_start)

    # Use RentCalculator (PRESERVED - no changes)
    # ... existing rent calculation logic ...

    # Store in ledger
    # ... transaction to create RentLedger entries ...
  end
end
```

---

### Phase 7: Update RentDb (30 min)

**Strip down to CONNECTION ONLY:**

```ruby
# lib/rent_db.rb (after migration)
require 'sequel'
require 'cuid'
require 'date'

# RentDb provides thread-safe database connection for Kimonokittens.
# All domain logic lives in models. This class is CONNECTION ONLY.
class RentDb
  # Thread-safe connection with automatic pooling
  def self.db
    @db ||= begin
      Sequel.connect(
        ENV.fetch('DATABASE_URL'),
        max_connections: 10,
        pool_timeout: 5,
        test: true,
        validate: true
      )
    end
  end

  # Singleton compatibility for existing code
  def self.instance
    @instance ||= new
  end

  # Deprecated: Use repositories instead
  # Kept temporarily for backward compatibility
  def get_tenants
    warn "DEPRECATED: Use TenantRepository#all instead"
    TenantRepository.new.all.map { |t|
      { 'id' => t.id, 'name' => t.name, 'email' => t.email }
    }
  end

  # TODO: Remove all domain logic methods after migration
end
```

---

### Phase 8: Update Handlers (60 min)

**Example: rent_calculator_handler.rb**

**Before:**
```ruby
db = RentDb.instance
config = db.get_rent_config(year: year, month: month)
```

**After:**
```ruby
config_repo = RentConfigRepository.new
config = RentConfig.for_period(year: year, month: month, repository: config_repo)
```

**Preserve API contract** - handlers return same JSON structure.

---

### Phase 9: Electricity Aggregation (30 min)

**Add to vattenfall.rb:**

```ruby
# After storing bills
unless ENV['SKIP_DB']
  puts "\n💾 Storing invoices in database..."

  electricity_repo = ElectricityBillRepository.new
  config_repo = RentConfigRepository.new

  results[:invoices].each do |invoice|
    bill = ElectricityBill.new(
      provider: invoice['provider'],
      bill_date: Date.parse(invoice['due_date']),
      amount: invoice['amount']
    )

    # Store + sync to RentConfig
    ApplyElectricityBill.call(
      bill: bill,
      electricity_repo: electricity_repo,
      config_repo: config_repo
    )
  end
end
```

---

## Testing Strategy

### Unit Tests (Domain Models)

**No database required:**

```ruby
# spec/models/electricity_bill_spec.rb
RSpec.describe ElectricityBill do
  describe '.calculate_bill_period' do
    it 'handles end-of-month due dates' do
      period = ElectricityBill.calculate_bill_period(Date.new(2025, 9, 30))
      expect(period).to eq(Date.new(2025, 8, 1))
    end

    it 'handles start-of-month due dates' do
      period = ElectricityBill.calculate_bill_period(Date.new(2025, 11, 3))
      expect(period).to eq(Date.new(2025, 9, 1))
    end
  end
end
```

### Integration Tests (Repositories)

**Use test database:**

```ruby
# spec/repositories/electricity_bill_repository_spec.rb
RSpec.describe ElectricityBillRepository do
  let(:repo) { described_class.new }

  it 'stores and retrieves bills' do
    bill = ElectricityBill.new(
      provider: 'Vattenfall',
      bill_date: Date.new(2025, 11, 3),
      amount: 1685.69
    )

    stored = repo.create(bill)
    expect(stored.id).not_to be_nil

    retrieved = repo.find_by_id(stored.id)
    expect(retrieved.amount).to eq(1685.69)
  end
end
```

### Preservation Tests (Rent Calculation)

**Verify existing behavior unchanged:**

```ruby
# spec/integration/rent_calculation_preservation_spec.rb
RSpec.describe 'Rent Calculation Preservation' do
  it 'produces identical results to pre-migration logic' do
    # Use Oct 2025 known values
    config_repo = RentConfigRepository.new

    # Call NEW code
    config = RentConfig.for_period(year: 2025, month: 10, repository: config_repo)

    # Compare to KNOWN GOOD values from current system
    expect(config['el']).to eq(2424)
    expect(config['kallhyra']).to eq(24530)
    # ... all keys ...
  end
end
```

---

## Risk Mitigation

### Critical Preservation Points

**1. Rent Calculation Logic**
- **DO NOT TOUCH** rent.rb core calculation methods
- Only update data access (use repositories)
- Run full test suite after every change
- Compare outputs to known-good historical values

**2. API Contracts**
- Handlers must return IDENTICAL JSON structures
- Frontend expects specific field names
- WebSocket data format unchanged

**3. Database Schema**
- NO schema changes during migration
- Models map to EXISTING columns
- Prisma remains source of truth

### Rollback Plan

**If something breaks:**

1. **Git revert** entire migration (atomic commit)
2. **Keep RentDb** as fallback until confident
3. **Feature flag** new models (ENV['USE_NEW_MODELS'])
4. **Gradual deployment** (test mode first)

---

## Production Deployment

### Cron Setup (Dell Kiosk Only)

**Create deployment script:**

```bash
# deployment/scripts/setup_electricity_cron.sh
#!/bin/bash
# Run as kimonokittens user on Dell kiosk

CRON_ENTRY="0 3 * * * cd /home/kimonokittens/Projects/kimonokittens && /home/kimonokittens/.rbenv/shims/ruby vattenfall.rb >> logs/electricity_fetcher.log 2>&1"

# Add to crontab if not exists
(crontab -l 2>/dev/null | grep -q "vattenfall.rb") || (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
```

**NOT deployed on Mac dev environment** - only production.

---

## Success Criteria

**Migration Complete When:**

- ✅ All 4 models created with domain logic
- ✅ All 4 repositories created
- ✅ Service layer handles transactions
- ✅ RentDb stripped to connection only
- ✅ All handlers updated to use new models
- ✅ All tests passing (existing + new)
- ✅ Rent calculation outputs identical to pre-migration
- ✅ Electricity aggregation automated
- ✅ Documentation complete (MODEL_ARCHITECTURE.md)
- ✅ Production cron configured

**Validation:**

```bash
# Run full test suite
bundle exec rspec

# Verify rent calculation unchanged
ruby -r ./lib/models/rent_config.rb -e "..."

# Check electricity aggregation
ruby vattenfall.rb  # Should auto-update RentConfig
```

---

## Documentation Deliverables

1. **MODEL_MIGRATION_PLAN.md** (this file)
2. **MODEL_ARCHITECTURE.md** (new - LLM-friendly API guide)
3. **ELECTRICITY_AUTOMATION_COMPLETION_SUMMARY.md** (updated - aggregation section)
4. **CLAUDE.md** (updated - new patterns, testing)

---

## Timeline

**Total estimated: 4-6 hours**

- Phase 1: Foundation (30 min)
- Phase 2: ElectricityBill (60 min)
- Phase 3: RentConfig (60 min)
- Phase 4: Tenant (45 min)
- Phase 5: RentLedger (30 min)
- Phase 6: Services (45 min)
- Phase 7: RentDb cleanup (30 min)
- Phase 8: Handlers (60 min)
- Phase 9: Aggregation (30 min)
- Testing & validation (60 min)

**Single session execution recommended** - maintain full context.

---

**Ready to execute!** 🚀
