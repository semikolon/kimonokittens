# Kimonokittens Development Guide

This document contains technical implementation details, patterns, and guidelines for contributors working on the Kimonokittens monorepo.

---

## Rent Calculator System

This section covers the architecture and logic of the Ruby-based rent calculation system. For a high-level overview, see the main [README.md](README.md).

### 1. System Architecture & Components

The system is composed of several key components that work together:

*   **`RentCalculator` (`rent.rb`)**: The core engine responsible for all calculations. It takes roommate and cost data as input and produces a detailed breakdown and a user-friendly summary.
*   **Persistent Storage**: A set of classes that manage the state of the system using the filesystem.
    *   **`RentHistory` (`lib/rent_history.rb`)**: Manages versioned, historical records of all rent calculations in JSON files. This is the primary mechanism for storing and retrieving past results.
*   **API Integration (`handlers/rent_calculator_handler.rb`)**: A RESTful API that exposes the calculator's functionality. It's designed to be used by front-end applications, voice assistants, or other scripts.
    *   **Note**: The original design envisioned `ConfigStore` and `RoommateStore` as separate SQLite-backed libraries. This has been simplified in the current implementation, with configuration being passed directly to the calculator methods. The `RentHistory` module is the primary persistence mechanism.

### 2. Core Logic & Calculation Model

The rent calculation follows a specific order to ensure fairness and precision.

1.  **Total Rent Calculation**:
    The total distributable rent is calculated as:
    `total = kallhyra + drift_total - saldo_innan - extra_in`
    -   `drift_total` is the sum of `el`, `bredband`, and either the quarterly `drift_rakning` (if present) or the sum of monthly fees (`vattenavgift`, `va`, `larm`).

2.  **Weight-based Distribution**:
    -   Each roommate's weight is calculated as `days_stayed / total_days_in_month`.

3.  **Adjustment Application**:
    -   First, the sum of all prorated adjustments is calculated.
    -   The `distributable_rent` is then defined as `total_rent - total_adjustments`.
    -   This distributable amount is divided by the `total_weight` to find the cost per weight point.
    -   Each person's final rent is `(rent_per_weight_point * their_weight) + their_prorated_adjustment`.
    -   This model ensures each person pays exactly their adjustment amount more or less than their weighted share of the base costs.

4.  **Precision & Rounding**:
    -   All intermediate calculations maintain full floating-point precision.
    -   Only the final per-roommate amounts are rounded to the nearest integer krona.
    -   A remainder-distribution step ensures the sum of the rounded amounts exactly equals the total cost to be paid, preventing öre-level discrepancies.
    -   **Crucial Learning**: The remainder is distributed one öre at a time to the roommates with the largest fractional part in their un-rounded rent. This is fairer than giving it all to the single largest contributor, especially when multiple roommates have identical shares.

### 3. Validation Rules and Safety Checks

The system includes several validation rules to prevent common errors and ensure data consistency. These are conceptual guards and may not all be implemented as explicit code checks yet.

*   **Roommate Count**: The system should ideally warn if the total number of roommates falls outside the 3-4 person range, as this affects the financial viability of the household.
*   **Room Adjustments**: Large adjustments (e.g., > ±2000 SEK) should require explicit confirmation. Adjustments are always prorated based on the number of days a person stays during the month.
*   **Stay Duration**: The number of days for a partial stay cannot exceed the number of days in the given month.
*   **Data Consistency**: The calculator requires a minimum set of costs (`kallhyra`, `el`, `bredband`) to produce a valid result.

### 4. Specific Business Logic

#### Electricity Bill Handling

The system is designed to handle a specific billing cycle for electricity costs:

*   **Normal Flow**: Bills for a given month's consumption (e.g., January) typically arrive in the following month (February). These costs are then included in the rent calculation for the month after that (March), which is due at the end of February.
*   **Timeline Example**:
    1.  **January**: Electricity is consumed.
    2.  **Early February**: Bills for January's consumption arrive.
    3.  **Late February**: The January electricity costs are included in the **March rent calculation**.
    4.  **Feb 27**: March rent is due, covering January's electricity costs.
*   **Special Cases**: If a bill needs to be paid separately (e.g., it's overdue), the `el` cost for that period should be set to `0` in the next rent calculation to avoid double-charging. The special payment arrangement (e.g., Fredrik covering multiple shares) is noted in `docs/electricity_costs.md`.

### 5. API and Usage Examples

The primary entry points are `rent_breakdown` (for detailed analysis) and `calculate_and_save` (for generating official records).

```ruby
# Example usage
roommates = {
  'Alice' => { days: 30, room_adjustment: -200 },  # Full month, 200kr discount
  'Bob' => { days: 15, room_adjustment: 0 }        # Half month, no adjustment
}

config = {
  kallhyra: 10_000,
  el: 1_500,
  bredband: 400,
  drift_rakning: 2_612, # Quarterly invoice (replaces monthly fees when present)
  saldo_innan: 0,
  extra_in: 0
}

# Calculate and save to history in one step
RentCalculator.calculate_and_save(
  roommates: roommates,
  config: config,
  history_options: {
    title: "Initial Calculation", # Optional but recommended
    test_mode: true # Use test directory for storage
  }
)
```

### 6. RentHistory Persistence Details

*   **Storage**: Files are stored in JSON format at:
    *   Production: `data/rent_history/YYYY_MM_vN.json`
    *   Testing: `spec/data/rent_history/YYYY_MM_vN.json`
*   **Versioning**:
    *   If no version `N` is provided on save, it auto-increments from the highest existing version for that month.
    *   Use versions to track significant changes, like a roommate joining mid-month or a major correction.
    *   Use `force: true` when saving to explicitly overwrite an existing version file.
*   **Error Handling**: The module raises custom errors for common issues:
    *   `RentHistory::VersionError` on version conflicts.
    -   `RentHistory::DirectoryError` on filesystem permission issues.

### 7. Output Formats

The calculator produces two primary outputs:

1.  **Detailed Breakdown**: A hash containing a full breakdown of all costs, weights, and the final rent per roommate. This is used for record-keeping in `RentHistory` and for detailed verification.
2.  **Friendly Message**: A concise, Markdown-formatted string suitable for sharing in a group chat (e.g., Facebook Messenger). It provides a clear summary of who pays what and when it's due.

### 8. Recent Learnings & Key Decisions (July 2025)

Our recent work reconstructing the `RentCalculator` yielded several important learnings:

*   **Value of a Robust Test Suite**: The comprehensive RSpec suite was indispensable for correctly reconstructing the lost business logic. It served as executable documentation and prevented regressions.
*   **Handling Key Types**: A recurring source of bugs was the mismatch between `String` and `Symbol` keys in hashes, especially after JSON serialization/deserialization.
    *   **Decision**: For any data structure intended for presentation or external storage (like the output of `rent_breakdown` or `RentHistory`), we will standardize on **string keys** to avoid ambiguity. Internal calculation hashes can continue to use symbols for performance.
*   **Importance of Committing Untracked Files**: The original loss of the `rent.rb` file was due to it being untracked (`.gitignore`) and overwritten during a merge. This highlights the need to commit even work-in-progress code to a feature branch.
*   **Clarity over cleverness**: The original `calculate_rent` tried to do too much. It now has a single responsibility: calculate the final, unrounded amounts per roommate. The separate `rent_breakdown` method handles rounding and formatting for presentation.

### 9. Testing Considerations

1.  **Floating Point Precision**: Use RSpec's `be_within(0.01).of(expected)` for comparing floating-point numbers. Direct equality checks (`eq`) will often fail due to precision limits.
2.  **Test Data Organization**: Use simple, round numbers (e.g., total rent of 10,000) for basic unit tests and real-world data (like the complex November 2024 scenario) for integration tests to catch nuanced edge cases.
3.  **RentHistory Testing**: Tests must handle file I/O carefully, creating and cleaning up test-specific data directories and files to avoid polluting real data or failing due to existing state.

### 10. Common Gotchas

1.  **Drift Calculation**: When a quarterly invoice (`drift_rakning`) is present for a month, it **replaces** the standard monthly fees (`vattenavgift`, `va`, `larm`). The monthly fees are only used if `drift_rakning` is zero or not present.
2.  **Room Adjustments**: Remember that adjustments are prorated. A -1000 SEK adjustment for someone staying half the month will only result in a -500 SEK reduction in their final rent.
3.  **Data Persistence**: Use versioning in `RentHistory` to track significant changes or different scenarios for a single month.
4.  **Script-based testing**: The `if __FILE__ == $0` block at the end of `rent.rb` is useful for quick, manual testing. However, any logic or scenario tested there should ideally be moved into a proper RSpec integration test to ensure it runs as part of the automated suite. 