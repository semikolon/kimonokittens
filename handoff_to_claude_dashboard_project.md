---
**LEGACY: This document is superseded by DEVELOPMENT.md. See DEVELOPMENT.md for canonical dashboard implementation details.**
---

# Handoff to Claude: Kimonokittens Hallway Dashboard Project

> **Status (as of July 9, 2025):** This document is partially historical. The dashboard is fully implemented and stabilized. For the latest technical details, see DEVELOPMENT.md. Retained for project vision, phased plan, and context.

## 1. Project Goal

The primary objective is to build a new, modern, real-time hallway information dashboard for the Kimonokittens collective. This dashboard will replace an old, defunct Dakboard setup and will run on a large, ultra-widescreen monitor mounted in the hallway. It should serve as a central hub for at-a-glance information, house-related tasks, and personal stats, with a clean, "no-boxes" aesthetic.

The project involves frontend development, backend API endpoint creation/modification, and careful integration with existing house infrastructure (Agoo server, Node-RED, etc.).

## 2. Core Decisions & Tech Stack

-   **Frontend Framework:** React with Vite. This was chosen for component reusability with the existing `handbook` project.
-   **Styling:** Tailwind CSS for utility-first styling.
-   **Animations:** Framer Motion for UI animations, including a "fireworks/sparks" effect for chore completions.
-   **Backend:** The existing Ruby Agoo server (`json_server.rb`) will be extended to provide data.
-   **Real-time:** WebSockets, using the same pattern as the `handbook` project, for pushing live updates to the dashboard.

## 3. Project & Monorepo Structure

This project will be set up as a monorepo to facilitate code sharing.

-   **Root `package.json`:** Has been configured with `workspaces`.
-   **New Dashboard App:** A new React application will be created in the `/dashboard` directory.
-   **Shared UI Library:** A new shared component library will be created in `/packages/ui`. Both the `dashboard` and `handbook/frontend` apps will consume components from here.

## 4. UI/UX Vision & Design Guidelines

-   **Layout:** A three-column grid layout designed for an ultra-widescreen display.
    -   **Left Column ("At a Glance"):** Weather, Clock, Train Departures, Indoor Sensors.
    -   **Center Column ("The Vibe"):** The main Kimonokittens logo/image, announcements, and celebration animations.
    -   **Right Column ("Our Life"):** To-Do List, Calendar, Personal Stats.
-   **Aesthetics:**
    -   **Background:** A very dark, stormy purple/blue.
    -   **Widgets:** Content should appear to "float". **Avoid borders, boxes, or cards.** Use typography, spacing, and iconography to delineate widgets.
-   **Logo:** The main Kimonokittens logo from the `www/` directory should be the default centerpiece.

## 5. Detailed Implementation Plan (Actionable TODOs)

This plan corresponds to the detailed TODO list.

### Phase 1: Foundation & Static Widgets

1.  **Bootstrap App:** Create the React + Vite project in `/dashboard`.
2.  **Setup Shared UI:** Create the `/packages/ui` directory with a `package.json`.
3.  **Implement Layout:** Build the 3-column, full-screen CSS grid layout with the specified dark background.
4.  **Create Clock Widget:** A simple, large digital clock and date display. This requires no backend integration.
5.  **Create Logo Widget:** Display the static Kimonokittens logo in the center column.

### Phase 2: Integrating Existing Endpoints

6.  **WebSocket Client:** Implement the WebSocket client in the dashboard app to connect to the Agoo server, mirroring the `handbook`'s implementation.
7.  **Indoor Sensors Widget:** Fetch data from the existing `/data/temperature` endpoint (proxied to Node-RED). Display various sensor readings as seen on the old dashboard.
8.  **Train Departures Widget:** Fetch data from the `train_departure_handler`. Display upcoming departures. **Note:** The user mentioned the SL API might have changed; this integration needs to be verified.
9.  **Strava Widget:** Fetch data from the `strava_workouts_handler` and display the "Fredriks Löpning" stats.

### Phase 3: New Backend Endpoints & Integrations

10. **Weather Widget:**
    -   **Backend:** Create a new handler in Agoo to fetch data from a weather API. The recommended service is [WeatherAPI.com](https://www.weatherapi.com/) (requires a free API key).
    -   **Frontend:** Build the widget to display current weather, a 3-5 day forecast, and other data points (sunrise/sunset, wind) as seen in the old screenshots.
11. **Todoist Widget:**
    -   **Backend:** Create a new handler in Agoo to fetch tasks from the Todoist API for the shared house account/project.
    -   **Frontend:** Display the list of chores.
12. **Google Calendar Widget:**
    -   **Backend:** Create a new handler in Agoo to fetch events from the shared house Google Calendar.
    -   **Frontend:** Display a list of upcoming events.

### Phase 4: Polish & Advanced Features

13. **Chore Celebration Animation:** Implement a Framer Motion animation (fireworks/sparks) that is triggered by a WebSocket event from the backend when a chore is marked as complete.

## 6. Known Issues & Important Considerations

-   **WebSocket Stability:** The Vite dev server logs for the `handbook` show repeated `ECONNRESET` errors. This should be investigated to ensure the dashboard's real-time connection is stable. The proxy setup in `vite.config.ts` for the handbook is likely the place to look.
-   **Server Migration:** The plan to migrate all house services from the Raspberry Pi to a Dell server is documented in `docs/server_migration.md`. This is a critical parallel effort that will impact the base URLs and IPs used for services like Node-RED.
-   **API Keys & Credentials:** The backend handlers for Weather, Todoist, Google Calendar, SL, and Strava will all require API keys/credentials, which should be managed via the project's `.env` file.

This plan should provide Claude with all the necessary context to take over the project. The next immediate step is to execute Phase 1. 