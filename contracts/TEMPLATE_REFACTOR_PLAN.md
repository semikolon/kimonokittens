# Contract Template Refactor Implementation Plan

## Problem Statement

**Current Architecture (Flawed):**
- Two `.md` files with duplicated contract text
- Any policy update requires editing multiple files
- Risk of drift between contract versions
- No connection to handbook as single source of truth

**Goal:**
- Handbook = canonical policy text
- Contracts pull sections from handbook automatically
- Tenant data in database (not JSON files)
- Zero duplication, zero drift risk

## Architecture Design

### Data Sources

**1. Handbook (Canonical Policy Text)**
```
handbook/docs/agreements.md
├─ Inredningsdeposition system
├─ Communal pot rules
├─ Co-ownership terms
├─ House rules references
└─ Democratic decision-making
```

**2. Database (Personal Data)**
```
Tenant table (extend if needed):
├─ name, personnummer
├─ email, phone
├─ move_in_date
├─ base_rent, deposit, furnishing_deposit
└─ status
```

**3. Template (Contract Structure)**
```
contracts/templates/base_contract.md.erb
├─ Legal preamble
├─ Parter section (from DB)
├─ Objekt (static)
├─ Hyrestid (from DB move_in_date)
├─ Hyra (from DB rent amounts)
├─ Avgifter (from handbook)
├─ Deposition (from handbook)
├─ Inredningsdeposition (from handbook)
├─ Uppsägning (from handbook)
├─ Övriga villkor (from handbook)
├─ Hyresstruktur (from handbook)
└─ Signatures
```

## Verbosity Consideration

**Question:** Does handbook verbosity suit legal contracts?

**Analysis:**
- Handbook already written for clarity and legal defensibility
- Both documents need clear, unambiguous language
- Contracts benefit from detailed explanations (prevents disputes)
- **Decision:** Use handbook text verbatim ✅

**If changes needed later:**
- Could add `contract_version` flag in handbook sections
- Different ERB tags for brief vs detailed text
- But start simple: one text, two contexts

## Database Schema Changes

### Current Tenant Table
Check if needs extension for:
```sql
-- Required for contracts (if missing):
ALTER TABLE Tenant ADD COLUMN email TEXT;
ALTER TABLE Tenant ADD COLUMN phone TEXT;
ALTER TABLE Tenant ADD COLUMN move_in_date DATE;
ALTER TABLE Tenant ADD COLUMN base_rent DECIMAL(10,2);
ALTER TABLE Tenant ADD COLUMN deposit DECIMAL(10,2);
ALTER TABLE Tenant ADD COLUMN furnishing_deposit DECIMAL(10,2);
ALTER TABLE Tenant ADD COLUMN status TEXT; -- 'active', 'pending', 'moved_out'
```

## Implementation Steps

### Phase 1: Handbook Section Extraction (30 min)
1. Create `HandbookParser` class
   - Parse `handbook/docs/agreements.md`
   - Extract sections by heading (## Inredningsdeposition, etc.)
   - Return hash: `{ inredningsdeposition: "text...", deposition: "text..." }`
2. Handle markdown to plain text conversion (preserve formatting)
3. Test extraction on current handbook content

### Phase 2: Template Creation (45 min)
1. Create `contracts/templates/base_contract.md.erb`
2. Define ERB template structure:
   ```erb
   # HYRESAVTAL – ANDRAHANDSUTHYRNING

   ## Parter
   **Förstahandshyresgäst:**
   - Namn: <%= landlord[:name] %>
   - Personnummer: <%= landlord[:personnummer] %>

   **Andrahands-hyresgäst:**
   - Namn: <%= tenant[:name] %>
   - Personnummer: <%= tenant[:personnummer] %>

   ## Inredningsdeposition
   <%= handbook_section[:inredningsdeposition] %>
   ```
3. Create landlord constants (Fredrik's info)
4. Define all needed variables from DB + handbook

### Phase 3: Generator Refactor (60 min)
1. Update `ContractGeneratorHtml.generate_from_tenant_id(tenant_id)`
2. Query tenant from database (not JSON)
3. Parse handbook sections via HandbookParser
4. Render ERB template with merged data
5. Generate markdown → HTML → PDF pipeline
6. Handle date formatting, currency formatting
7. Preserve existing PDF styling (80% colors, margins, etc.)

### Phase 4: Migration & Testing (45 min)
1. Run generator for Sanna (tenant_id from DB)
2. Run generator for Frida
3. **Visual diff** against current PDFs
   - Verify all content present
   - Verify formatting identical
   - Check page breaks, spacing
4. If issues: adjust template, not source data
5. Commit when both contracts match quality

### Phase 5: Cleanup (15 min)
1. Delete old `.md` files (keep in git history)
2. Update `contracts/.gitignore`:
   ```
   # Generated contracts (regenerate from DB)
   /*.md
   /*.pdf
   ```
3. Document new workflow in README
4. Archive JSON files (migration complete)

## Rollback Plan

If issues discovered:
1. Current `.md` files preserved in git history
2. Can regenerate current PDFs anytime
3. Database unchanged (new columns only added)
4. No data loss risk

## Testing Checklist

- [ ] Handbook parser extracts all sections correctly
- [ ] ERB template renders valid markdown
- [ ] Generated markdown matches content of current contracts
- [ ] PDF generation works with new markdown
- [ ] All styling preserved (colors, margins, fonts)
- [ ] Total rent line present
- [ ] Logo displays correctly
- [ ] Both Sanna and Frida contracts generate successfully
- [ ] Visual inspection: no missing content
- [ ] Visual inspection: formatting identical

## Files to Create/Modify

**New:**
- `lib/handbook_parser.rb` - Extract sections from handbook
- `contracts/templates/base_contract.md.erb` - ERB template

**Modified:**
- `lib/contract_generator_html.rb` - Use DB + handbook instead of markdown
- Database schema - Add missing Tenant columns (if needed)
- `contracts/.gitignore` - Ignore generated files

**Deprecated:**
- `contracts/Sanna_Benemar_Hyresavtal_2025-11-01.md` (git history preserved)
- `contracts/Frida_Johansson_Hyresavtal_2025-12-03.md` (git history preserved)
- `contracts/tenants/*.json` (data migrated to DB)

## Success Criteria

1. Single source of truth: handbook policies used verbatim
2. Zero duplication: edit once, affects all contracts
3. Database-driven: tenant data in DB, not files
4. Generated contracts visually identical to current versions
5. Future contract generation: single command with tenant_id

## Timeline Estimate

- Phase 1 (Parser): 30 min
- Phase 2 (Template): 45 min
- Phase 3 (Generator): 60 min
- Phase 4 (Testing): 45 min
- Phase 5 (Cleanup): 15 min
- **Total: ~3 hours**

## Next Steps

1. Check current Tenant schema
2. Implement HandbookParser
3. Create ERB template
4. Refactor generator
5. Test with both tenants
6. Commit when contracts match
