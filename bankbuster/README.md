# BankBuster

Automated retrieval and parsing of Bankgirot **camt.054** payment reports.

• Logs in to Internetbanken Business with Bank-ID (QR flow)
• Downloads missing XML reports that match `ENV["PAYMENT_FILENAME_PATTERN"]`
• Saves them into `transactions/` and parses payments via `bank_payments_reader.rb`
• Exposes a WebSocket endpoint so a front-end dashboard can show live progress.

_Current status_: core scraper (`bank_buster.rb`) works from CLI; WebSocket handler is stubbed.

---

## Folder layout
```
bankbuster/
  README.md              ← this file
  TODO.md                ← backlog / next steps
  bankbuster-frontend/   ← Vue 3 Tailwind app (built → dist/)
  handlers/
    bank_buster_handler.rb  ← Agoo WebSocket handler
  bank_buster.rb          ← main scraper class (uses Vessel + Ferrum)
  bank_payments_reader.rb ← XML → JSON parser
  spec/                   ← RSpec tests (need love)
```

## How it works
1. `BankBuster#parse` spins up a headless Chromium (Ferrum).
2. Filters out images/fonts, accepts cookies, fills SSN, waits for QR.
3. Once Bank-ID auth succeeds, hits `/app/ib/dokument` API to list docs.
4. Downloads any camt.054 report not already on disk.
5. Parses each file with `BankPaymentsReader` and yields progress events.

## Local run
```bash
# prerequisites: Chrome lib deps, Ruby 3, yarn
cp .env.example .env   # set BANK_* vars & ADMIN_SSN
ruby bank_buster.rb    # runs headless and prints progress
```

## Serving via Agoo
`json_server.rb` already requires `handlers/bank_buster_handler.rb` and upgrades `/ws`.
Once `bank_buster_handler` receives `'START'`, it should:
```
Thread.new do
  BankBuster.new.parse { |ev| ws.write(ev.to_json) }
end
```
Connecting front-end can then show live logs and parsed payments.

---

See TODO.md for immediate tasks. 