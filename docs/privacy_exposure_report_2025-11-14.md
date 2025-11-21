# Privacy Exposure Report – 14 Nov 2025

## Scope
Repo: `kimonokittens` (public GitHub). Requested review focused on potentially sensitive data: mostly Swedish personnummer, phone numbers, and local certificates/keys.

## Key Findings
1. **Tenant PII everywhere**  
   - Real personnummer + phone numbers appear in contracts (`contracts/*.md`), tenant metadata JSON, deployment helpers, and planning docs. Examples: `contracts/Frida_Johansson_Hyresavtal_2025-12-03.md`, `deployment/contract_tenants_export.json`, `docs/DELL_CONTRACT_DEPLOYMENT_PLAN.md`.  
   - These files effectively expose identifiable data for Frida Johansson, Sanna Juni Benemar, etc.
2. **mkcert dev TLS key committed**  
   - Root includes `localhost.pem` and `localhost-key.pem` generated via mkcert (see transcript `transcripts/cursor_new_stuff_woohoo.md`). Anyone can impersonate your local HTTPS endpoint if they also install your mkcert CA, and the file leaks machine metadata.
3. **Infrastructure dumps in repo**  
   - Node-RED backup JSON includes internal IPs and device IDs (`node-red/flows-backup-20251026.json`).  
   - Various transcripts mention environment variables, albeit without actual values, but reinforce that this repo shouldn’t be public.

## Recommendations
1. **Immediate**: make the GitHub repo private; regenerate local TLS materials (delete checked‑in mkcert outputs and add them to `.gitignore`).
2. **Data hygiene**: remove or encrypt tenant contracts/JSON from git history (e.g., move to secure storage, re-import via scripts). Use `git filter-repo` or start a clean repo after extracting needed code.
3. **Access policy**: document consent requirements for storing personal data; if consent isn’t explicit, scrub names/personnummer entirely or replace with anonymized fixtures.
4. **Prevent recurrence**: add contribution guidelines + pre-commit hooks that block Swedish SSN/phone patterns and PEM headers; ensure `.gitignore` includes certs, dumps, and other secrets.

Until these steps are complete, treat this repository as sensitive and restrict sharing.
