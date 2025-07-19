# Kimonokittens Development Guide

This document contains technical implementation details, patterns, and guidelines for contributors working on the Kimonokittens monorepo.

---

## 1. System Architecture

The project is built around a unified architecture designed for real-time updates and future AI integration.

*   **React Frontend (`handbook/frontend`)**: A user interface for displaying financial data (e.g., `<RentPanel/>`) and allowing for administrative changes.
*   **Ruby API (`handlers/*`)**: The primary API for all rent-related operations. It contains the core calculation logic and is responsible for interacting with the database.
*   **PostgreSQL Database with Prisma**:
    *   **Database**: PostgreSQL is the authoritative datastore for all financial records, configuration, and tenant information.
    *   **Schema**: The database schema is managed by Prisma in `handbook/prisma/schema.prisma`. This provides a single source of truth for our data models (`Tenant`, `RentLedger`, etc.).
    *   **Client**: Prisma generates a type-safe JavaScript/TypeScript client, used by the frontend build process and any future Node.js scripts.
*   **Real-time Updates via WebSockets**: The system uses WebSockets to push updates to the frontend whenever data changes in the backend.
    *   **Server**: The Agoo server (`json_server.rb`) hosts a WebSocket endpoint at `/handbook/ws`.
    *   **Frontend**: The frontend uses `react-use-websocket` to listen for update messages (`rent_data_updated`) and automatically reloads the page.

## 2. AI-Powered Data Interaction (In Progress)

To allow for natural language updates to our financial data, we are integrating an LLM into the `QueryInterface`.

*   **Goal**: Enable users to type commands like "Set the electricity cost for July to 1800 kr" and have the system execute the corresponding API call.
*   **Mechanism**:
    1.  The `QueryInterface.tsx` component will send the user's prompt to a new `/api/ai` endpoint.
    2.  This endpoint will be handled by a new Ruby handler (`handlers/ai_handler.rb`).
    3.  The handler will provide the `RentCalculator` API (its endpoints and schemas) as a "tool" to an LLM (e.g., GPT-4o).
    4.  The LLM will determine which API endpoint to call and with what parameters, based on the user's prompt.
    5.  The Ruby handler will execute the tool call and return the result to the user.

## 3. Core Logic: Rent Calculation

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

## 4. Data Persistence & Migrations

All persistent data for the rent system is stored in a PostgreSQL database, managed by Prisma. This replaces the previous system of JSON files (`RentHistory`) and SQLite databases (`ConfigStore`, `RoommateStore`).

*   **Schema Source of Truth**: `handbook/prisma/schema.prisma` is the canonical source for all data models (`Tenant`, `RentLedger`, etc.).
*   **Primary Models**:
    *   `Tenant`: Stores information about current and past roommates.
    *   `RentLedger`: The central table for financial records. Each row represents a specific charge or payment for a tenant for a given period, replacing the old `RentHistory` JSON files.
*   **Migrations**: Database schema changes are managed through Prisma Migrate. To create a new migration after editing the schema, run `npx prisma migrate dev --name <migration-name>`.
*   **Historical Data Correction**: A one-time data correction script runs on server startup in `json_server.rb` to ensure the `Tenant` table is always populated with the correct historical timeline.
*   **Data Access**:
    *   The **Ruby API** will interact with the database directly, likely using the `pg` gem.
    *   The **React frontend** and other Node.js tools can use the type-safe Prisma Client for data access.

## 5. Validation Rules and Safety Checks

The system includes several validation rules to prevent common errors and ensure data consistency. These are conceptual guards and may not all be implemented as explicit code checks yet.

*   **Roommate Count**: The system should ideally warn if the total number of roommates falls outside the 3-4 person range, as this affects the financial viability of the household.
*   **Room Adjustments**: Large adjustments (e.g., > ±2000 SEK) should require explicit confirmation. Adjustments are always prorated based on the number of days a person stays during the month.
*   **Stay Duration**: The number of days for a partial stay cannot exceed the number of days in the given month.
*   **Data Consistency**: The calculator requires a minimum set of costs (`kallhyra`, `el`, `bredband`) to produce a valid result.

## 6. Specific Business Logic

### Electricity Bill Handling

The system is designed to handle a specific billing cycle for electricity costs:

*   **Normal Flow**: Bills for a given month's consumption (e.g., January) typically arrive in the following month (February). These costs are then included in the rent calculation for the month after that (March), which is due at the end of February.
*   **Timeline Example**:
    1.  **January**: Electricity is consumed.
    2.  **Early February**: Bills for January's consumption arrive.
    3.  **Late February**: The January electricity costs are included in the **March rent calculation**.
    4.  **Feb 27**: March rent is due, covering January's electricity costs.
*   **Special Cases**: If a bill needs to be paid separately (e.g., it's overdue), the `el` cost for that period should be set to `0` in the next rent calculation to avoid double-charging. The special payment arrangement (e.g., Fredrik covering multiple shares) is noted in `docs/electricity_costs.md`.

## 7. API and Usage Examples

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

## 8. Output Formats

The calculator produces two primary outputs:

1.  **Detailed Breakdown**: A hash containing a full breakdown of all costs, weights, and the final rent per roommate. This is used for record-keeping in `RentHistory` and for detailed verification.
2.  **Friendly Message**: A concise, Markdown-formatted string suitable for sharing in a group chat (e.g., Facebook Messenger). It provides a clear summary of who pays what and when it's due.

## 9. Testing Considerations

See also: [handoff_to_claude_rspec_tests.md](handoff_to_claude_rspec_tests.md) for the original RSpec/spec coverage plan. Most handler specs are now in place, but new handler logic (timeouts/fallbacks) and frontend widget tests are still missing and should be tracked in TODO.md.

1.  **Floating Point Precision**: Use RSpec's `be_within(0.01).of(expected)` for comparing floating-point numbers. Direct equality checks (`eq`) will often fail due to precision limits.
2.  **Test Data Organization**: Use simple, round numbers (e.g., total rent of 10,000) for basic unit tests and real-world data (like the complex November 2024 scenario) for integration tests to catch nuanced edge cases.
3.  **Database Test Cleaning**: When using `TRUNCATE` to clean a PostgreSQL database between tests, foreign key constraints will cause errors. The `TRUNCATE TABLE "MyTable" RESTART IDENTITY CASCADE;` command is essential. `CASCADE` ensures that any tables with a foreign key reference to `"MyTable"` are also truncated, which is necessary when dealing with Prisma's relational tables (e.g., `_ItemOwners`).

## 10. Common Gotchas

1.  **Drift Calculation**: When a quarterly invoice (`drift_rakning`) is present for a month, it **replaces** the standard monthly fees (`vattenavgift`, `va`, `larm`). The monthly fees are only used if `drift_rakning` is zero or not present.
2.  **Room Adjustments**: Remember that adjustments are prorated. A -1000 SEK adjustment for someone staying half the month will only result in a -500 SEK reduction in their final rent.
3.  **Data Persistence**: Use versioning in `RentHistory` to track significant changes or different scenarios for a single month.
4.  **Script-based testing**: The `if __FILE__ == $0` block at the end of `rent.rb` is useful for quick, manual testing. However, any logic or scenario tested there should ideally be moved into a proper RSpec integration test to ensure it runs as part of the automated suite.

## 11. Key Technical Decisions & Learnings

This section summarizes non-obvious architectural choices and important lessons from recent development.

### System Architecture Decisions

1.  **Prisma ORM & PostgreSQL for All Financial Data**
    * **System:** All financial data, including configuration (`RentConfig`) and historical calculations (`RentLedger`), is stored in PostgreSQL and managed via Prisma.
    * **Replaces:** This unified system replaces a legacy file-based approach that used SQLite for configuration and versioned JSON files (`data/rent_history/`) for calculation history.
    * **Rationale:**
        *   **Single Source of Truth:** Consolidates all data into one database, making it easier to manage and backup.
        *   **Queryability:** Allows for complex queries and data analysis that were impossible with the old system (e.g., historical trends).
        *   **Frontend Integration:** Auto-generated TypeScript types from Prisma provide type safety for frontend components like `<RentPanel/>` that consume financial data. The API for this is still Ruby.
        *   **Transactional Integrity:** Ensures that updates to rent data are atomic, reducing risks of corruption.

2.  **API Route Registration**: A critical bug was caused by a missing route definition in `json_server.rb`. Although logic existed in the handler, the server returned a 404 because the route was not registered. **All API endpoints must be explicitly handled.**

3.  **Vite Proxy for Backend APIs**: The frontend dev server (`vite.config.ts`) must be configured to proxy both standard API calls (`/api`) and WebSocket connections (`/handbook/ws`) to the backend Ruby server to work in a local development environment.

### Data Handling & Integration

4.  **Data Structure Consistency (Frontend/Backend)**: The structure of JSON objects returned by the API must exactly match the TypeScript interfaces expected by React components. A mismatch (e.g., `Total` vs `total`) can cause silent failures where data appears as `0` or `null`.

5.  **Ruby Hash Keys: String vs. Symbol**: A recurring source of subtle bugs. For any data passed from an external source (like an API handler) into core business logic, keys must be consistently transformed to symbols using `transform_keys(&:to_sym)`.

6.  **Historical Data Correction (`json_server.rb`)**
    *   **Problem:** The `Tenant` table in the database lacked accurate `startDate` and `departureDate` information, leading to incorrect filtering in the rent forecast.
    *   **Solution:** A `startDate` column was added via a Prisma migration. A one-time data correction script was added to `json_server.rb` to run on startup, ensuring that the database is always populated with the correct historical timeline for all tenants. This makes the system resilient to database resets during development.

### Database & Environment

7.  **Database Cleaning for Tests**: When using `TRUNCATE` to clean a PostgreSQL database between RSpec tests, the `TRUNCATE TABLE "MyTable" RESTART IDENTITY CASCADE;` command is essential to handle foreign key constraints correctly.

8.  **Ruby `pg` Gem and `DATABASE_URL`**
    *   The Ruby `pg` gem does not support the `?schema=public` parameter in the `DATABASE_URL` string, which is often added by Prisma. This causes a `PG::Error: invalid URI query parameter` on connection. The parameter must be removed from the `.env` file for the Ruby backend to connect.

9.  **Frontend Dependencies & Environment**
    *   **React 19 & `react-facebook-login`:** The legacy `react-facebook-login` package is incompatible with React 19. It was replaced with the maintained `@greatsumini/react-facebook-login` fork.
    *   **Facebook SDK Initialization:** The error `FB.login() called before FB.init()` occurs when the Facebook SDK is not initialized with a valid App ID.
    *   **Solution:** The App ID must be provided via a `VITE_FACEBOOK_APP_ID` environment variable. For local development, this should be placed in an untracked `handbook/frontend/.env.local` file.

### Recent Learnings (July 2025)

10.  **Value of a Robust Test Suite**: The comprehensive RSpec suite was indispensable for correctly reconstructing the lost business logic. It served as executable documentation and prevented regressions.

11.  **Handling Key Types**: A recurring source of bugs was the mismatch between `String` and `Symbol` keys in hashes, especially after JSON serialization/deserialization.
    *   **Decision**: For any data structure intended for presentation or external storage (like the output of `rent_breakdown` or `RentHistory`), we will standardize on **string keys** to avoid ambiguity. Internal calculation hashes can continue to use symbols for performance.

12.  **Importance of Committing Untracked Files**: The original loss of the `rent.rb` file was due to it being untracked (`.gitignore`) and overwritten during a merge. This highlights the need to commit even work-in-progress code to a feature branch.

13.  **Clarity over cleverness**: The original `calculate_rent` tried to do too much. It now has a single responsibility: calculate the final, unrounded amounts per roommate. The separate `rent_breakdown` method handles rounding and formatting for presentation.

### WebSocket/Agoo Integration (July 2025)

- **Agoo WebSocket handler must return `[101, {}, []]` for upgrades.** Returning `[0, {}, []]` causes a 500 error due to invalid Rack status code. See: https://github.com/ohler55/agoo/issues/216
- **Set `env['rack.upgrade'] = self.class`** (or `self`) in the handler. Do not manually hijack IO or use Upgraded.new for this pattern.
- **Use `con_id` as the only stable identifier** for WebSocket clients in PubSub. Do not use `client.hash`.
- The Vite dev server must proxy `/handbook/ws` to the backend for local dev.
- The previous handoff doc is now obsolete; this section is the canonical reference for Agoo+WebSocket integration.

---

## July 2025: Key Learnings and Recent Fixes

- **Agoo WebSocket handler must return `[101, {}, []]` for upgrades and use `con_id` for client tracking.** Returning `[0, {}, []]` or using `client.hash` causes 500 errors and instability. See this doc for canonical details; the old handoff doc is now obsolete.
- **Symbol vs. String Key Bugs:** Ruby APIs returning symbol keys (e.g., `:forecastday`) to JS/TS frontends cause subtle runtime errors. Always normalize to string keys or transform in the frontend.
- **Train/Weather API Fallbacks:** When external APIs fail (e.g., SL/ResRobot, WeatherAPI), provide realistic fallback/mock data to keep the dashboard functional and user-friendly.
- **Test Suite Value:** The RSpec and Vitest suites were critical for safely refactoring and reconstructing lost or broken logic. All new features and bugfixes should be covered by specs.
- **Obsolete Docs:** The handoff_to_claude_websocket_stabilization.md file is now obsolete; this DEVELOPMENT.md is the canonical reference for all recent architectural and technical decisions.

---

*For more detailed implementation guides, older decisions, and specific business logic (like electricity bill handling), please refer to the Git history and the source code itself.*

## Handler/Server Stability: Timeouts, Fallbacks, and BankBuster Gotchas

Recent experience revealed two distinct server failure modes:
- If the BankBuster handler is half-disabled (route registered but constant undefined), Agoo will exit immediately on startup. Always comment out both the require and the route.
- If any handler makes a blocking Faraday call (e.g., to SL or Strava) and the server is single-threaded (Agoo default), the entire server can freeze until the call times out. 

**Solution:**
- All Faraday calls to external APIs must set both `open_timeout` and `timeout` (typically 2s/3s), and rescue errors to provide fallback data.
- SL API is currently returning fallback data due to missing accessId (see TODO.md for next steps).

**See also:**
- The canonical plan for the upcoming Git-backed proposal/approval workflow is in `handoff_to_claude_git_proposal_workflow.md`.
- All handler/server stability patterns are now documented here.
