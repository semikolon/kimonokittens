# Billogram Rent Payment Automation Plan

**Status:** ⏳ DEFERRED - Resume end of December 2025
**Created:** November 27, 2025
**Priority:** Low (quality of life improvement, not urgent)

---

## Overview

Automate the monthly house rent payment to Bostadsagenturen (24,529 SEK) through Billogram, minimizing manual steps to just the required BankID authentication.

---

## Current Manual Process

1. Open Gmail on Mac or iPhone
2. Find email from "Bostadsagenturen i Stockholm ab" (via Billogram)
   - Subject: "Din faktura (faktura nr XXXX)"
   - Due date typically 27th of month
3. Click link in email (e.g., `https://billogram.com/l/yC3bqejwlgXz3gL3pK`)
4. On Billogram dashboard, see invoice summary (24,529 SEK)
5. Click "Till betalning" button
6. On payment page, click "Godkänn betalning" (Bank verification selected, Swedbank account)
7. Click "Mobilt BankID" (or "BankID på denna enhet" if on iPhone)
8. BankID app opens → Scan QR code (if on Mac) or auto-open (if on iPhone)
9. Click "Identify" in BankID app → Face ID authentication
10. Payment is scheduled (takes 1-2 bank days to process)

**Pain point:** Steps 1-7 are mechanical clicking that could be automated. Only step 9 (Face ID) is fundamentally required for security.

---

## Desired End State

**Ideal flow:**
1. System detects new invoice (email parsing, scheduled check, or Billogram API)
2. System sends SMS to Fredrik with a "magic link"
3. Click SMS link on iPhone
4. Automation navigates through Billogram, reaching BankID step
5. BankID app auto-opens on same device
6. Authenticate with Face ID
7. Done

**Minimal interaction:** Just click SMS link + Face ID authentication

---

## Architectural Options Identified

### Option 1: Server-side automation + QR scan
- Playwright/Ferrum runs on Dell/Mac server
- Navigates to BankID QR screen
- User scans QR with phone to authenticate
- **Con:** Still requires looking at QR somewhere (MMS? Web page?)

### Option 2: Server-side automation + deep link
- Automation extracts/constructs `bankid://` deep link
- Sends deep link via SMS
- User clicks, BankID app opens, authenticates
- **Con:** Need to poll Billogram to confirm completion

### Option 3: On-device automation (iOS Shortcuts?)
- iOS Shortcuts workflow on iPhone
- Opens Safari, navigates, clicks buttons via accessibility
- Hands off to BankID app
- **Con:** iOS automation capabilities are limited

### Option 4: Hybrid (PREFERRED)
- Server detects invoice, prepares everything
- Sends "magic link" that takes user directly to BankID step
- User authenticates
- Server confirms completion
- **Pro:** Minimal user interaction, clean handoff

---

## Research Plan (Deferred)

When resuming, spawn 3 parallel research subagents:

### A) Playwright Approach
- Browser automation via Playwright MCP
- How to handle session cookies, navigation
- Deep link extraction for BankID
- Pros/cons for this use case

### B) Ferrum/FerrumVCR Approach
- Leverage existing brf-auto Ferrum infrastructure
- FerrumVCR for testing without actual payments
- Integration with kimonokittens codebase
- Reference: `~/Projects/brf-auto` (Ferrum), BankBuster in this repo (older)

### C) Alternative Solutions
- Billogram API (if available)
- Email parsing + direct Billogram URL construction
- iOS Shortcuts integration
- Existing payment automation services
- Sweden-specific solutions (Autogiro, etc.)

### D) Meta-analysis
- Compare all approaches
- Map pros/cons matrix
- Recommend implementation path
- Consider maintenance burden

Each subagent saves research report to `docs/` for later synthesis.

---

## Technical Context

### Related Code in This Repo
- `lib/bank_buster.rb` - Older browser automation for bank scraping (may be outdated)
- `bin/bank_sync` - Lunchflow bank transaction sync (different use case but similar infra)

### Related Code in brf-auto
- Ferrum browser automation framework (production-tested)
- FerrumVCR for HTTP traffic recording/replay
- Much more recent and actively developed

### Invoice Details
- **Sender:** Bostadsagenturen i Stockholm ab (via Billogram)
- **Amount:** 24,529 SEK (incl. moms) - 24,500 kr base for Sördalavägen 26
- **Due date:** 27th of month
- **Payment method:** Bank verification via Swedbank
- **Authentication:** BankID (Face ID on iPhone)

---

## Screenshots Reference

Screenshots from November 13, 2025 invoice (faktura nr 9569):

1. **Gmail email** - Invoice notification with Billogram link
2. **Billogram dashboard** - Invoice overview (24,529 SEK, förfallodatum 27 november 2025)
3. **Payment page** - Bank verification options (Datum: 1 december 2025, Konto: Swedbank)
4. **BankID page** - Authentication options (Mobilt BankID / BankID på denna enhet)

---

## Notes

- BankID Face ID step **cannot** be automated (by design - security layer)
- Goal is to reduce ~10 manual steps to ~2 (click link + Face ID)
- Similar pattern to electricity bill automation but with payment instead of scraping
- Consider reusability for other Billogram invoices if Fredrik has any

---

## Resume Checklist (End of December 2025)

- [ ] Read this document to restore context
- [ ] Spawn research subagents A, B, C in parallel
- [ ] Wait for reports, then spawn D for synthesis
- [ ] Decide on implementation approach
- [ ] Implement MVP
- [ ] Test with January 2026 invoice
