# Kimonokittens Development Guide

This document contains technical implementation details, patterns, and guidelines for contributors working on the Kimonokittens monorepo.

---

## 1. System Architecture

The project is built around a unified architecture designed for real-time updates and future AI integration.

*   **React Frontend (`handbook/frontend`)**: A user interface for displaying financial data (e.g., `<RentPanel/>`) and allowing for administrative changes.
*   **Ruby API (`handlers/*`)**: The primary API for all rent-related operations. It contains the core calculation logic and is responsible for interacting with the database.
*   **PostgreSQL Database with Prisma**:
    *   **Database**: PostgreSQL is the authoritative datastore for all financial records, configuration, and tenant information.
    *   **Schema**: The database schema is managed by Prisma in `handbook/prisma/schema.prisma`.
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
    -   A remainder-distribution step ensures the sum of the rounded amounts exactly equals the total cost to be paid.
    -   **Crucial Learning**: The remainder is distributed one öre at a time to the roommates with the largest fractional part in their un-rounded rent.

## 4. Data Persistence & Migrations

All persistent data for the rent system is stored in a PostgreSQL database, managed by Prisma. This replaces the previous system of JSON files and SQLite databases.

*   **Schema Source of Truth**: `handbook/prisma/schema.prisma` is the canonical source for all data models (`Tenant`, `RentLedger`, etc.).
*   **Migrations**: Database schema changes are managed via `npx prisma migrate dev`.
*   **Historical Data Correction**: A one-time data correction script runs on server startup in `json_server.rb` to ensure the `Tenant` table is always populated with the correct historical timeline.

## 5. Key Technical Decisions & Learnings

This section summarizes non-obvious architectural choices and important lessons from recent development.

1.  **API Route Registration**: A critical bug was caused by a missing route definition in `json_server.rb`. Although logic existed in the handler, the server returned a 404 because the route was not registered. **All API endpoints must be explicitly handled.**
2.  **Vite Proxy for Backend APIs**: The frontend dev server (`vite.config.ts`) must be configured to proxy both standard API calls (`/api`) and WebSocket connections (`/handbook/ws`) to the backend Ruby server to work in a local development environment.
3.  **Data Structure Consistency (Frontend/Backend)**: The structure of JSON objects returned by the API must exactly match the TypeScript interfaces expected by React components. A mismatch (e.g., `Total` vs `total`) can cause silent failures where data appears as `0` or `null`.
4.  **Ruby Hash Keys: String vs. Symbol**: A recurring source of subtle bugs. For any data passed from an external source (like an API handler) into core business logic, keys must be consistently transformed to symbols using `transform_keys(&:to_sym)`.
5.  **Database Cleaning for Tests**: When using `TRUNCATE` to clean a PostgreSQL database between RSpec tests, the `TRUNCATE TABLE "MyTable" RESTART IDENTITY CASCADE;` command is essential to handle foreign key constraints correctly.
6.  **Drift Calculation**: When a quarterly invoice (`drift_rakning`) is present, it **replaces** the standard monthly fees (`vattenavgift`, `va`, `larm`).
7.  **Prorated Room Adjustments**: Room adjustments are always prorated based on the number of days a person stays during the month.

---
*For more detailed implementation guides, older decisions, and specific business logic (like electricity bill handling), please refer to the Git history and the source code itself.*
