# Kimonokittens – Meta Repository

This repo is a **multi-project monorepo** for various home-automation and finance tools running on the Raspberry Pi at _kimonokittens.com_.

Active sub-projects:

| Path | Purpose |
|------|---------|
| `handbook/` | Live wiki & handbook for the kollektiv (React + Ruby Agoo) |
| `bankbuster/` | Automated downloader & parser for Bankgirot camt.054 reports (Ruby + Vue dashboard) |

When working in Cursor:

* Open the sub-folder you're focused on (`handbook/` or `bankbuster/`) as a **separate workspace** so the AI context stays tight.
* Each sub-project has its own README, TODO backlog and `.cursor/rules` directory.

The scripts for the rent calculation system also live at the repo root and `handlers/`. They share gems and the same Agoo server.

```bash
├── json_server.rb         # Boots Agoo, mounts sub-apps
├── handlers/              # Misc JSON endpoints (electricity, trains, etc.)
├── bankbuster/            # Bank scraper
└── handbook/              # Wiki SPA & API
```

---

## Rent Calculator and History

A Ruby system for calculating rent distribution among roommates and maintaining historical records of rent payments.

### Components

#### RentCalculator (rent.rb)

Core calculator that handles all rent calculations. Features:
- Weight-based rent distribution using days stayed
- Room adjustments (discounts/extra charges)
- Proper handling of partial months
- Quarterly invoice support (drift_rakning)
- Configurable constants
- Precise floating-point calculations (only rounded at final output)
- Messenger-friendly output format for easy sharing

#### Persistent Storage

The system uses SQLite databases to maintain persistent state:

##### ConfigStore (lib/rent_config_store.rb)
Manages all cost-related configurations:
- Base costs (rent, internet, etc.)
- Monthly fees and quarterly invoices
- Previous balances and adjustments
- Supports both global and month-specific values

Example interactions:
```ruby
# Update internet cost
ConfigStore.instance.set('bredband', 450)

# Set quarterly invoice for specific month
ConfigStore.instance.set('drift_rakning', 2612, 2024, 12)
```

##### RoommateStore (lib/roommate_store.rb)
Manages all roommate-related data:
- Current roommates and their adjustments
- Move-in and move-out dates
- Temporary stays
- Room adjustment history

Example interactions:
```ruby
# Add new permanent roommate
RoommateStore.instance.add_permanent_roommate('Elvira', nil, Date.new(2024, 1, 1))

# Record a departure
RoommateStore.instance.set_departure('Astrid', Date.new(2024, 12, 15))

# Add temporary stay
RoommateStore.instance.set_monthly_stay('Amanda', 2024, 12, days: 10)
```

##### RentHistory (lib/rent_history.rb)
Storage system for maintaining historical records of rent calculations:
- Stores input data (constants, roommate info)
- Records final rent amounts
- Supports versioning for tracking changes
- Optional version titles for clarity
- JSON-based storage for easy access

#### API Integration (handlers/rent_calculator_handler.rb)

RESTful API designed for both human and AI interaction:
- Natural language friendly endpoints
- Smart defaults to minimize required input
- Support for voice assistant integration
- Messenger-friendly output format

Example voice interactions:
```
User: "What will my rent be?"
Assistant: [Calls API with stored defaults]

User: "The quarterly invoice came, it's 2612 kr"
Assistant: [Updates stored config via API]

User: "Elvira is moving in next month"
Assistant: [Updates roommate data via API]
```

### Implementation Details

#### Validation Rules and Safety Checks

The system includes several validation rules to prevent common errors and ensure data consistency:

1. Roommate Count:
   - Warns if total roommates would be less than 3 (minimum for cost-effectiveness)
   - Warns if total roommates would be more than 4 (space constraints)
   - Can be overridden with `force: true` when necessary (e.g., couple sharing room)

2. Room Adjustments:
   - Maximum adjustment of ±2000kr without force flag
   - Larger adjustments require explicit confirmation
   - Adjustments are always prorated based on days stayed

3. Stay Duration:
   - Never accepts more days than in the target month
   - Suggests using default full-month calculation when days = 30/31
   - Requires positive number of days

4. Data Consistency:
   - Validates all required costs (kallhyra, el, bredband)
   - Ensures no overlapping stays for same roommate
   - Maintains historical record of all changes

#### Rent Calculation Model

The rent calculation follows a specific order to ensure fairness and precision:

1. Total Rent Calculation:
   ```ruby
   total_rent = kallhyra + drift_total - saldo_innan - extra_in
   ```
   - Base rent (kallhyra) is the core component
   - Operational costs (drift_total) includes:
     - Electricity (el)
     - Internet (bredband)
     - Either quarterly invoice (drift_rakning) or monthly fees
   - Previous balance (saldo_innan) and extra income (extra_in) are subtracted

2. Weight-based Distribution:
   - Each roommate's weight = days_stayed / total_days_in_month
   - This ensures fair distribution for partial months
   - Total weight = sum of all roommate weights

3. Room Adjustments:
   - Calculate sum of all adjustments (prorated by days stayed)
   - Subtract total adjustments from total rent to get adjusted total
   - Calculate standard rent per weight unit:
     ```ruby
     standard_rent_per_weight = (total_rent - total_adjustments) / total_weight
     ```
   - For each roommate:
     - Base rent = standard_rent_per_weight × their_weight
     - Final rent = base_rent + their_adjustment
   - This ensures each person pays exactly their adjustment amount more/less than their weighted share
   - The total rent amount remains unchanged

4. Precision Handling:
   - All intermediate calculations maintain full floating-point precision
   - Only final per-roommate amounts are rounded (ceiling)
   - This prevents accumulation of rounding errors
   - Tests use be_within for floating-point comparisons

#### Output Formats

1. Detailed Breakdown:
   ```ruby
   results = RentCalculator.rent_breakdown(roommates: roommates, config: config)
   ```
   - Shows all cost components
   - Includes operational costs breakdown
   - Lists per-roommate amounts
   - Useful for verification and record-keeping

2. Messenger-friendly Format:
   ```ruby
   message = RentCalculator.friendly_message(roommates: roommates, config: config)
   ```
   - Concise format for sharing in group chat
   - Uses Markdown-style bold text with asterisks
   - Shows payment due date (27th of the previous month)
   - Swedish month names for better localization
   - Example output:
     ```
     *Hyran för januari 2025* ska betalas innan 27 dec och blir:
     *4905 kr* för Astrid och *6260 kr* för oss andra
     ```

### Testing Considerations

1. Floating Point Precision:
   ```ruby
   # Good: Use be_within for floating point comparisons
   expect(result).to be_within(0.01).of(expected)
   
   # Bad: Direct equality will fail due to floating point precision
   expect(result).to eq(expected)
   ```

2. Test Data Organization:
   - Use simple numbers (e.g., 10_000) for basic test cases
   - Use real data (e.g., November 2024) for integration tests
   - Test edge cases with uneven numbers (e.g., 100.01)

3. RentHistory Testing:
   - Clean up test files before and after tests
   - Create data directories if needed
   - Handle version conflicts explicitly
   - Convert hash keys for proper data loading

4. Common Test Scenarios:
   - Full month stays with equal shares
   - Partial month stays with prorated rent
   - Room adjustments (both positive and negative)
   - Multiple adjustments with redistribution
   - Edge cases with small amounts and many roommates

### Common Gotchas

1. Drift Calculation:
   - When drift_rakning (quarterly invoice) is present, it replaces monthly fees
   - Monthly fees (vattenavgift, va, larm) are only used when no drift_rakning
   - A zero drift_rakning is treated same as no drift_rakning

2. Room Adjustments:
   - Negative values for discounts (e.g., -1400 for smaller room)
   - Positive values for extra charges
   - Always prorated based on days stayed
   - Redistributed among all roommates based on weights

3. Data Persistence:
   - Always use version numbers for significant changes
   - Include descriptive titles for versions
   - Handle file conflicts explicitly
   - Maintain backwards compatibility

4. Error Handling:
   - Validate all required costs (kallhyra, el, bredband)
   - Ensure roommate days are valid (1 to days_in_month)
   - Handle file access and version conflicts gracefully
   - Provide clear error messages for recovery

### Electricity Bill Handling

The system handles electricity costs from two suppliers:

1. Regular Flow:
   - Bills arrive early in month X for month X-1's consumption
   - These bills are included in rent for month X+1 (due end of month X)
   - Example timeline:
     ```
     January: Consumption happens
     Early February: January's bills arrive
     Late February: Bills included in March rent calculation
     February 27: March rent due (including January's electricity)
     ```

2. Special Cases:
   - Late/overdue bills can be handled separately
   - Process for separate electricity payments:
     ```ruby
     # Example: Handling overdue bills separately
     total_electricity = vattenfall + fortum
     ```
