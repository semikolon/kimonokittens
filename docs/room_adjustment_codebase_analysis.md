# Codebase Congruence Analysis Report

## Executive Summary

The kimonokittens codebase has a **well-established room adjustment system** using fixed kronor amounts (not percentages). The `roomAdjustment` field exists in both database schema and domain models, with historical precedent for discounting smaller/less desirable rooms. The rent calculation follows a sophisticated **redistribution algorithm** where room adjustments affect the base rent distribution among all tenants, ensuring total apartment rent remains constant.

**Primary Recommendation**: Extend the existing `roomAdjustment` framework with room metadata (size, quality attributes) to enable transparent pricing for new arrangements like couples sharing connected rooms.

---

## Proposed Feature/Solution Context

- **Description**: Design framework for pricing rooms when adding a 5th person (couple sharing two connected walk-through rooms)
- **Affected Areas**: Domain models (`Tenant`), repositories (`TenantRepository`), rent calculator (`rent.rb`), handlers (`rent_calculator_handler.rb`)
- **Key Requirements**:
  - Transparent room pricing based on objective factors (size, amenities, ventilation)
  - Support for couples sharing multi-room spaces
  - Maintain existing fairness principles in rent distribution

---

## Existing Infrastructure

### Relevant Patterns Found

#### 1. **Room Adjustment System** (Core Pattern)

**Location**: Multiple files across the codebase

- **Database Schema**: `prisma/schema.prisma:69` - `roomAdjustment Float?` on `Tenant` model
- **Database Schema**: `prisma/schema.prisma:54` - `roomAdjustment Float?` on `RentLedger` model (historical tracking)
- **Domain Model**: `lib/models/tenant.rb:29` - Attribute with proration logic
- **Repository**: `lib/repositories/tenant_repository.rb:158-160` - `set_room_adjustment(tenant_id, adjustment)` method
- **Calculator**: `rent.rb:217-241` - `AdjustmentCalculator` class handles prorated adjustments
- **Handler API**: `handlers/rent_calculator_handler.rb:193` - `room_adjustment` parameter in API docs
- **Handler API**: `handlers/rent_calculator_handler.rb:343-355` - `update_adjustment` endpoint

**Implementation Details**:
- **Type**: Fixed kronor amount (positive = surcharge, negative = discount)
- **Proration**: Automatically prorated by days stayed (lines `rent.rb:234`)
  ```ruby
  prorated = info[:room_adjustment] * (days.to_f / @total_days)
  ```
- **Redistribution**: Total adjustment redistributed among all tenants based on their weights (lines `rent.rb:258-263`)
  ```ruby
  distributable_rent = config.total_rent - total_adjustment
  rent_per_weight_point = distributable_rent / total_weight
  ```

#### 2. **Historical Precedent: Astrid Case** (Documented Pattern)

**Location**: `rent_november.rb:35-38`

```ruby
# Förutom Astrid som ska få ett avdrag på 1400 kr
# eftersom hennes rum inte har god ventilation osv
deduction_astrid = 1400
```

**Historical Data**: `data/rent_history/2024_11_v2.json`
- **Astrid**: -1400 kr adjustment (poor ventilation room)
- **Malin**: -1900 kr adjustment (presumably smaller/inferior room)
- **Result**: Fredrik/Rasmus/Frans-Lukas paid 6,149 kr, Astrid paid 4,749 kr, Malin paid 4,305 kr

**Rationale**: "eftersom hennes rum inte har god ventilation osv" (poor ventilation)

This establishes clear precedent for:
- Discounting rooms based on **objective quality factors** (ventilation, size)
- Using **fixed kronor amounts** rather than percentages
- **Transparency** about why adjustments exist

#### 3. **Weight-Based Distribution** (Core Algorithm)

**Location**: `rent.rb:179-215` - `WeightCalculator` class

```ruby
def calculate
  weights = {}
  total_weight = 0.0

  @roommates.each do |name, info|
    days = info[:days] || @total_days
    weight = days.to_f / @total_days
    weights[name] = weight
    total_weight += weight
  end

  [weights, total_weight]
end
```

**Algorithm Flow** (`rent.rb:248-279`):
1. Calculate each tenant's weight (days_stayed / total_days_in_month)
2. Calculate prorated adjustments for each tenant
3. Subtract total adjustments from apartment total: `distributable_rent = total_rent - total_adjustment`
4. Divide distributable rent by total weight: `rent_per_weight_point = distributable_rent / total_weight`
5. Calculate base rent: `base_rent = weight × rent_per_weight_point`
6. Apply adjustment: `final_rent = base_rent + prorated_adjustment`

**Key Insight**: Adjustments **redistribute** costs among all tenants. A -1400 kr discount means others pay proportionally more to cover it, maintaining total apartment rent.

#### 4. **Precision & Rounding Strategy** (Quality Pattern)

**Location**: `rent.rb:299-339`

- All intermediate calculations use **full floating-point precision**
- Only final per-roommate amounts are rounded (line 300)
- **Remainder distribution** ensures total equals exactly (lines 307-326)
  - Distributes remainder to tenants with highest fractional parts (fairest approach)
- **Equalization for small differences**: If max-min < 10 kr, everyone pays max amount (lines 333-339)

### Available Tools & Dependencies

#### Database Schema (Prisma)

**Location**: `prisma/schema.prisma`

**Tenant Model** (lines 61-82):
```prisma
model Tenant {
  id                 String           @id
  name               String
  email              String           @unique
  roomAdjustment     Float?           // ✅ ALREADY EXISTS
  startDate          DateTime?
  departureDate      DateTime?
  // Contract fields
  personnummer       String?
  phone              String?
  baseRent           Decimal?         @db.Decimal(10, 2)  // ⚠️ Unused field
  deposit            Decimal?         @db.Decimal(10, 2)
  furnishingDeposit  Decimal?         @db.Decimal(10, 2)
  status             String?          @default("active")
  RentLedger         RentLedger[]
  CoOwnedItem        CoOwnedItem[]    @relation("ItemOwners")
  SignedContract     SignedContract[]
}
```

**RentLedger Model** (lines 45-59):
```prisma
model RentLedger {
  id               String    @id
  tenantId         String
  period           DateTime
  amountDue        Float
  amountPaid       Float
  paymentDate      DateTime?
  daysStayed       Float?
  roomAdjustment   Float?    // ✅ Historical tracking
  baseMonthlyRent  Float?
  calculationTitle String?
  calculationDate  DateTime?
  Tenant           Tenant    @relation(fields: [tenantId], references: [id])
}
```

**Observations**:
- `roomAdjustment` already exists in both Tenant and RentLedger
- `baseRent` field exists but is **unused** in current calculations
- No fields for room metadata (size, quality attributes)

#### Domain Models

**Location**: `lib/models/tenant.rb`

**Key Methods**:
- `days_stayed_in_period(period_start, period_end)` (lines 86-99) - Handles move-in/out logic
- `prorated_adjustment(total_days_in_month, days_stayed)` (lines 113-116) - Calculates prorated adjustment
- `has_room_adjustment?` (lines 134-136) - Checks if adjustment exists
- `calculate_deposit(num_active_tenants, total_base_rent: 24_530)` (lines 164-167) - Deposit formula (~110% of per-person base rent)

**Untapped Capabilities**:
- No room metadata storage/calculation methods
- No multi-tenant unit support (couples)

#### REST API Endpoints

**Location**: `handlers/rent_calculator_handler.rb`

**Available Operations**:
1. **POST /api/rent/roommates** (lines 301-365)
   - `action: 'add_permanent'` - Add new tenant with optional `room_adjustment`
   - `action: 'update_adjustment'` - Update existing tenant's adjustment
   - `action: 'set_departure'` - Set departure date
   - `action: 'set_temporary'` - **NOT IMPLEMENTED** (line 356-359)

2. **GET /api/rent/roommates** (lines 367-372)
   - List all current tenants with their adjustments

3. **POST /api/rent** (lines 93-133)
   - Calculate rent with custom `roommates` hash including `room_adjustment`

4. **PUT /api/rent/config** (lines 274-299)
   - Update rent configuration values (kallhyra, el, etc.)

**Example Request** (from docs, lines 232-244):
```json
{
  "roommates": {
    "Fredrik": {},
    "Rasmus": {},
    "Astrid": {
      "days": 15,
      "room_adjustment": -1400
    }
  }
}
```

### Similar Implementations

**Deposit Calculation Pattern**

**Location**: `lib/models/tenant.rb:164-167`

```ruby
def self.calculate_deposit(num_active_tenants, total_base_rent: 24_530)
  base_rent_per_person = total_base_rent / num_active_tenants.to_f
  (base_rent_per_person * 1.1).round
end
```

**Pattern**: Mathematical formula based on:
- Number of active tenants
- Total apartment base rent (24,530 kr)
- Multiplier (110%) for safety margin

**Relevance**: Demonstrates pattern of **algorithmic calculations** based on apartment totals and tenant counts, which could be extended to room pricing.

---

## Alignment Analysis

### Architectural Consistency

- **Follows existing patterns**: ✅ **YES**
  - Fixed kronor adjustments (not percentages)
  - Stored at tenant level (not room level)
  - Redistributed through weight-based calculation
  - Prorated by days stayed

- **Specific observations**:
  1. **Database Ready**: `roomAdjustment` field already exists in schema
  2. **API Ready**: Endpoints already support setting/updating adjustments
  3. **Calculator Ready**: Core algorithm handles arbitrary adjustment amounts
  4. **Historical Precedent**: Astrid case (-1400 kr) and Malin case (-1900 kr) establish pattern

### Reusable Components

**Fully Reusable** (no changes needed):

1. **`TenantRepository.set_room_adjustment(tenant_id, adjustment)`**
   - Location: `lib/repositories/tenant_repository.rb:158-160`
   - Usage: Set any tenant's room adjustment

2. **`Tenant.prorated_adjustment(total_days_in_month, days_stayed)`**
   - Location: `lib/models/tenant.rb:113-116`
   - Usage: Calculate prorated adjustment for partial months

3. **`RentCalculator.rent_breakdown(roommates:, config:)`**
   - Location: `rent.rb:283-384`
   - Usage: Calculate rent with any adjustment amounts
   - Already handles redistribution algorithm

4. **POST /api/rent/roommates with `action: 'update_adjustment'`**
   - Location: `handlers/rent_calculator_handler.rb:343-355`
   - Usage: Update any tenant's adjustment via HTTP API

**Needs Extension** (add new functionality):

1. **Room Metadata Storage** - NOT EXISTS
   - Current: Only adjustment amount stored
   - Needed: Room size, quality factors, couple status
   - Approach: Add fields to Tenant model or create Room model

2. **Couple/Unit Handling** - PARTIAL
   - Current: Each tenant is independent
   - Needed: Link tenants in same unit, handle joint pricing
   - Approach: Add relationship fields or unit grouping

3. **Room Pricing Algorithm** - NOT EXISTS
   - Current: Manual adjustment amounts
   - Needed: Calculate adjustment from room attributes
   - Approach: Create `RoomPricingCalculator` service

---

## Gap Identification

### What's Truly Missing

1. **Room Metadata Model**
   - No fields for: room size (sqm), amenities, quality ratings
   - No structured way to document why adjustment exists
   - No room-level entity (only tenant-level data)

2. **Couple/Unit Support**
   - No way to link two tenants as a couple
   - No shared billing entity
   - No joint deposit tracking

3. **Room Pricing Algorithm**
   - No automatic calculation of adjustments from room attributes
   - No transparency/audit trail for how adjustments determined
   - No tooling to compare room values

4. **Documentation of Adjustment Rationale**
   - Adjustment amounts stored, but not WHY
   - Astrid case documented in comment, but not in database
   - No structured quality/issue tracking

### What Needs Enhancement

1. **Tenant Model** - Add room metadata fields
   - `room_size_sqm` (Float) - Objective size measure
   - `room_quality_issues` (JSON) - Structured issues list (ventilation, noise, etc.)
   - `room_amenities` (JSON) - Structured amenities list (ensuite, balcony, etc.)
   - `unit_id` (String, nullable) - Group tenants in same unit (for couples)
   - `adjustment_rationale` (String) - Human-readable explanation

2. **RentLedger Model** - Already has `roomAdjustment` field ✅
   - Consider adding `adjustment_rationale` for historical transparency

3. **API Endpoints** - Add room metadata parameters
   - Extend `add_permanent` and `update_adjustment` endpoints
   - Add validation for room metadata

4. **Dashboard/Frontend** - Show room comparisons
   - Visualize room sizes, quality factors
   - Display adjustment rationales
   - Compare rent per sqm across rooms

---

## Recommendations

### Primary Approach: **Extend Existing `roomAdjustment` Framework**

**Rationale**: The existing system already handles everything needed algorithmically. The only gaps are metadata and transparency.

**Implementation Steps**:

1. **Add Room Metadata to Tenant Model** (Database Migration)

```prisma
model Tenant {
  // ... existing fields ...
  roomAdjustment           Float?
  roomSizeSqm              Float?   // Room size in square meters
  roomQualityIssues        Json?    // { ventilation: "poor", noise: "high", natural_light: "low" }
  roomAmenities            Json?    // { ensuite: true, balcony: false, storage: "closet" }
  adjustmentRationale      String?  // "Discount for poor ventilation and smaller size"
  unitId                   String?  // Group tenants in same unit (for couples)
  adjustmentLastReviewed   DateTime? // When pricing was last evaluated

  // ... rest of model ...
}
```

2. **Create `RoomPricingCalculator` Service** (`lib/services/room_pricing_calculator.rb`)

```ruby
class RoomPricingCalculator
  # Base rent per sqm (derived from apartment total)
  BASE_RENT_PER_SQM = 24_530 / 85.0  # Assuming ~85 sqm apartment

  # Calculate room adjustment based on objective factors
  def self.calculate_adjustment(room_size_sqm:, quality_issues: {}, amenities: {}, num_tenants: 4)
    base_rent = room_size_sqm * BASE_RENT_PER_SQM
    fair_share = 24_530 / num_tenants.to_f

    # Adjust for quality issues
    quality_discount = calculate_quality_discount(quality_issues)

    # Adjust for amenities
    amenity_premium = calculate_amenity_premium(amenities)

    # Final adjustment = (base_rent - fair_share) + amenity_premium - quality_discount
    adjustment = (base_rent - fair_share) + amenity_premium - quality_discount
    adjustment.round
  end

  private

  def self.calculate_quality_discount(issues)
    discount = 0
    discount += 400 if issues['ventilation'] == 'poor'
    discount += 300 if issues['noise'] == 'high'
    discount += 200 if issues['natural_light'] == 'low'
    discount += 500 if issues['mold'] == true
    discount
  end

  def self.calculate_amenity_premium(amenities)
    premium = 0
    premium += 800 if amenities['ensuite'] == true
    premium += 400 if amenities['balcony'] == true
    premium += 200 if amenities['storage'] == 'walk_in_closet'
    premium
  end
end
```

3. **Update API Endpoints** (Extend existing)

Add room metadata parameters to `POST /api/rent/roommates`:

```ruby
when 'add_permanent'
  # ... existing code ...
  room_size_sqm = body['room_size_sqm']
  room_quality_issues = body['room_quality_issues']
  room_amenities = body['room_amenities']
  adjustment_rationale = body['adjustment_rationale']

  # Auto-calculate adjustment if metadata provided
  if room_size_sqm && !body['room_adjustment']
    calculated_adjustment = RoomPricingCalculator.calculate_adjustment(
      room_size_sqm: room_size_sqm,
      quality_issues: room_quality_issues || {},
      amenities: room_amenities || {},
      num_tenants: Persistence.tenants.find_active.count
    )
    room_adjustment = calculated_adjustment
  end

  new_tenant = Tenant.new(
    name: name,
    email: email,
    room_adjustment: room_adjustment,
    room_size_sqm: room_size_sqm,
    room_quality_issues: room_quality_issues,
    room_amenities: room_amenities,
    adjustment_rationale: adjustment_rationale,
    # ... other fields ...
  )
```

4. **Couple Support via `unitId`**

For couples sharing two rooms:
- Create two `Tenant` records with same `unitId`
- Each tenant has their own `room_adjustment` based on their specific room
- Dashboard shows combined rent for the unit
- Split deposit between couple members

**Example**:
```ruby
# Room 1 (larger, ensuite) - Person A
{
  name: "Alice",
  email: "alice@example.com",
  room_size_sqm: 16.0,
  room_amenities: { ensuite: true },
  room_adjustment: 800,  # Premium for ensuite + larger size
  unit_id: "couple_1"
}

# Room 2 (smaller, walk-through) - Person B
{
  name: "Bob",
  email: "bob@example.com",
  room_size_sqm: 12.0,
  room_quality_issues: { noise: "high" },  # Walk-through = more noise
  room_adjustment: -300,  # Discount for smaller + noise
  unit_id: "couple_1"
}

# Net couple adjustment: +800 - 300 = +500 kr/month
# Redistributed among other tenants via existing algorithm
```

5. **Documentation & Transparency**

- Add `adjustment_rationale` to dashboard display
- Show room comparison table (size, amenities, quality, rent)
- Display rent per sqm for each room
- Log adjustment calculations for audit trail

### Alternative Approaches

#### Alternative 1: **Percentage-Based Adjustments**

**Trade-offs**:
- ❌ Breaks existing pattern (all historical data uses fixed amounts)
- ❌ More complex to understand ("What's 5% of 6,132 kr?")
- ❌ Requires significant refactoring of calculator
- ✅ Scales automatically with total rent changes

**Verdict**: Not recommended. Fixed amounts are simpler and already established.

#### Alternative 2: **Separate Room Entity**

Create a `Room` model separate from `Tenant`:

```prisma
model Room {
  id                String   @id
  name              String   // "Blue Room", "Master Suite"
  sizeSqm           Float
  qualityIssues     Json?
  amenities         Json?
  baseAdjustment    Float
  currentTenant     Tenant?  @relation(...)
}
```

**Trade-offs**:
- ✅ Cleaner separation of concerns
- ✅ Easier to track room history
- ❌ More complex schema changes
- ❌ Requires data migration of existing tenants
- ❌ Overkill for 4-5 person apartment

**Verdict**: Over-engineered for current scale. Consider if apartment grows to 8+ rooms.

#### Alternative 3: **Per-Room Base Rent**

Set individual base rent per room (like commercial leases):

- Room A: 7,000 kr/month
- Room B: 6,500 kr/month
- Room C: 5,800 kr/month
- Room D: 5,200 kr/month

**Trade-offs**:
- ✅ Simplest for tenants to understand
- ✅ No redistribution complexity
- ❌ Breaks existing algorithm completely
- ❌ Doesn't handle partial months well
- ❌ Total rent can drift from apartment actual costs

**Verdict**: Not compatible with existing architecture. Would require complete rewrite.

### Implementation Considerations

**Dependencies to Leverage**:
- Prisma for schema migrations (`npx prisma migrate dev --name add_room_metadata`)
- Existing `Tenant` domain model and repository
- Existing `RentCalculator` algorithm (unchanged)
- Existing API endpoints (extend parameters)

**Patterns to Follow**:
1. **Store adjustment rationale** - Follow Astrid case documentation pattern
2. **Use fixed kronor amounts** - Match historical data format
3. **Leverage existing proration** - Don't reinvent days-stayed logic
4. **Maintain total rent** - Redistribution algorithm handles fairness

**Potential Pitfalls**:
1. **Avoid percentage-based adjustments** - Breaks compatibility with historical data
2. **Don't bypass existing calculator** - Redistribution algorithm is well-tested
3. **Document quality factors** - Transparency prevents disputes
4. **Handle couple billing carefully** - Need clear individual vs joint responsibility
5. **Test with historical data** - Verify calculations match November 2023 Astrid case

---

## Code Examples

### Example 1: Adding Room Metadata to Astrid (Historical Case)

**Migration**:
```sql
-- Add room metadata columns
ALTER TABLE "Tenant"
  ADD COLUMN "roomSizeSqm" DOUBLE PRECISION,
  ADD COLUMN "roomQualityIssues" JSONB,
  ADD COLUMN "roomAmenities" JSONB,
  ADD COLUMN "adjustmentRationale" TEXT,
  ADD COLUMN "adjustmentLastReviewed" TIMESTAMP;
```

**Update Historical Record**:
```ruby
astrid = Persistence.tenants.find_by_name("Astrid")

Persistence.tenants.update(
  Tenant.new(
    id: astrid.id,
    name: astrid.name,
    email: astrid.email,
    room_adjustment: -1400,
    room_size_sqm: 12.5,
    room_quality_issues: {
      ventilation: "poor",
      natural_light: "low"
    },
    adjustment_rationale: "Discount for poor ventilation and limited natural light",
    adjustment_last_reviewed: Date.new(2023, 11, 1)
  )
)
```

### Example 2: Adding Couple with Connected Rooms

```ruby
# POST /api/rent/roommates
{
  "action": "add_permanent",
  "name": "Emma",
  "email": "emma@example.com",
  "start_date": "2025-12-01",
  "room_size_sqm": 16.0,
  "room_amenities": {
    "ensuite": true,
    "balcony": true
  },
  "adjustment_rationale": "Premium for ensuite bathroom and private balcony",
  "unit_id": "couple_emma_oliver"
  // room_adjustment will be auto-calculated: +800 kr
}

# POST /api/rent/roommates
{
  "action": "add_permanent",
  "name": "Oliver",
  "email": "oliver@example.com",
  "start_date": "2025-12-01",
  "room_size_sqm": 11.0,
  "room_quality_issues": {
    "noise": "high"  // Walk-through room
  },
  "adjustment_rationale": "Discount for smaller size and walk-through traffic",
  "unit_id": "couple_emma_oliver"
  // room_adjustment will be auto-calculated: -400 kr
}

// Net couple impact: +800 - 400 = +400 kr/month redistributed to Fredrik/Rasmus/Adam
```

### Example 3: Calculate Rent for December 2025 with Couple

```ruby
roommates = {
  'Fredrik' => {},  # Base rent
  'Rasmus' => {},   # Base rent
  'Adam' => {},     # Base rent
  'Emma' => {
    room_adjustment: 800  # Premium for ensuite + balcony
  },
  'Oliver' => {
    room_adjustment: -400  # Discount for smaller + walk-through
  }
}

config = {
  year: 2025,
  month: 11,  # December config period (November bill data)
  kallhyra: 24530,
  el: 2200,
  bredband: 400,
  vattenavgift: 343,
  va: 274,
  larm: 137
}

results = RentCalculator.rent_breakdown(
  roommates: roommates,
  config: config
)

# Expected output:
# Total: ~28,884 kr
# Base rent per person: ~5,777 kr
# Redistributed adjustment: +400 kr total → +100 kr per other tenant
#
# Fredrik: 5,877 kr  (base + 100 kr from couple premium)
# Rasmus: 5,877 kr   (base + 100 kr from couple premium)
# Adam: 5,877 kr     (base + 100 kr from couple premium)
# Emma: 6,677 kr     (base + 100 kr share + 800 kr premium)
# Oliver: 5,477 kr   (base + 100 kr share - 400 kr discount)
#
# Verification: 5,877 + 5,877 + 5,877 + 6,677 + 5,477 = 29,785 kr ✅
```

### Example 4: Show Room Comparison in Dashboard

```ruby
# GET /api/rent/roommates?include_metadata=true

{
  "tenants": [
    {
      "name": "Fredrik",
      "room_size_sqm": 14.0,
      "room_adjustment": 0,
      "rent_per_sqm": 413,  // 5,777 / 14.0
      "adjustment_rationale": null
    },
    {
      "name": "Emma",
      "room_size_sqm": 16.0,
      "room_adjustment": 800,
      "rent_per_sqm": 417,  // 6,677 / 16.0
      "adjustment_rationale": "Premium for ensuite bathroom and private balcony",
      "unit_id": "couple_emma_oliver"
    },
    {
      "name": "Oliver",
      "room_size_sqm": 11.0,
      "room_adjustment": -400,
      "rent_per_sqm": 498,  // 5,477 / 11.0 (higher per sqm but lower total)
      "adjustment_rationale": "Discount for smaller size and walk-through traffic",
      "unit_id": "couple_emma_oliver"
    }
  ],
  "summary": {
    "total_sqm_rented": 55.0,
    "avg_rent_per_sqm": 435,
    "couple_total": 12154  // Emma + Oliver combined
  }
}
```

---

## Conclusion

The kimonokittens codebase already has **90% of the infrastructure needed** for transparent room pricing. The `roomAdjustment` mechanism is mature, well-tested, and follows established patterns from the Astrid case.

**The primary gap is metadata**, not algorithm. By adding room size, quality factors, and amenities to the existing Tenant model, the system can support transparent, objective room pricing without disrupting the core rent calculation logic.

**Next Steps**:
1. Decide on room metadata fields (sqm, quality issues, amenities)
2. Create Prisma migration for schema changes
3. Implement `RoomPricingCalculator` service
4. Extend API endpoints with room metadata parameters
5. Update dashboard to show room comparisons and adjustment rationales
6. Document pricing methodology for transparency

**Critical Success Factors**:
- Maintain fixed kronor adjustments (not percentages)
- Leverage existing redistribution algorithm (don't reinvent)
- Document rationale for every adjustment
- Test with historical cases (Astrid -1400 kr, Malin -1900 kr)
- Show rent per sqm for objective comparisons
