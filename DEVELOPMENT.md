# Kimonokittens Development Guide

This document contains technical implementation details, patterns, and guidelines for contributors working on the Kimonokittens monorepo.

---

## Rent Calculator System

This section covers the architecture and logic of the Ruby-based rent calculation system. For a high-level overview, see the main [README.md](README.md).

### 1. Core Logic & Calculation Model

The rent calculation follows a specific order to ensure fairness and precision.

1.  **Total Rent Calculation**:
    The total distributable rent is calculated as:
    `total = kallhyra + drift_total - saldo_innan - extra_in`
    -   `drift_total` is the sum of `el`, `bredband`, and either the quarterly `drift_rakning` (if present) or the sum of monthly fees (`vattenavgift`, `va`, `larm`).

2.  **Weight-based Distribution**:
    -   Each roommate's share is weighted by their days stayed: `weight = days_stayed / total_days_in_month`.
    -   This ensures fair distribution for partial months.

3.  **Room Adjustments & Redistribution**:
    -   The sum of all adjustments (prorated by days stayed) is calculated.
    -   This total adjustment is subtracted from the `total_rent` to find the `distributable_rent`.
    -   A per-weight-point rent is calculated: `rent_per_weight = distributable_rent / total_weight`.
    -   Each roommate's final rent is: `(rent_per_weight * their_weight) + their_adjustment`.
    -   This model ensures that the cost or benefit of an adjustment is socialized among all roommates according to their weight, while the person with the adjustment pays exactly their specified amount above or below their fair share.

4.  **Precision, Rounding, and Remainder Distribution**:
    -   All intermediate calculations maintain full floating-point precision.
    -   Final per-roommate amounts are rounded to the nearest integer (`.round`).
    -   To ensure the sum of rounded shares exactly equals the total rent, any remainder (usually a few öre) is distributed.
    -   **Crucial Learning**: The remainder is distributed one öre at a time to the roommates with the largest fractional part in their un-rounded rent. This is fairer than giving it all to the single largest contributor, especially when multiple roommates have identical shares.

### 2. Recent Learnings & Key Decisions (July 2025)

Our recent work reconstructing the `RentCalculator` yielded several important learnings:

*   **Value of a Robust Test Suite**: The comprehensive RSpec suite was indispensable for correctly reconstructing the lost business logic. It served as executable documentation and prevented regressions.
*   **Handling Key Types**: A recurring source of bugs was the mismatch between `String` and `Symbol` keys in hashes, especially after JSON serialization/deserialization.
    *   **Decision**: For any data structure intended for presentation or external storage (like the output of `rent_breakdown` or `RentHistory`), we will standardize on **string keys** to avoid ambiguity. Internal calculation hashes can continue to use symbols for performance.
*   **Importance of Committing Untracked Files**: The original loss of the `rent.rb` file was due to it being untracked (`.gitignore`) and overwritten during a merge. This highlights the need to commit even work-in-progress code to a feature branch.

### 3. Testing Considerations

1.  **Floating Point Precision**:
    -   **Good**: Use `be_within(0.01).of(expected)` for comparing floats.
    -   **Bad**: Direct equality (`eq`) will likely fail due to precision issues.

2.  **Test Data Organization**:
    -   Use simple, whole numbers for unit tests to verify specific logic.
    -   Use real-world data (e.g., the November 2024 scenario) for integration tests to catch complex edge cases.

3.  **`RentHistory` Testing**:
    -   Specs must clean up any created test files in `spec/data/rent_history/` before and after runs to ensure idempotency.
    -   Explicitly test version conflicts and file overwriting logic.

### 4. Common Gotchas

1.  **`drift_rakning` vs. Monthly Fees**: When `drift_rakning` (quarterly invoice) is present and non-zero, it **replaces** the monthly fees (`vattenavgift`, `va`, `larm`). The monthly fees are only used when `drift_rakning` is absent or zero.
2.  **Room Adjustments**: A negative value is a discount (e.g., `-1400`), while a positive value is an extra charge.
3.  **Script-based testing**: The `if __FILE__ == $0` block at the end of `rent.rb` is useful for quick, manual testing. However, any logic or scenario tested there should ideally be moved into a proper RSpec integration test to ensure it runs as part of the automated suite. 