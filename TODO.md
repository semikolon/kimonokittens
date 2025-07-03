- [Current Tasks](#current-tasks)
  - [General](#general)
  - [Documentation Maintenance](#documentation-maintenance)
  - [Rent History](#rent-history)
  - [Testing](#testing)
  - [Persistent Storage](#persistent-storage)
- [Future Enhancements](#future-enhancements)
  - [Rails Migration](#rails-migration)
  - [SMS Reminders and Swish Integration](#sms-reminders-and-swish-integration)
  - [Error Handling](#error-handling)
  - [Output Formats](#output-formats)
  - [Deposit Management](#deposit-management)
  - [One-time Fees](#one-time-fees)
  - [Automation](#automation)
  - [API Integration](#api-integration)

# Current Tasks

## General
- Always make sure documentation is up to date with usage and developer guidelines and background knowledge that might be important for future devs (TODO.md, README.md, inline comments, etc).

## Documentation Maintenance
- [ ] Keep track of special payment arrangements:
  - Who covers whose shares
  - When arrangements started/ended
  - Which costs are affected
- [ ] Document billing cycles clearly:
  - Relationship between consumption, billing, and rent months
  - How special cases are handled
  - Impact on rent calculations
- [ ] Maintain historical records:
  - Payment arrangements
  - Bill amounts and dates
  - Consumption patterns
  - Year-over-year trends

## Rent History
- [ ] Adjust example scripts to prevent overwriting existing files
- [ ] Separate test data from production/default data directories for rent history (make sure specs don't overwrite production data)

## Testing
- [x] Add integration tests:
  - [x] November 2024 scenario
  - [x] Error cases
  - [x] Friendly message format
- [x] Manual testing with real data

## Persistent Storage
- [ ] Add migration system for database schema changes
- [ ] Add backup/restore functionality for SQLite databases
- [ ] Add data validation and cleanup tools
- [ ] Add monitoring for database size and performance

# Future Enhancements

## Rails Migration
- [ ] Consider migrating to Rails when more features are needed:
  - ActiveRecord for better database management
  - Web dashboard for configuration
  - User authentication for roommates
  - Background jobs for automation
  - Better testing infrastructure
  - Email notifications and reminders
  - Mobile-friendly UI
- [ ] Keep architecture modular to facilitate future migration
- [ ] Document current data structures for smooth transition

## SMS Reminders and Swish Integration
- [ ] Implement automated rent reminders via SMS:
  - Generate personalized Swish payment links with correct amounts
  - Send monthly reminders with payment links
  - Manual confirmation system for payments
  - Update payment status in persistent storage
  - Track payment history
- [ ] Investigate Swish API access requirements:
  - Research requirements for företag/enskild firma
  - Evaluate costs and benefits
  - Explore automatic payment confirmation possibilities
  - Document findings for future implementation
- [ ] **JotForm AI Agent Integration**:
  - [ ] Set up JotForm AI Agent with SMS channel capabilities
  - [ ] Configure API tool to connect to the rent calculator API
  - [ ] Implement conversational scenarios:
    - Rent inquiries ("What's my rent?")
    - Updating quarterly invoices ("The quarterly invoice is 2612 kr")
    - Roommate changes ("Adam is moving in next month")
    - Payment confirmations ("I've paid my rent")
  - [ ] Test the integration with sample SMS conversations
  - [ ] Set up scheduled reminders for monthly rent payments
  - [ ] Monitor API availability and SMS delivery
  - [ ] Create documentation for roommates on how to interact with the SMS agent

## Error Handling
- [x] Improve error messages and recovery procedures:
  - [x] Invalid roommate data (negative days, etc.)
  - [x] Missing required costs
  - [x] File access/permission issues
  - [x] Version conflicts
- [x] Implement validation rules:
  - [x] Roommate count limits (3-4 recommended)
  - [x] Room adjustment limits (±2000kr)
  - [x] Stay duration validation
  - [x] Smart full-month handling
- [ ] Document common error scenarios:
  - Clear resolution steps
  - Prevention guidelines
  - Recovery procedures
  - User-friendly messages

## Output Formats
- [x] Support for Messenger-friendly output:
  - [x] Bold text formatting with asterisks
  - [x] Swedish month names
  - [x] Automatic due date calculation
  - [x] Concise yet friendly format
- [ ] Additional output formats:
  - [ ] HTML for web display
  - [ ] CSV for spreadsheet import
  - [ ] PDF for official records

## Deposit Management
- [ ] Track deposits and shared property:
  - Initial deposit (~6000 SEK per person)
  - Buy-in fee for shared items (~2000 SEK per person)
  - Shared items inventory:
    - Plants, pillows, blankets
    - Mesh wifi system
    - Kitchen equipment
    - Common area items
  - Condition tracking:
    - House condition (floors, bathrooms, kitchen)
    - Plant health and maintenance
    - Furniture and equipment status
    - Photos and condition reports
  - Value calculations:
    - Depreciation over time
    - Fair deduction rules
    - Return amount calculations
    - Guidelines for wear vs damage

## One-time Fees
- [ ] Support for special cases:
  - Security deposits (handling, tracking, returns)
  - Maintenance costs (fair distribution)
  - Special purchases (shared items)
  - Utility setup fees (internet, electricity)
- [ ] Design fair distribution rules:
  - Based on length of stay
  - Based on usage/benefit
  - Handling early departures
  - Partial reimbursements

## Automation
- [ ] Automate electricity bill retrieval:
  - Scrape from supplier websites (Vattenfall, etc.)
  - Update monthly costs automatically
  - Store historical electricity usage data
  - Alert on unusual changes in consumption

## API Integration
- [x] Expose rent calculator as API for voice/LLM assistants:
  - [x] Natural language interface for rent queries
  - [x] Voice assistant integration (e.g., "Hey Google, what's my rent this month?")
  - [x] Ability for roommate-specific queries
  - [x] Historical rent lookup capabilities
- [x] Persistent storage for configuration:
  - [x] Base costs and monthly fees
  - [x] Quarterly invoice tracking
  - [x] Previous balance management
- [x] Persistent storage for roommates:
  - [x] Current roommate tracking
  - [x] Move-in/out dates
  - [x] Room adjustments
  - [x] Temporary stays
- [ ] **JotForm AI Integration**:
  - [ ] Ensure API is properly exposed with HTTPS and authentication
  - [ ] Optimize friendly_message format specifically for SMS
  - [ ] Add error handling for API timeouts and connection issues
  - [ ] Implement logging for JotForm API requests for debugging
  - [ ] Create OpenAPI documentation specifically for JotForm integration
