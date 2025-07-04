# Kimonokittens Development Guide

This document contains technical implementation details, patterns, and guidelines for contributors working on the Kimonokittens monorepo.

---

## Rent Calculator System

This section covers the architecture and logic of the Ruby-based rent calculation system. For a high-level overview, see the main [README.md](README.md).

### 1. Unified System Architecture

The rent calculation system is being unified with the `handbook` application to create a single, robust service. The new architecture combines the strengths of the original Ruby business logic with a modern, type-safe persistence layer.

The key components are:

*   **React Frontend (`handbook/frontend`)**: A user interface within the handbook for displaying financial data (e.g., `<RentPanel/>`) and allowing for administrative changes.
*   **Ruby API (`handlers/rent_calculator_handler.rb`)**: The primary API for all rent-related operations. It contains the core calculation logic from `rent.rb` and is responsible for reading from and writing to the database. It's designed to be used by both the React frontend and by LLM-driven tools for natural language updates.
*   **PostgreSQL Database with Prisma**:
    *   **Database**: PostgreSQL is the authoritative datastore for all financial records, configuration, and tenant information.
    *   **Schema**: The database schema is managed by Prisma in `handbook/prisma/schema.prisma`. This provides a single source of truth for our data models (`Tenant`, `RentLedger`, etc.).
    *   **Client**: Prisma generates a type-safe JavaScript/TypeScript client, used by the frontend build process and any future Node.js scripts.

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

### 3. Data Persistence Model (PostgreSQL + Prisma)

All persistent data for the rent system is stored in a PostgreSQL database, managed by Prisma. This replaces the previous system of JSON files (`RentHistory`) and SQLite databases (`ConfigStore`, `RoommateStore`).

*   **Schema Source of Truth**: `handbook/prisma/schema.prisma` is the canonical source for all data models.
*   **Primary Models**:
    *   `Tenant`: Stores information about current and past roommates.
    *   `RentLedger`: The central table for financial records. Each row represents a specific charge or payment for a tenant for a given period, replacing the old `RentHistory` JSON files.
*   **Migrations**: Database schema changes are managed through Prisma Migrate. To create a new migration after editing the schema, run `npx prisma migrate dev --name <migration-name>`.
*   **Data Access**:
    *   The **Ruby API** will interact with the database directly, likely using the `pg` gem.
    *   The **React frontend** and other Node.js tools can use the type-safe Prisma Client for data access.

### 4. Validation Rules and Safety Checks

The system includes several validation rules to prevent common errors and ensure data consistency. These are conceptual guards and may not all be implemented as explicit code checks yet.

*   **Roommate Count**: The system should ideally warn if the total number of roommates falls outside the 3-4 person range, as this affects the financial viability of the household.
*   **Room Adjustments**: Large adjustments (e.g., > ±2000 SEK) should require explicit confirmation. Adjustments are always prorated based on the number of days a person stays during the month.
*   **Stay Duration**: The number of days for a partial stay cannot exceed the number of days in the given month.
*   **Data Consistency**: The calculator requires a minimum set of costs (`kallhyra`, `el`, `bredband`) to produce a valid result.

### 5. Specific Business Logic

#### Electricity Bill Handling

The system is designed to handle a specific billing cycle for electricity costs:

*   **Normal Flow**: Bills for a given month's consumption (e.g., January) typically arrive in the following month (February). These costs are then included in the rent calculation for the month after that (March), which is due at the end of February.
*   **Timeline Example**:
    1.  **January**: Electricity is consumed.
    2.  **Early February**: Bills for January's consumption arrive.
    3.  **Late February**: The January electricity costs are included in the **March rent calculation**.
    4.  **Feb 27**: March rent is due, covering January's electricity costs.
*   **Special Cases**: If a bill needs to be paid separately (e.g., it's overdue), the `el` cost for that period should be set to `0` in the next rent calculation to avoid double-charging. The special payment arrangement (e.g., Fredrik covering multiple shares) is noted in `docs/electricity_costs.md`.

### 6. API and Usage Examples

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

### 7. Output Formats

The calculator produces two primary outputs:

1.  **Detailed Breakdown**: A hash containing a full breakdown of all costs, weights, and the final rent per roommate. This is used for record-keeping in `RentHistory` and for detailed verification.
2.  **Friendly Message**: A concise, Markdown-formatted string suitable for sharing in a group chat (e.g., Facebook Messenger). It provides a clear summary of who pays what and when it's due.

### 8. Migration Plan: Unifying the Systems

We are currently migrating from a dual-system approach (Ruby/SQLite for backend logic, Node/Postgres for frontend concepts) to a single, unified architecture.

The high-level plan is as follows:

1.  **Commit to PostgreSQL and Prisma**: Adopt `schema.prisma` as the single source of truth for data models.
2.  **Activate Schema**: Uncomment the `RentLedger` model and apply the database migration.
3.  **Adapt Ruby API**: Modify the Ruby handlers (`rent_calculator_handler.rb`) to read from and write to the PostgreSQL database instead of using the old file-based persistence.
4.  **Connect Frontend**: Fully implement frontend components like `<RentPanel/>` to consume data from the unified API.

### 9. Recent Learnings & Key Decisions (July 2025)

Our recent work reconstructing the `RentCalculator` yielded several important learnings:

*   **Value of a Robust Test Suite**: The comprehensive RSpec suite was indispensable for correctly reconstructing the lost business logic. It served as executable documentation and prevented regressions.
*   **Handling Key Types**: A recurring source of bugs was the mismatch between `String` and `Symbol` keys in hashes, especially after JSON serialization/deserialization.
    *   **Decision**: For any data structure intended for presentation or external storage (like the output of `rent_breakdown` or `RentHistory`), we will standardize on **string keys** to avoid ambiguity. Internal calculation hashes can continue to use symbols for performance.
*   **Importance of Committing Untracked Files**: The original loss of the `rent.rb` file was due to it being untracked (`.gitignore`) and overwritten during a merge. This highlights the need to commit even work-in-progress code to a feature branch.
*   **Clarity over cleverness**: The original `calculate_rent` tried to do too much. It now has a single responsibility: calculate the final, unrounded amounts per roommate. The separate `rent_breakdown` method handles rounding and formatting for presentation.

### 10. Testing Considerations

1.  **Floating Point Precision**: Use RSpec's `be_within(0.01).of(expected)` for comparing floating-point numbers. Direct equality checks (`eq`) will often fail due to precision limits.
2.  **Test Data Organization**: Use simple, round numbers (e.g., total rent of 10,000) for basic unit tests and real-world data (like the complex November 2024 scenario) for integration tests to catch nuanced edge cases.
3.  **Database Test Cleaning**: When using `TRUNCATE` to clean a PostgreSQL database between tests, foreign key constraints will cause errors. The `TRUNCATE TABLE "MyTable" RESTART IDENTITY CASCADE;` command is essential. `CASCADE` ensures that any tables with a foreign key reference to `"MyTable"` are also truncated, which is necessary when dealing with Prisma's relational tables (e.g., `_ItemOwners`).

### 11. Common Gotchas

1.  **Drift Calculation**: When a quarterly invoice (`drift_rakning`) is present for a month, it **replaces** the standard monthly fees (`vattenavgift`, `va`, `larm`). The monthly fees are only used if `drift_rakning` is zero or not present.
2.  **Room Adjustments**: Remember that adjustments are prorated. A -1000 SEK adjustment for someone staying half the month will only result in a -500 SEK reduction in their final rent.
3.  **Data Persistence**: Use versioning in `RentHistory` to track significant changes or different scenarios for a single month.
4.  **Script-based testing**: The `if __FILE__ == $0` block at the end of `rent.rb` is useful for quick, manual testing. However, any logic or scenario tested there should ideally be moved into a proper RSpec integration test to ensure it runs as part of the automated suite.

---

## Key Technical Decisions & Learnings

This section captures non-obvious lessons learned during development. Adding to this list after a debugging session is highly encouraged.

1. **Prisma ORM & PostgreSQL for All Financial Data**
    * **System:** All financial data, including configuration (`RentConfig`) and historical calculations (`RentLedger`), is stored in PostgreSQL and managed via Prisma.
    * **Replaces:** This unified system replaces a legacy file-based approach that used SQLite for configuration and versioned JSON files (`data/rent_history/`) for calculation history.
    * **Rationale:**
        *   **Single Source of Truth:** Consolidates all data into one database, making it easier to manage and backup.
        *   **Queryability:** Allows for complex queries and data analysis that were impossible with the old system (e.g., historical trends).
        *   **Frontend Integration:** Auto-generated TypeScript types from Prisma provide type safety for frontend components like `<RentPanel/>` that consume financial data. The API for this is still Ruby.
        *   **Transactional Integrity:** Ensures that updates to rent data are atomic, reducing risks of corruption.

2. **Frontend-Backend Integration (`<RentPanel/>`)**
    *   **Proxy:** The Vite frontend server (`handbook/frontend`) is configured in `vite.config.ts` to proxy all requests from `/api` to the backend Ruby server running on port `3001`. This allows the frontend to make API calls to its own origin, simplifying development.
    *   **Data Flow:** The `<RentPanel/>` component fetches data from `/api/rent/history`. The backend `rent_calculator_handler` checks for saved data for the current month. If none exists, it calls `generate_rent_forecast` to create a new forecast on the fly, using historical data and defaults.
    *   **Key Learning (Data Structure):** The structure of the JSON object returned by the forecast method must exactly match the interface expected by the React component (`RentDetails`). A mismatch here (e.g., `Total` vs `total`) can cause silent failures where data appears as `0` or `null`.

3. **Historical Data Correction (`json_server.rb`)**
    *   **Problem:** The `Tenant` table in the database lacked accurate `startDate` and `departureDate` information, leading to incorrect filtering in the rent forecast.
    *   **Solution:** A `startDate` column was added via a Prisma migration. A one-time data correction script was added to `json_server.rb` to run on startup, ensuring that the database is always populated with the correct historical timeline for all tenants. This makes the system resilient to database resets during development.

4. **Ruby Hash Keys: String vs. Symbol**
    *   **Problem:** A recurring source of subtle bugs. The core `RentCalculator` logic often expects hashes with **symbol** keys (e.g., `:kallhyra`), while data parsed from JSON API requests has **string** keys. This can lead to default values not being overridden correctly.
    *   **Decision:** For any data structure passed from an external source (like an API handler) into core business logic, keys must be consistently transformed. Use `transform_keys(&:to_sym)` or be explicit when accessing values (e.g., `breakdown['Total']`).

5. **Frontend Dependencies & Environment**
    *   **React 19 & `react-facebook-login`:** The legacy `react-facebook-login` package is incompatible with React 19. It was replaced with the maintained `@greatsumini/react-facebook-login` fork.
    *   **Facebook SDK Initialization:** The error `FB.login() called before FB.init()` occurs when the Facebook SDK is not initialized with a valid App ID.
    *   **Solution:** The App ID must be provided via a `VITE_FACEBOOK_APP_ID` environment variable. For local development, this should be placed in an untracked `handbook/frontend/.env.local` file.

6. **Ruby `pg` Gem and `DATABASE_URL`**
    *   The Ruby `pg` gem does not support the `?schema=public` parameter in the `DATABASE_URL` string, which is often added by Prisma. This causes a `PG::Error: invalid URI query parameter` on connection. The parameter must be removed from the `.env` file for the Ruby backend to connect.

7. **Dockerised Postgres in dev, system Postgres in prod**
    *   Devs can `docker rm -f` to reset data; prod reuses existing DB server managed by `systemd`.

8. **Obsidian-Git pull-only**
    *   Prevents accidental direct commits that bypass approval workflow.