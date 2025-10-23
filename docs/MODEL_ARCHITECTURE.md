# Model Architecture Guide for LLM Automation

**Date:** October 23, 2025
**Status:** ✅ PRODUCTION READY
**Audience:** AI assistants, future developers, automation systems

---

## Executive Summary

This document provides a comprehensive guide to the Kimonokittens rent management domain model architecture. The system uses a **clean architecture pattern** with domain models (business logic), repositories (persistence), and services (transactions).

**Key Principles:**
- **Domain models** contain all business logic (no database access)
- **Repositories** handle persistence only (no business rules)
- **Services** orchestrate multi-table transactions
- **Persistence module** provides centralized repository access

---

## Quick Reference: Common Tasks

### Get Current Month's Rent Configuration
```ruby
require_relative 'lib/persistence'

# Get configuration for October 2025
config = RentConfig.for_period(
  year: 2025,
  month: 10,
  repository: Persistence.rent_configs
)

# Returns hash with all configuration keys:
# { 'kallhyra' => 24530, 'el' => 2424, 'bredband' => 400, ... }
```

### Store Electricity Invoice (with automatic aggregation)
```ruby
require_relative 'lib/services/apply_electricity_bill'

# Store invoice and auto-update RentConfig
result = ApplyElectricityBill.call(
  provider: 'Vattenfall',
  amount: 1685.69,
  due_date: Date.new(2025, 11, 3)
)

# Returns:
# {
#   inserted: true,              # false if duplicate
#   bill: #<ElectricityBill>,    # domain object
#   bill_period: Date(...),      # consumption period
#   aggregated_total: 2424,      # sum for that period
#   config_updated: :created     # or :updated
# }
```

### Find Active Tenants on a Date
```ruby
require_relative 'lib/persistence'

# Get all tenants active on October 1, 2025
tenants = Persistence.tenants.find_active_on(Date.new(2025, 10, 1))

# Returns array of Tenant domain objects
tenants.each do |tenant|
  puts "#{tenant.name}: #{tenant.email}"
  puts "  Days stayed: #{tenant.days_stayed_in_period(start_date, end_date)}"
  puts "  Room adjustment: #{tenant.room_adjustment}" if tenant.room_adjustment
end
```

### Get Rent History for a Period
```ruby
require_relative 'lib/persistence'

# Get all rent ledger entries for October 2025
history = Persistence.rent_ledger.get_rent_history(year: 2025, month: 10)

# Returns array of RentLedger domain objects
history.each do |entry|
  tenant = Persistence.tenants.find_by_id(entry.tenant_id)
  puts "#{tenant.name}: #{entry.amount_due} kr (#{entry.payment_status})"
end
```

---

## Architecture Overview

### Layer Responsibilities

```
┌─────────────────────────────────────────────────┐
│  HTTP Handlers (handlers/*.rb)                  │
│  - Rack endpoint definitions                    │
│  - Request/response formatting                  │
│  - Call services/repositories                   │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  Service Layer (lib/services/*.rb)              │
│  - Multi-table transactions                     │
│  - Orchestrate repositories                     │
│  - Business workflow coordination               │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  Domain Models (lib/models/*.rb)                │
│  - Business logic                               │
│  - Validations                                  │
│  - Calculations                                 │
│  - NO database access                           │
└─────────────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  Repositories (lib/repositories/*.rb)           │
│  - CRUD operations via Sequel                   │
│  - Hydrate (DB row → domain object)             │
│  - Dehydrate (domain object → DB row)           │
│  - NO business logic                            │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  Persistence Module (lib/persistence.rb)        │
│  - Singleton repository instances               │
│  - Centralized access point                     │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  Database (PostgreSQL via Sequel)               │
│  - Schema defined by Prisma                     │
│  - Connection managed by RentDb                 │
└─────────────────────────────────────────────────┘
```

### Directory Structure

```
lib/
├── models/                      # Domain models (business logic)
│   ├── period.rb                # Value object for date ranges
│   ├── electricity_bill.rb      # Electricity invoice domain
│   ├── rent_config.rb           # Configuration domain
│   ├── tenant.rb                # Tenant/roommate domain
│   └── rent_ledger.rb           # Rent payment audit trail
│
├── repositories/                # Persistence layer
│   ├── base_repository.rb       # Common CRUD operations
│   ├── electricity_bill_repository.rb
│   ├── rent_config_repository.rb
│   ├── tenant_repository.rb
│   └── rent_ledger_repository.rb
│
├── services/                    # Transaction orchestration
│   └── apply_electricity_bill.rb
│
├── persistence.rb               # Centralized repository access
└── rent_db.rb                   # Database connection (thin wrapper)
```

---

## Domain Models

### 1. Period (Value Object)

**Purpose:** Immutable time range representation used across models.

**Usage:**
```ruby
period = Period.new(
  Date.new(2025, 10, 1),  # start_date
  Date.new(2025, 10, 31)  # end_date
)

period.days           # => 31
period.months         # => 1
period.overlaps?(other_period)  # => true/false
```

**Methods:**
- `days` - Total days in period (inclusive)
- `months` - Total months in period
- `overlaps?(other)` - Check if periods overlap
- `contains?(date)` - Check if date within period

---

### 2. ElectricityBill

**Purpose:** Represents an electricity invoice with billing period calculation.

**Business Rules:**
- **Billing period**: Calculated from due date (CRITICAL timing logic)
  - Due day 25-31: Bill arrived same month → consumption = month - 1
  - Due day 1-24: Bill arrived previous month → consumption = month - 2
- **Deduplication**: (provider, bill_date, amount) composite key
- **Aggregation**: Sum all bills for a consumption period

**Domain Logic:**
```ruby
# Class methods (used for calculations):
ElectricityBill.calculate_bill_period(due_date)
  # Input: due_date (Date)
  # Output: consumption period (Date, month start)
  # Example: Nov 3 → Sept 1 (start-of-month due date pattern)

ElectricityBill.aggregate_for_period(period, repository:)
  # Input: period (Date), repository (ElectricityBillRepository)
  # Output: total amount (Float)
  # Purpose: Sum all bills for that consumption period
```

**Instance Usage:**
```ruby
bill = ElectricityBill.new(
  id: nil,                          # Auto-generated CUID
  provider: 'Vattenfall',
  bill_date: Date.new(2025, 11, 3), # Due date
  amount: 1685.69,
  bill_period: nil                  # Auto-calculated from bill_date
)

bill.provider       # => "Vattenfall"
bill.bill_period    # => Date.new(2025, 9, 1)  (calculated)
bill.amount         # => 1685.69
```

**Serialization:**
```ruby
bill.to_h
# => { provider: "Vattenfall", billDate: Date(...), amount: 1685.69, billPeriod: Date(...) }
```

---

### 3. RentConfig

**Purpose:** Configuration values with key classification and carry-forward logic.

**Business Rules:**
- **Period-Specific Keys**: Exact period match only (el, drift_rakning, saldo_innan, extra_in)
- **Persistent Keys**: Carry forward from most recent value (kallhyra, bredband, vattenavgift, va, larm)
- **Defaults**: Fallback values when no config exists

**Key Classification:**
```ruby
RentConfig::PERIOD_SPECIFIC_KEYS  # => ['el', 'drift_rakning', 'saldo_innan', 'extra_in']
RentConfig::PERSISTENT_KEYS       # => ['kallhyra', 'bredband', 'vattenavgift', 'va', 'larm']

RentConfig::DEFAULTS
# => {
#   kallhyra: 24530,
#   bredband: 400,
#   vattenavgift: 375,
#   va: 300,
#   larm: 150
# }
```

**Domain Logic:**
```ruby
# Class method (primary API):
config = RentConfig.for_period(
  year: 2025,
  month: 10,
  repository: Persistence.rent_configs
)

# Returns hash matching historical API:
# {
#   'kallhyra' => 24530,      # Persistent key (carry-forward)
#   'el' => 2424,             # Period-specific (exact match)
#   'bredband' => 400,        # Persistent key
#   'vattenavgift' => 375,    # Default (no config exists)
#   ...
# }
```

**Instance Usage:**
```ruby
config = RentConfig.new(
  id: nil,                         # Auto-generated CUID
  key: 'el',
  value: '2424',                   # Always stored as string
  period: Time.utc(2025, 9, 1),    # Month start UTC
  created_at: nil,
  updated_at: nil
)

config.period_specific?  # => true (el is period-specific)
config.persistent?       # => false
```

**CRITICAL TIMING:**
- **Config period** = month when bills arrived
- **Rent period** = config month + 1
- **Consumption period** = config month - 1
- Example: September config → October rent → August consumption

---

### 4. Tenant

**Purpose:** Represents a household member with move-in/out logic and room adjustments.

**Business Rules:**
- **Days stayed**: Handles partial months, move-in/out dates
- **Room adjustments**: Prorated by days stayed, redistributed among tenants
- **Active status**: Determined by start_date and departure_date

**Domain Logic:**
```ruby
tenant = Tenant.new(
  id: nil,
  name: 'Adam',
  email: 'adam@example.com',
  facebook_id: nil,
  avatar_url: nil,
  room_adjustment: -1400,          # Negative = discount
  start_date: Date.new(2025, 3, 16),
  departure_date: nil,             # Still active
  created_at: nil,
  updated_at: nil
)

# Calculate days stayed in October 2025:
days = tenant.days_stayed_in_period(
  Date.new(2025, 10, 1),
  Date.new(2025, 10, 31)
)
# => 31 (full month)

# Calculate prorated room adjustment:
adjustment = tenant.prorated_adjustment(
  31,    # total days in month
  16     # days stayed (half month)
)
# => -700.0 (half of -1400 discount)

# Check if active on a date:
tenant.active_on?(Date.new(2025, 10, 15))  # => true
tenant.active?                             # => true (no departure_date)
```

**Serialization:**
```ruby
tenant.to_h
# => {
#   id: "...",
#   name: "Adam",
#   email: "adam@example.com",
#   facebookId: nil,
#   avatarUrl: nil,
#   roomAdjustment: -1400,
#   startDate: Date(...),
#   departureDate: nil,
#   createdAt: Time(...),
#   updatedAt: Time(...)
# }
```

---

### 5. RentLedger

**Purpose:** Immutable audit trail for rent calculations and payments.

**Business Rules:**
- **Immutable**: Once created, never modified (financial best practice)
- **Complete context**: Preserves calculation details (days_stayed, room_adjustment, etc.)
- **Payment tracking**: amount_due vs amount_paid

**Domain Logic:**
```ruby
entry = RentLedger.new(
  id: nil,
  tenant_id: 'cuid123',
  period: Time.utc(2025, 10, 1),
  amount_due: 7045.0,
  amount_paid: 0,
  payment_date: nil,
  days_stayed: 31.0,
  room_adjustment: 0,
  base_monthly_rent: 24530,
  calculation_title: 'Oktober 2025',
  calculation_date: Time.now.utc,
  created_at: nil
)

entry.paid?              # => false
entry.partially_paid?    # => false
entry.outstanding        # => 7045.0
entry.payment_status     # => "unpaid"
entry.period_swedish     # => "Oktober 2025"
```

**Serialization:**
```ruby
entry.to_h
# => {
#   id: "...",
#   tenantId: "cuid123",
#   period: Time(...),
#   amountDue: 7045.0,
#   amountPaid: 0,
#   paymentDate: nil,
#   daysStayed: 31.0,
#   roomAdjustment: 0,
#   baseMonthlyRent: 24530,
#   calculationTitle: "Oktober 2025",
#   calculationDate: Time(...),
#   createdAt: Time(...)
# }
```

---

## Repositories

### Persistence Module Pattern

**Primary interface** for accessing repositories:

```ruby
require_relative 'lib/persistence'

# Get singleton repository instances:
Persistence.tenants           # => TenantRepository
Persistence.rent_configs      # => RentConfigRepository
Persistence.rent_ledger       # => RentLedgerRepository
Persistence.electricity_bills # => ElectricityBillRepository

# Reset for tests (swaps connection context):
Persistence.reset!
```

### Base Repository

**Common operations** inherited by all repositories:

```ruby
class BaseRepository
  attr_reader :db, :dataset

  def initialize(db: nil)
    @db = db || default_db
    @dataset = @db[table_name]
  end

  def transaction(&block)
    db.transaction(&block)
  end

  # Subclasses must implement:
  # - table_name (returns Symbol)
  # - hydrate(row) (DB row → domain object)
  # - dehydrate(object) (domain object → DB hash)
end
```

### TenantRepository

**Query methods:**
```ruby
repo = Persistence.tenants

# Find by ID:
tenant = repo.find_by_id('cuid123')

# Find by email:
tenant = repo.find_by_email('adam@example.com')

# Find all active on a date:
active = repo.find_active_on(Date.new(2025, 10, 1))

# Get all tenants:
all = repo.all

# Create:
tenant = Tenant.new(name: 'Adam', email: 'adam@example.com')
created = repo.create(tenant)
```

### RentConfigRepository

**Query methods:**
```ruby
repo = Persistence.rent_configs

# Find by exact key + period match (period-specific keys):
config = repo.find_by_key_and_period('el', Time.utc(2025, 9, 1))

# Find most recent value for key (persistent keys):
config = repo.find_latest_for_key('kallhyra', Time.utc(2025, 10, 1))

# Find all configs for a period:
configs = repo.find_by_period(Time.utc(2025, 9, 1))

# Get all distinct keys:
keys = repo.all_keys  # => ['el', 'kallhyra', 'bredband', ...]

# Get all configs for a key (ordered by period):
history = repo.all_for_key('el')

# Create:
config = RentConfig.new(key: 'el', value: '2424', period: Time.utc(2025, 9, 1))
created = repo.create(config)

# Upsert (create or update):
updated = repo.upsert(
  key: 'el',
  value: 2500,
  period: Time.utc(2025, 9, 1)
)

# Update:
config = repo.find_by_key_and_period('el', Time.utc(2025, 9, 1))
updated_config = RentConfig.new(
  id: config.id,
  key: 'el',
  value: '2600',
  period: config.period
)
repo.update(updated_config)

# Delete:
repo.delete('cuid123')
```

### ElectricityBillRepository

**Query methods:**
```ruby
repo = Persistence.electricity_bills

# Find by ID:
bill = repo.find_by_id('cuid123')

# Find all bills for a period:
bills = repo.find_by_period(Date.new(2025, 9, 1))

# Store with deduplication (primary method):
result = repo.store_with_deduplication(
  provider: 'Vattenfall',
  amount: 1685.69,
  due_date: Date.new(2025, 11, 3)
)

# Returns:
# {
#   inserted: true,              # false if duplicate
#   bill: #<ElectricityBill>,
#   bill_period: Date.new(2025, 9, 1),
#   reason: nil                  # or 'duplicate'
# }

# Create (direct):
bill = ElectricityBill.new(...)
created = repo.create(bill)
```

### RentLedgerRepository

**Query methods:**
```ruby
repo = Persistence.rent_ledger

# Find by tenant + period:
entry = repo.find_by_tenant_and_period('tenant_id', Time.utc(2025, 10, 1))

# Find all entries for a period:
entries = repo.find_by_period(Time.utc(2025, 10, 1))

# Get rent history for a month (legacy API):
history = repo.get_rent_history(year: 2025, month: 10)

# Create:
entry = RentLedger.new(...)
created = repo.create(entry)
```

---

## Service Layer

### ApplyElectricityBill

**Purpose:** Atomic transaction to store electricity bill and update RentConfig.

**Workflow:**
1. Store individual bill (with deduplication)
2. Aggregate all bills for that billing period
3. Update RentConfig with aggregated total
4. Notify WebSocket clients

**Usage:**
```ruby
require_relative 'lib/services/apply_electricity_bill'

result = ApplyElectricityBill.call(
  provider: 'Vattenfall',
  amount: 1685.69,
  due_date: Date.new(2025, 11, 3),
  electricity_repo: nil,  # Optional (defaults to Persistence)
  config_repo: nil        # Optional (defaults to Persistence)
)

# Returns:
# {
#   inserted: true,              # false if duplicate
#   bill: #<ElectricityBill>,
#   bill_period: Date.new(2025, 9, 1),
#   aggregated_total: 2424,      # sum of all bills for Sept
#   config_updated: :created,    # or :updated
#   reason: nil                  # or 'duplicate'
# }
```

**Transaction safety:**
- Entire operation wrapped in database transaction
- Rollback on any failure
- WebSocket notification is non-critical (logged but doesn't fail transaction)

---

## API Endpoints

### GET /api/rent/friendly_message

**Purpose:** Get human-readable rent message for current/specified month.

**Handler:** `handlers/rent_calculator_handler.rb`

**Data flow:**
```
1. Parse query params (year, month, testMode)
2. RentConfig.for_period → fetch configuration
3. Persistence.tenants.find_active_on → fetch active tenants
4. RentCalculator.calculate → compute rent (PRESERVED LOGIC)
5. Format message with heating cost line
6. Return JSON
```

**Example request:**
```bash
curl 'http://localhost:3001/api/rent/friendly_message?year=2025&month=10'
```

**Example response:**
```json
{
  "message": "Hyran för oktober 2025 ska betalas innan 27 sep och är 7 045 kr/person.",
  "total_rent": 28179,
  "per_person": 7045,
  "num_roommates": 4,
  "year": 2025,
  "month": 10,
  "data_source": "Baserad på aktuella elräkningar",
  "heating_cost_line": "2 °C varmare skulle kosta 143 kr/mån (36 kr/person); 2 °C kallare skulle spara 130 kr/mån (33 kr/person)"
}
```

### POST /api/electricity/apply_bill (planned)

**Purpose:** Store electricity bill and trigger aggregation.

**Data flow:**
```
1. Parse request body (provider, amount, due_date)
2. ApplyElectricityBill.call → store + aggregate + update config
3. Broadcast WebSocket update
4. Return result
```

**Example request:**
```bash
curl -X POST http://localhost:3001/api/electricity/apply_bill \
  -H 'Content-Type: application/json' \
  -d '{
    "provider": "Vattenfall",
    "amount": 1685.69,
    "due_date": "2025-11-03"
  }'
```

**Example response:**
```json
{
  "inserted": true,
  "bill_period": "2025-09-01",
  "aggregated_total": 2424,
  "config_updated": "created"
}
```

---

## WebSocket Data Flow

### Rent Data Updates

**Publisher:** `lib/services/apply_electricity_bill.rb`

**Broadcast:**
```ruby
$pubsub&.publish("rent_data_updated")
```

**Subscriber:** `dashboard/src/context/DataContext.tsx`

**Effect:** Frontend refetches `/api/rent/friendly_message` and updates UI.

---

## Testing Patterns

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

  describe '.aggregate_for_period' do
    it 'sums bills for a period' do
      repo = instance_double(ElectricityBillRepository)
      bills = [
        ElectricityBill.new(provider: 'A', bill_date: Date.new(2025, 11, 3), amount: 1000),
        ElectricityBill.new(provider: 'B', bill_date: Date.new(2025, 11, 5), amount: 1424)
      ]
      allow(repo).to receive(:find_by_period).and_return(bills)

      total = ElectricityBill.aggregate_for_period(Date.new(2025, 9, 1), repository: repo)
      expect(total).to eq(2424)
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

  before do
    # Ensure test database is used
    ENV['DATABASE_URL'] = 'postgresql://localhost/kimonokittens_test'
  end

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
    expect(retrieved.bill_period).to eq(Date.new(2025, 9, 1))
  end

  it 'deduplicates bills' do
    result1 = repo.store_with_deduplication(
      provider: 'Vattenfall',
      amount: 1685.69,
      due_date: Date.new(2025, 11, 3)
    )
    expect(result1[:inserted]).to eq(true)

    result2 = repo.store_with_deduplication(
      provider: 'Vattenfall',
      amount: 1685.69,
      due_date: Date.new(2025, 11, 3)
    )
    expect(result2[:inserted]).to eq(false)
    expect(result2[:reason]).to eq('duplicate')
  end
end
```

### Service Tests

**Transaction behavior:**

```ruby
# spec/services/apply_electricity_bill_spec.rb
RSpec.describe ApplyElectricityBill do
  it 'stores bill, aggregates, and updates config in transaction' do
    result = ApplyElectricityBill.call(
      provider: 'Vattenfall',
      amount: 1685.69,
      due_date: Date.new(2025, 11, 3)
    )

    expect(result[:inserted]).to eq(true)
    expect(result[:bill_period]).to eq(Date.new(2025, 9, 1))
    expect(result[:aggregated_total]).to be > 0
    expect(result[:config_updated]).to be_in([:created, :updated])

    # Verify RentConfig was updated:
    config = Persistence.rent_configs.find_by_key_and_period('el', Time.utc(2025, 9, 1))
    expect(config.value.to_i).to eq(result[:aggregated_total])
  end
end
```

---

## Common Patterns

### Pattern 1: Add New Electricity Invoice

```ruby
# From scraper (vattenfall.rb):
require_relative 'lib/services/apply_electricity_bill'

result = ApplyElectricityBill.call(
  provider: 'Vattenfall',
  amount: invoice_amount,
  due_date: Date.parse(invoice_due_date)
)

if result[:inserted]
  puts "✓ Inserted: #{result[:bill_period]} → #{result[:aggregated_total]} kr"
else
  puts "⊘ Skipped (duplicate)"
end
```

### Pattern 2: Get Current Month Configuration

```ruby
# From handler:
require_relative 'lib/models/rent_config'
require_relative 'lib/persistence'

config = RentConfig.for_period(
  year: Time.now.year,
  month: Time.now.month,
  repository: Persistence.rent_configs
)

# Use config hash:
base_rent = config['kallhyra']
electricity = config['el']
internet = config['bredband']
```

### Pattern 3: Calculate Rent for Active Tenants

```ruby
# From rent calculation handler:
require_relative 'lib/persistence'

# Get configuration:
config = RentConfig.for_period(year: year, month: month, repository: Persistence.rent_configs)

# Get active tenants:
period_start = Date.new(year, month, 1)
tenants = Persistence.tenants.find_active_on(period_start)

# Calculate each tenant's rent:
tenants.each do |tenant|
  days = tenant.days_stayed_in_period(period_start, period_end)
  adjustment = tenant.prorated_adjustment(total_days, days)
  # ... rent calculation logic ...
end
```

### Pattern 4: Create Rent Ledger Entry

```ruby
# After rent calculation:
require_relative 'lib/persistence'

ledger = RentLedger.new(
  tenant_id: tenant.id,
  period: Time.utc(year, month, 1),
  amount_due: calculated_rent,
  amount_paid: 0,
  days_stayed: days_stayed,
  room_adjustment: adjustment,
  base_monthly_rent: base_rent,
  calculation_title: "#{swedish_month} #{year}",
  calculation_date: Time.now.utc
)

Persistence.rent_ledger.create(ledger)
```

---

## Migration Notes

### From Legacy RentDb to New Architecture

**Before (Oct 21, 2025):**
```ruby
db = RentDb.instance
config = db.get_rent_config(year: 2025, month: 10)
tenants = db.get_tenants
db.store_electricity_invoice(...)
```

**After (Oct 23, 2025):**
```ruby
require_relative 'lib/persistence'
require_relative 'lib/models/rent_config'

config = RentConfig.for_period(year: 2025, month: 10, repository: Persistence.rent_configs)
tenants = Persistence.tenants.all
ApplyElectricityBill.call(...)
```

### RentDb Current State

**Now a thin wrapper** for backward compatibility:

```ruby
class RentDb
  # Connection management:
  def self.db
    @db ||= Sequel.connect(ENV.fetch('DATABASE_URL'), ...)
  end

  # Deprecated methods (kept for backward compatibility):
  def get_tenants
    warn "DEPRECATED: Use Persistence.tenants.all instead"
    Persistence.tenants.all.map(&:to_h)
  end

  # Use Persistence module for all new code!
end
```

---

## Future Enhancements

### Planned Services

**CalculateRent service** (not yet implemented):
```ruby
# lib/services/calculate_rent.rb
class CalculateRent
  def self.call(year:, month:, test_mode: false)
    # Fetch config
    config = RentConfig.for_period(...)

    # Fetch active tenants
    tenants = Persistence.tenants.find_active_on(...)

    # Use RentCalculator (preserved logic)
    # ... calculation ...

    # Store in ledger
    # ... transaction ...
  end
end
```

**Benefits:**
- Testable without handlers
- Reusable from CLI/cron
- Clear transaction boundaries

### Planned Endpoints

**POST /api/electricity/manual_entry** - Manual invoice entry (emergency fallback)
**GET /api/config/:key/:period** - Get specific config value
**PUT /api/config/:key/:period** - Update config value (admin)

---

## Troubleshooting

### Common Issues

**Issue:** "Cannot find module 'lib/persistence'"
**Fix:** Use `require_relative` not `require`:
```ruby
require_relative 'lib/persistence'  # ✓ Correct
require 'lib/persistence'           # ✗ Wrong
```

**Issue:** "undefined method `for_period' for RentConfig"
**Fix:** Missing repository parameter:
```ruby
RentConfig.for_period(year: 2025, month: 10, repository: Persistence.rent_configs)  # ✓
RentConfig.for_period(year: 2025, month: 10)  # ✗ Missing repository
```

**Issue:** "wrong argument type String (expected Time)"
**Fix:** RentConfig period must be Time, not Date:
```ruby
Time.utc(2025, 9, 1)   # ✓ Correct
Date.new(2025, 9, 1)   # ✗ Wrong type
```

**Issue:** "Duplicate electricity bill not detected"
**Fix:** Use `store_with_deduplication` not `create`:
```ruby
Persistence.electricity_bills.store_with_deduplication(...)  # ✓ Deduplication
Persistence.electricity_bills.create(...)                    # ✗ No deduplication
```

---

## Summary Checklist for LLM Assistants

When working with this codebase:

- ✅ **Use Persistence module** for repository access
- ✅ **Call domain model class methods** for business logic (ElectricityBill.calculate_bill_period, RentConfig.for_period)
- ✅ **Use services for transactions** (ApplyElectricityBill.call)
- ✅ **Preserve API contracts** - handlers return same JSON structure
- ✅ **Use test database** - ENV['DATABASE_URL'] with `_test` suffix
- ✅ **Respect timing rules** - config period ≠ rent period ≠ consumption period
- ✅ **Never bypass deduplication** - use store_with_deduplication not create
- ✅ **Serialize for APIs** - call `to_h` on domain objects before returning JSON

**Key files to understand:**
1. `lib/persistence.rb` - Repository access
2. `lib/models/rent_config.rb` - Configuration business rules
3. `lib/services/apply_electricity_bill.rb` - Transaction example
4. `handlers/rent_calculator_handler.rb` - Handler example

**Complete migration status:** ✅ All phases complete (Oct 23, 2025)

---

**End of Guide**
