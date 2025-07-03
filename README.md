# Rent Calculator and History

A Ruby system for calculating rent distribution among roommates and maintaining historical records of rent payments.

## Components

### RentCalculator (rent.rb)

Core calculator that handles all rent calculations. Features:
- Weight-based rent distribution using days stayed
- Room adjustments (discounts/extra charges)
- Proper handling of partial months
- Quarterly invoice support (drift_rakning)
- Configurable constants
- Precise floating-point calculations (only rounded at final output)
- Messenger-friendly output format for easy sharing

### Persistent Storage

The system uses SQLite databases to maintain persistent state:

#### ConfigStore (lib/rent_config_store.rb)
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

#### RoommateStore (lib/roommate_store.rb)
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

#### RentHistory (lib/rent_history.rb)
Storage system for maintaining historical records of rent calculations:
- Stores input data (constants, roommate info)
- Records final rent amounts
- Supports versioning for tracking changes
- Optional version titles for clarity
- JSON-based storage for easy access

### API Integration (handlers/rent_calculator_handler.rb)

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

## Implementation Details

### Validation Rules and Safety Checks

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

### Rent Calculation Model

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

### Output Formats

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
     per_person = (total_electricity / 4.0).ceil
     
     # Adjust next month's rent calculation
     config = {
       el: 0,  # Set to zero since handled separately
       # ... other config ...
     }
     ```
   - When handled separately, the amount is excluded from next rent calculation
   - Special payment arrangements (e.g., one person covering multiple shares) are documented

3. Payment Arrangements:
   - Fredrik covers both his and Rasmus's shares of electricity bills
   - Other roommates pay their individual shares
   - This arrangement applies to separate electricity payments
   - Regular rent payments remain equally split

4. Documentation:
   - All electricity costs are tracked in `docs/electricity_costs.md`
   - Bills are recorded with both due dates and consumption months
   - Special payment arrangements are noted in scenarios
   - Historical patterns and trends are documented

## Usage Examples

```ruby
# Example usage
roommates = {
  'Alice' => { days: 30, room_adjustment: -200 },  # Full month, 200kr discount
  'Bob' => { days: 15, room_adjustment: 0 }        # Half month, no adjustment
}

config = {
  kallhyra: 10_000,     # Base rent
  el: 1_500,            # Electricity
  bredband: 400,        # Internet
  drift_rakning: 2_612, # Quarterly invoice (replaces monthly fees when present)
  saldo_innan: 0,       # Previous balance
  extra_in: 0           # Extra income
}

# Just calculate
results = RentCalculator.rent_breakdown(roommates, config)

# Or calculate and save to history in one step
results = RentCalculator.calculate_and_save(
  roommates: roommates,
  config: config,
  history_options: {
    version: 1,
    title: "Initial Calculation"  # Optional but recommended
  }
)
```

### RentHistory (lib/rent_history.rb)

Storage system for maintaining historical records of rent calculations. Features:
- Stores input data (constants, roommate info)
- Records final rent amounts
- Supports versioning for tracking changes
- Optional version titles for clarity
- JSON-based storage for easy access

```ruby
# Recording a month's rent
november = RentHistory::Month.new(
  year: 2024,
  month: 11,
  title: "Initial Calculation"  # Optional
)

# Store the input data
november.constants = config
november.roommates = roommates

# Record the results
november.record_results(results['Rent per Roommate'])
november.save  # Saves to project_root/data/rent_history/2024_11_v1.json

# Loading historical data
october = RentHistory::Month.load(
  year: 2024,
  month: 10
)
puts october.final_results  # Shows what each person paid
```

#### Storage and Versioning
- Files are stored in:
  - Production: `project_root/data/rent_history/YYYY_MM_vN.json` (default)
  - Test: `project_root/spec/data/rent_history/YYYY_MM_vN.json` (when test_mode: true)
- Version numbers (N) auto-increment if not specified
- Version titles help document significant changes (e.g., "Pre-Elvira", "After Elvira Joined")
- Use `force: true` with save to overwrite existing versions

#### Error Handling
- `RentHistory::VersionError` - Version conflicts
- `RentHistory::DirectoryError` - Directory access/permission issues
- All errors provide clear messages for troubleshooting
- Directories are created automatically when possible

#### Testing
- Use `test_mode: true` to store files in test directory
- Test files are automatically cleaned up between runs
- Test environment is completely isolated from production

## Version History Example

November 2024 demonstrates our versioning approach:

1. Version 1 ("Initial November Calculation (Pre-Elvira)"):
   - Original calculation before Elvira joined
   - Historical record of actual payments
   - Reimbursements: Malin (259 kr), others (339 kr)

2. Version 2 ("November Recalculation with Elvira's Partial Stay"):
   - Added Elvira (8 days, 1619 kr)
   - Updated calculation method
   - Final rent distribution

## Calculation Rules

The rent calculation follows these steps:
1. Calculate weights based on days stayed
2. Apply room adjustments (e.g., discount for smaller room)
3. Handle operational costs:
   - Use quarterly invoice (drift_rakning) when available
   - Otherwise use sum of monthly fees
4. Distribute total cost based on weights
5. Apply adjustments and redistribute fairly
6. Round only the final results (maintaining precision during calculations)

## Important Notes

- Files stored in data/rent_history/YYYY_MM_vN.json
- Room adjustments:
  - Negative values for discounts
  - Positive values for extra charges
- Quarterly invoice (drift_rakning):
  - Replaces monthly fees when present
  - Includes vattenavgift (water), VA (sewage), and larm (alarm)
  - Monthly fees are used to save up for quarterly invoice
  - Typically around 2600 kr per quarter
- Rounding behavior:
  - All intermediate calculations maintain full floating-point precision
  - Only final results are rounded
  - Ceiling preferred over floor to ensure total rent is covered
- Version numbers track significant changes:
  - New version when roommates join/leave
  - When recalculation is needed
  - For major corrections

## Development

Run the tests:
```bash
rspec spec/rent_calculator_spec.rb
rspec spec/rent_history_spec.rb
```

See examples/rent_history_example.rb for a detailed usage example.
See TODO.md for current development status and plans.