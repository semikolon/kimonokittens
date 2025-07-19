# Accomplishments & Historical Milestones

This file tracks major completed tasks and project milestones.

---

### February 2025

*   **Finalized and documented the February 2025 rent calculations after extensive scenario modeling.**

### July 2025

*   **Dashboard/Server Stabilization and Handler Resilience**
    *   Added aggressive timeouts and fallback data to all external API handlers (SL, Strava, Node-RED)
    *   Fully disabled BankBuster handler to prevent accidental server exit
    *   Normalized all JSON keys to strings for frontend compatibility
    *   SL API currently returns fallback data due to missing accessId
    *   All endpoints now fail fast and dashboard remains responsive

*   **Dashboard Stabilization and Key Bugfixes (July 9, 2025)**
    *   **Context:** Persistent WebSocket 500 errors, segfaults, train API failures, and weather widget runtime errors due to symbol keys.
    *   **Action:** Fixed Agoo handler to use status 101 and con_id, migrated train API to fallback, fixed weather widget to handle symbol keys, and ensured all widgets degrade gracefully.
    *   **Outcome:** Dashboard is now fully stable and error-free. See DEVELOPMENT.md for canonical details.

*   **WebSocket/Agoo integration stabilized (July 9, 2025)**
    *   **Context:** Persistent 500 errors on WebSocket upgrades due to incorrect Rack status code (0 instead of 101).
    *   **Action:** Fixed the handler to return `[101, {}, []]` for upgrades, as required by Agoo+Rack. See DEVELOPMENT.md for details.
    *   **Outcome:** Real-time updates are now stable and working. Canonical reference is now in DEVELOPMENT.md.

*   **Reconstructed and Stabilized the `RentCalculator` Module (July 4, 2025)**
    *   **Context:** A critical `rent.rb` file containing all business logic was accidentally deleted due to being untracked in git.
    *   **Action:** The module was successfully reconstructed from scratch by using the existing RSpec test suite as a guide for the required behavior.
    - **Outcome:** All 53 tests for the `RentCalculator` and `RentHistory` systems are now passing. Key bugs related to key symbolization, float vs. integer rounding, remainder distribution, and presentation logic were identified and fixed. The system is now stable.
    *   **Key Learning:** This event underscored the value of a comprehensive test suite and the importance of committing all work, even if incomplete. Technical learnings from this process have been documented in `DEVELOPMENT.md`.

*   **Migrated the core `RentCalculator` backend from a legacy file-based system (SQLite and versioned JSON files) to a unified PostgreSQL database managed by Prisma. This involved a significant refactoring of the API handler and a complete rewrite of the integration test suite to be database-driven.**

*   **Implemented the `<RentPanel/>` UI and Backend Forecasting (July 5, 2025)**
    *   **Context:** The application needed a primary user interface to display rent calculations and forecasts.
    *   **Action:** Developed a new React component (`<RentPanel/>`) to show a detailed rent breakdown. The backend was enhanced to generate on-the-fly forecasts for future months. A data correction script was created to populate historical tenant start and departure dates, ensuring forecast accuracy.
    *   **Outcome:** The application now has a functional UI for viewing rent data. Numerous frontend (React/Vite) and backend (Ruby/Postgres) integration bugs were resolved, including data type mismatches, key inconsistencies, and environment configuration issues. 

*   **Implemented Real-Time Updates for the Rent Panel (July 5, 2025)**
    *   **Context:** The `<RentPanel/>` needed to reflect database changes instantly without requiring a manual page refresh.
    *   **Action:** A full-stack WebSocket system was implemented. The Ruby backend now broadcasts a `rent_data_updated` message whenever financial data is changed. The React frontend listens for this message and automatically reloads the page.
    *   **Outcome:** The user experience is now seamless and reactive. All API and WebSocket proxy issues in the Vite development environment were resolved, and the backend server was stabilized by fixing several gem dependency conflicts. 

*   **Systematic Server Crash Root Cause Analysis - Critical Discovery**
    *   Conducted methodical testing: individual endpoints, simultaneous requests, frontend simulation, repeated cycles, stress testing
    *   **Server demonstrated complete stability under all realistic load conditions**
    *   Definitively proved crashes were NOT caused by external API calls, startup issues, or frontend request patterns
    *   **Root cause confirmed: BankBuster handler mis-registration (already fixed)**
    *   Server ran continuously throughout all test phases without any segmentation faults
    *   Previous timeout fixes were valuable defensive programming but addressed symptoms, not the actual cause 