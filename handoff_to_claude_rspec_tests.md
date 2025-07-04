# Handoff Plan: RSpec Coverage for Core Ruby Code

**To:** Claude Assistant
**From:** Gemini Assistant
**Date:** July 4, 2025
**Subject:** Test Plan for Kimonokittens Ruby Scripts & API Handlers

## 1. Goal

The primary objective is to achieve comprehensive RSpec test coverage for the core Ruby logic and API handlers in the `kimonokittens` repository. The existing test suite (in `spec/`) has good coverage for the `RentCalculator` logic and the `HandbookHandler`, but several critical API handlers and standalone scripts remain untested.

This document outlines the scope of work, testing strategy, and specific requirements for each component.

## 2. Technical Environment & Style Guide

*   **Framework:** RSpec
*   **HTTP Mocking:** Use `rack-test` for simulating requests to the Agoo server handlers. The existing `spec/handbook_handler_spec.rb` and `spec/rent_calculator/integration_spec.rb` are excellent reference examples.
*   **Dependencies:** All gems are managed via `bundler`. Run `bundle install` before starting.
*   **File Structure:** New specs for handlers should be placed in a new `spec/handlers/` directory.
*   **Execution:** Run the full suite with `bundle exec rspec`.

## 3. Scope of Work: Untested Components

The following handlers and scripts require complete RSpec test suites.

### 3.1. API Handlers (`handlers/`)

A new directory `spec/handlers/` should be created to house these tests.

*   [ ] `auth_handler.rb`
*   [ ] `electricity_stats_handler.rb`
*   [ ] `home_page_handler.rb`
*   [ ] `proxy_handler.rb`
*   [ ] `rent_calculator_handler.rb`
*   [ ] `static_handler.rb`
*   [ ] `strava_workouts_handler.rb`
*   [ ] `train_departure_handler.rb`
*   [ ] `bank_buster_handler.rb` (Note: This is a WebSocket handler, which may require a different testing approach, possibly with a mock WebSocket client).

### 3.2. Core Scripts (Root Directory)

*   [ ] `vattenfall.rb`
*   [ ] `tibber.rb`

## 4. Detailed Testing Requirements

### 4.1. General Handler Tests

For every handler, ensure:
*   The response has a `200 OK` status for valid requests.
*   The `Content-Type` header is correct (e.g., `application/json; charset=utf-8` or `text/html`).
*   It gracefully handles invalid paths within its scope (e.g., `/api/rent/invalid_endpoint` should return a `404`).

### 4.2. Specific Scenarios

#### `spec/handlers/rent_calculator_handler_spec.rb`
This is the highest priority.
*   **POST /api/rent/calculate:**
    *   Test with a valid JSON body, ensuring it returns a `200` status and a correctly structured JSON response containing the rent breakdown.
    *   Test with an invalid/incomplete body, ensuring it returns a `400 Bad Request` or other appropriate error code.
*   **GET /api/rent/history:**
    *   Test that it returns a JSON array of past rent calculations. Mock the underlying `RentHistory.load_all` method.
*   **GET & PATCH /api/rent/config:**
    *   Test that `GET` returns the current configuration.
    *   Test that `PATCH` with a valid body updates the configuration. Mock the `ConfigStore`.
    *   Test that `PATCH` with an invalid body returns an error.
*   **GET & POST /api/rent/roommates:**
    *   Test that `GET` returns the list of roommates.
    *   Test that `POST` successfully adds/updates a roommate. Mock the `RoommateStore`.
    *   Test validation rules (e.g., trying to add a roommate with invalid data).

#### `spec/handlers/electricity_stats_handler_spec.rb`
*   Mock the reading of `data/archive/electricity_usage.json` and `data/archive/tibber_price_data.json` to provide consistent test data.
*   Verify that the JSON response contains the expected keys (`average_price`, `total_consumption`, `total_cost`, etc.) and that the calculations are correct based on the mock data.

#### `spec/handlers/strava_workouts_handler_spec.rb`
*   Use `Faraday::Adapter::Test` to stub the external API call to Strava.
*   Test the success case where the API returns valid data, and ensure the handler parses it correctly.
*   Test the failure case where the Strava API returns an error (e.g., 500 or 401), and ensure the handler responds gracefully.

#### `spec/handlers/auth_handler.rb`
*   This is complex and involves mocking the Facebook OAuth2 flow.
*   Focus on testing the `do_GET` method for the `/auth/facebook/callback` path.
*   Mock the session object.
*   Mock the return value from the OAuth library to simulate a successful authentication, and verify that the user is correctly redirected.
*   Simulate a failure/denial from the OAuth provider and verify the error handling.

#### `spec/scripts/data_fetcher_scripts_spec.rb`
*   Create a single spec file for `vattenfall.rb` and `tibber.rb`.
*   The main goal is to test their parsing logic, not the network request itself.
*   Create sample raw HTML/JSON files in `spec/data/` that mimic the real responses from Vattenfall/Tibber.
*   In the tests, stub `Faraday.get` to return the content of these local sample files.
*   Verify that the scripts correctly parse these sample files and write the expected JSON output.

## 5. Final Deliverable

A set of new spec files in `spec/handlers/` and `spec/scripts/` that provide robust test coverage for all the components listed in the scope of work. All new and existing tests must pass when running `bundle exec rspec`. 