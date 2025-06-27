# TODO – BankBuster

### Milestone 0 – Bring the scraper to production readiness
- [ ] Replace hard-coded ENV defaults with sensible fallbacks & validation
- [ ] Parameterise screenshot folder in `.env`
- [ ] Improve error reporting (raise custom error classes instead of strings)
- [ ] Add retry logic for Ferrum dead-browser cases
- [ ] Clean up `puts`/`ap` logging → use a proper logger interface

### Milestone 1 – WebSocket dashboard
- [ ] Flesh out `handlers/bank_buster_handler.rb`
  - [ ] Accept `{action:"start", since:"2024-01-01"}` messages
  - [ ] Stream progress events (`type: 'LOG' | 'QR_UPDATE' | 'FILE' | 'COMPLETE'`)
- [ ] Front-end (Vue) additions
  - [ ] Progress console component
  - [ ] Live QR code display while waiting for Bank-ID
  - [ ] List newly downloaded files with status pills
- [ ] Secure endpoint with token in query (?auth=…)

### Milestone 2 – Parsing & persistence
- [ ] Finish `bank_payments_reader.rb` to output **JSON lines** per payment
- [ ] Save parsed payments into `payments.json` (append-only)
- [ ] Index by OCR/reference number for later invoice matching

### Milestone 3 – Tests & CI
- [ ] Replace brittle RSpec mocks with realistic fixtures
- [ ] Add GitHub Action: `bundle exec rspec`
- [ ] Add rubocop + lint step

### Milestone 4 – UX polish
- [ ] Cache login cookies so QR scan isn't needed every run
- [ ] CLI flag `--headful` to watch the browser when debugging
- [ ] Dark-mode theme for dashboard

### Nice-to-have backlog
- [ ] Convert scraper to Playwright-Ruby once stable
- [ ] Push finished camt.054 files to Google Drive backup
- [ ] E-mail alert if new payments appear but don't match invoices 