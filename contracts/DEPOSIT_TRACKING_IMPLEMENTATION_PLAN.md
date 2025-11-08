# Deposit Tracking Implementation Plan

## Problem Statement

**Current State:**
- Deposit amounts hardcoded in contract markdown files (6,200 + 2,200 kr)
- No tracking of what tenant ACTUALLY paid at move-in
- No refund calculation logic when tenant departs
- Contract states "en dryg (1) kall månadshyra" but doesn't explain formula

**Goal:**
- Track actual deposits paid per tenant in database
- Support formula-based deposit calculation: ~110% of per-person base rent
- Enable accurate refund calculations when tenant moves out
- Single source of truth for deposit data

## Architecture Analysis (from Explore Subagent)

### Current State ✅
- **Database columns already exist** (migration `20251108_add_contract_fields_to_tenant`)
- Columns: `deposit`, `furnishingDeposit` (Decimal 10,2)
- **Gap**: Ruby domain model and repository don't expose these fields yet

### Deposit Formula

```ruby
BASE_RENT_TOTAL = 24_530  # Total apartment kallhyra

# Per-person calculation:
num_active_tenants = 4
base_rent_per_person = BASE_RENT_TOTAL / num_active_tenants  # = 6,132.5 kr
deposit_per_person = (base_rent_per_person * 1.1).round      # ≈ 6,746 kr

FURNISHING_DEPOSIT = 2_200  # Constant (co-ownership buy-in)
```

**Reality vs Formula:**
- Formula suggests: 6,746 kr
- Actual paid (observed): 6,200 kr
- **Key insight**: Always store ACTUAL paid amount, not formula result

### Refund Scenario Example

**Sanna moves in (2025, 4 people):**
- Pays deposit: 6,200 kr (what she ACTUALLY paid)

**Sanna moves out (2028, 5 people):**
- New deposits would be: ~5,400 kr (lower due to more people)
- Sanna gets back: **6,200 kr** (what she paid), NOT 5,400 kr
- Minus deductions for damages/items taken

**Therefore:** Must track `depositPaid` at move-in, not calculate dynamically.

## Implementation Phases

### Phase 1: Domain Model Extension (REQUIRED)

**File:** `lib/models/tenant.rb`

**Changes:**

1. Add deposit fields to `attr_reader`:
```ruby
attr_reader :id, :name, :email, :facebook_id, :avatar_url,
            :room_adjustment, :start_date, :departure_date,
            :created_at, :updated_at,
            # Contract fields:
            :personnummer, :phone,
            :deposit, :furnishing_deposit
```

2. Update `initialize`:
```ruby
def initialize(id: nil, name:, email:, facebook_id: nil, avatar_url: nil,
               room_adjustment: nil, start_date: nil, departure_date: nil,
               created_at: nil, updated_at: nil,
               # Contract fields:
               personnummer: nil, phone: nil,
               deposit: nil, furnishing_deposit: nil)
  # ... existing assignments ...
  @personnummer = personnummer
  @phone = phone
  @deposit = parse_decimal(deposit)
  @furnishing_deposit = parse_decimal(furnishing_deposit)
end

private

def parse_decimal(value)
  return nil if value.nil?
  return value.to_f if value.is_a?(Numeric)
  value.to_s.to_f
end
```

3. Add business logic methods:
```ruby
# Check if deposits paid
def deposit_paid?
  !deposit.nil? && deposit > 0
end

def furnishing_deposit_paid?
  !furnishing_deposit.nil? && furnishing_deposit > 0
end

# Calculate total deposits
def total_deposits_paid
  (deposit || 0) + (furnishing_deposit || 0)
end

# Calculate expected deposit (formula-based)
def self.calculate_deposit(num_active_tenants, total_base_rent: 24_530)
  base_rent_per_person = total_base_rent / num_active_tenants.to_f
  (base_rent_per_person * 1.1).round
end
```

4. Update `to_h` serialization:
```ruby
def to_h
  {
    id: id,
    name: name,
    email: email,
    # ... existing fields ...
    personnummer: personnummer,
    phone: phone,
    deposit: deposit,
    furnishingDeposit: furnishing_deposit
  }
end
```

5. Add validation (optional):
```ruby
def validate!
  # ... existing validations ...

  if deposit && deposit < 0
    raise ArgumentError, "Deposit cannot be negative"
  end

  if furnishing_deposit && furnishing_deposit < 0
    raise ArgumentError, "Furnishing deposit cannot be negative"
  end
end
```

### Phase 2: Repository Extension (REQUIRED)

**File:** `lib/repositories/tenant_repository.rb`

**Changes:**

1. Update `hydrate` method:
```ruby
def hydrate(row)
  Tenant.new(
    id: row[:id],
    name: row[:name],
    email: row[:email],
    facebook_id: row[:facebookId],
    avatar_url: row[:avatarUrl],
    room_adjustment: row[:roomAdjustment],
    start_date: row[:startDate],
    departure_date: row[:departureDate],
    created_at: row[:createdAt],
    updated_at: row[:updatedAt],
    # Contract fields:
    personnummer: row[:personnummer],
    phone: row[:phone],
    deposit: row[:deposit],
    furnishing_deposit: row[:furnishingDeposit]
  )
end
```

2. Update `dehydrate` method:
```ruby
def dehydrate(tenant)
  {
    id: tenant.id || generate_id,
    name: tenant.name,
    email: tenant.email,
    facebookId: tenant.facebook_id,
    avatarUrl: tenant.avatar_url,
    roomAdjustment: tenant.room_adjustment,
    startDate: tenant.start_date,
    departureDate: tenant.departure_date,
    createdAt: tenant.created_at || now_utc,
    updatedAt: now_utc,
    # Contract fields:
    personnummer: tenant.personnummer,
    phone: tenant.phone,
    deposit: tenant.deposit,
    furnishingDeposit: tenant.furnishing_deposit
  }
end
```

### Phase 3: Testing (REQUIRED)

**File:** `spec/models/tenant_spec.rb` (or new file `spec/models/tenant_deposits_spec.rb`)

**Tests:**

```ruby
require 'spec_helper'
require_relative '../lib/models/tenant'

RSpec.describe Tenant, 'deposit tracking' do
  describe 'initialization' do
    it 'accepts deposit and furnishing_deposit' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        deposit: 6200,
        furnishing_deposit: 2200
      )

      expect(tenant.deposit).to eq(6200.0)
      expect(tenant.furnishing_deposit).to eq(2200.0)
    end

    it 'allows nil deposits' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com')
      expect(tenant.deposit).to be_nil
      expect(tenant.furnishing_deposit).to be_nil
    end
  end

  describe '#deposit_paid?' do
    it 'returns true when deposit set' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com', deposit: 6200)
      expect(tenant.deposit_paid?).to be true
    end

    it 'returns false when deposit nil' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com')
      expect(tenant.deposit_paid?).to be false
    end

    it 'returns false when deposit zero' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com', deposit: 0)
      expect(tenant.deposit_paid?).to be false
    end
  end

  describe '#total_deposits_paid' do
    it 'sums both deposits' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        deposit: 6200,
        furnishing_deposit: 2200
      )
      expect(tenant.total_deposits_paid).to eq(8400.0)
    end

    it 'handles nil values' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com')
      expect(tenant.total_deposits_paid).to eq(0.0)
    end
  end

  describe '.calculate_deposit' do
    it 'calculates 110% of per-person base rent' do
      deposit = Tenant.calculate_deposit(4, total_base_rent: 24_530)
      # (24530 / 4) * 1.1 = 6745.75 → rounded to 6746
      expect(deposit).to eq(6746)
    end

    it 'handles different occupancy levels' do
      deposit_4_people = Tenant.calculate_deposit(4)
      deposit_5_people = Tenant.calculate_deposit(5)

      expect(deposit_4_people).to be > deposit_5_people
    end
  end

  describe '#to_h' do
    it 'includes deposit fields' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        personnummer: '1234567890',
        phone: '070-123 45 67',
        deposit: 6200,
        furnishing_deposit: 2200
      )

      hash = tenant.to_h
      expect(hash[:personnummer]).to eq('1234567890')
      expect(hash[:phone]).to eq('070-123 45 67')
      expect(hash[:deposit]).to eq(6200.0)
      expect(hash[:furnishingDeposit]).to eq(2200.0)
    end
  end
end
```

**Repository tests:**

```ruby
# spec/repositories/tenant_repository_spec.rb
RSpec.describe TenantRepository, 'deposit persistence' do
  let(:repo) { TenantRepository.new(db) }

  it 'persists deposits to database' do
    tenant = Tenant.new(
      name: 'Test',
      email: 'test@example.com',
      deposit: 6200,
      furnishing_deposit: 2200
    )

    created = repo.create(tenant)
    retrieved = repo.find_by_id(created.id)

    expect(retrieved.deposit).to eq(6200.0)
    expect(retrieved.furnishing_deposit).to eq(2200.0)
  end

  it 'handles nil deposits' do
    tenant = Tenant.new(name: 'Test', email: 'test@example.com')

    created = repo.create(tenant)
    retrieved = repo.find_by_id(created.id)

    expect(retrieved.deposit).to be_nil
    expect(retrieved.furnishing_deposit).to be_nil
  end
end
```

### Phase 4: Contract Integration (FUTURE)

**Not included in this phase** - will be handled by template refactor:
- Generate contracts from database instead of markdown
- Pull deposit amounts from Tenant table
- Display formula explanation in contracts

## What We're NOT Implementing (Yet)

**Deferred to Future:**
1. **API handlers** for setting/updating deposits via HTTP
2. **Refund calculation logic** (deposits - deductions)
3. **Damage/deduction tracking** system
4. **Contract generation from database** (covered by template refactor)

**Rationale:** Focus on core domain model first. API and refund logic can be added incrementally.

## Migration Strategy

**Database:** ✅ Already migrated (migration `20251108_add_contract_fields_to_tenant`)

**Data Migration:** Not needed yet - existing tenants can have NULL deposits initially.

**Future Data Sync:** When template refactor complete, can migrate deposit data from contract JSON files to database if needed.

## Success Criteria

- ✅ Tenant model accepts deposit parameters
- ✅ Tenant model provides deposit query methods
- ✅ Repository persists deposits to database
- ✅ Repository retrieves deposits from database
- ✅ All tests pass (unit + integration)
- ✅ No breaking changes to existing rent calculation
- ✅ Backward compatible (NULL deposits allowed)

## Timeline Estimate

- Phase 1 (Domain Model): 45 min
- Phase 2 (Repository): 30 min
- Phase 3 (Tests): 60 min
- **Total: ~2 hours**

## Files to Modify

1. `lib/models/tenant.rb` - Add deposit fields and methods
2. `lib/repositories/tenant_repository.rb` - Add hydrate/dehydrate
3. `spec/models/tenant_spec.rb` - Add deposit tests
4. `spec/repositories/tenant_repository_spec.rb` - Add persistence tests

## Next Steps After This

After deposit tracking complete:
1. Implement template refactor (handbook → ERB → contracts)
2. Sync tenant data from JSON to database
3. Generate contracts from database instead of markdown
4. Single source of truth achieved ✅
