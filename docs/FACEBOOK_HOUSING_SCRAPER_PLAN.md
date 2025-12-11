# Facebook Housing Scraper - Plan Document

**Created:** December 10, 2025
**Updated:** December 10, 2025 (Ferrum scraper implementation complete)
**Purpose:** Find people posting "seeking housing" ads in Stockholm Facebook groups
**Execution:** Manual (run when needed, no automation)

---

## Goal

**Full context:** [JANUARY_2025_TENANT_CRISIS_MASTER_PLAN.md](./JANUARY_2025_TENANT_CRISIS_MASTER_PLAN.md) | [AI_KOLLEKTIV_VISION.md](./AI_KOLLEKTIV_VISION.md)

### The Crisis (Jan 2025)
- **Situation:** Sanna's psychotic episode triggered mass exodus - 3-4 rooms vacant simultaneously
- **Who left:** Rasmus gone, Frida abandoned move-in, Adam leaving for India
- **Financial exposure:** ~60,000 kr if no tenants by Jan 27
- **Deadline:** 17 days until January rent due (as of Dec 10)
- **Current leads:** Katarina, Marie, Lisa's friend, scraper prospects
- **February backups:** Isabelle+Jimmy (declined Jan, interested later)

### Recruitment Strategy (Parallel Tracks)
1. **Creative kollektiv ad** - General Facebook housing groups (current approach)
2. **AI kollektiv vision** - Tech/AI-focused pitch for programmers who use AI tools daily
   - Target: Coders seeking community + potential startup collaboration
   - Channels: Facebook paid ads (500-1000 kr), tech groups
   - Pitch: "Bo med andra AI-besatta, kanske starta något tillsammans"
3. **This scraper** - Automated lead discovery from FB housing groups

### Scraper Goal
Find people actively SEEKING housing in Stockholm who might be good kollektiv fits:
- **Priority 1:** Explicitly want kollektiv/shared living
- **Priority 2:** Generic housing need (open to kollektiv)
- **Priority 3:** Want own apartment (less likely but not excluded)

Output: Structured leads with contact info, budget, move-in timing, kollektiv-fit score.

---

## Technical Approach

### VALIDATED: Playwright MCP (Interactive)

**Proof of concept completed December 10, 2025:**
- Session persistence WORKS - FB login cookies persist across browser restarts
- Post content extraction WORKS - can read full posts including after "See more" expansion
- Post IDs extractable via `/posts/(\d+)` regex from URLs
- Timestamps readable ("about an hour ago", "6 hours ago", etc.)

**Workflow:**
1. User logs into FB once via Playwright MCP browser (with mobile app 2FA confirmation)
2. Session cookies persist for future scraping runs
3. Navigate to target groups
4. Scroll + extract with overlap strategy
5. Output structured JSON

### IMPLEMENTED: Ferrum Ruby Scraper

**Decision (December 10, 2025):** Ferrum selected over Playwright MCP for production use.

**Rationale:**
| Factor | Playwright MCP | Ferrum |
|--------|---------------|--------|
| **Token cost per run** | $0.50-2.00 | **$0.00** |
| **Monthly cost (weekly)** | $2-8/month | **$0.00** |
| **Schedulable (cron)** | ❌ Requires CC session | ✅ Fully automated |
| **Speed** | Slow (API round-trips) | Fast (local) |

**Implementation:**
- `lib/scrapers/facebook_housing_scraper.rb` - Main scraper class
- `bin/scrape_housing_ads` - CLI runner with options
- Chrome profile persistence at `~/.chrome-profiles/facebook-scraper`
- Follows vattenfall.rb/fortum.rb patterns

**Hybrid approach:** Playwright MCP validated the approach, Ferrum implements it cost-free.

---

## Target Groups

| Group Name | URL | Member Count | Notes |
|------------|-----|--------------|-------|
| Lägenheter i Stockholm - Öppen grupp | https://www.facebook.com/groups/1666084590295034 | 150.4K | TESTED - High volume, many seeking posts |
| Kollektiv i Stockholm | https://www.facebook.com/groups/kollektiv.stockholm/ | ? | In Fredrik's shortcuts |
| Kollektiv | https://www.facebook.com/groups/284581404943252/ | ? | In Fredrik's shortcuts |
| Bostad Stockholm | [URL needed] | ? | Common housing group |
| Hyresrätter Stockholm | [URL needed] | ? | Rental focused |
| Rum & Inneboende Stockholm | [URL needed] | ? | Room-specific |

**Status:** First group tested and validated.

---

## Search/Filter Criteria

### Keywords (Swedish + English) - PRIORITY RANKED

**PRIORITY 1 - Explicitly open to shared living (BEST FIT):**
- "söker rum" (seeking room)
- "söker kollektiv" / "vill bo i kollektiv"
- "delat boende" / "shared housing"
- "letar efter rum"
- "looking for room"
- "room in shared"

**PRIORITY 2 - Generic housing need (may be open to kollektiv):**
- "söker boende" (seeking housing - generic)
- "behöver bostad" / "behöver någonstans att bo"
- "står utan boende" (desperate, open to anything)
- "need a place to live"

**PRIORITY 3 - Wants own apartment (LESS INTERESTING but not excluded):**
- "söker lägenhet" (seeking apartment)
- "egen lägenhet" (own apartment)
- "looking for apartment"
*Note: These people haven't necessarily considered kollektiv yet - could be worth noting but lower priority*

**EXCLUDE (hard filters):**
- "ej inneboende" / "not interested in lodger"
- "ej kollektiv" / "no shared housing"
- "vill inte dela" (don't want to share)

**Exclude (offering housing):**
- "ledig" / "uthyres" / "hyr ut"
- "available" / "for rent"

### Date Range

- Posts from last 7-14 days
- Configurable parameter

### Location Signals

- "Stockholm" mentioned
- "Huddinge" (bonus)
- "söder" / "södermalm" (central preference - note but don't exclude)

### Budget Signals (if mentioned)

- 5000-10000 kr range = good fit
- Under 5000 kr = might be too budget-constrained
- Over 10000 kr = looking for own apartment, not kollektiv

---

## Output Format

```json
{
  "scrape_date": "2025-12-10",
  "posts_found": [
    {
      "poster_name": "Elsa Ridderstedt",
      "post_date": "2025-11-27",
      "post_url": "https://facebook.com/groups/xxx/posts/yyy",
      "group_name": "Lägenheter i Stockholm - Öppen grupp",
      "content_preview": "First 200 chars of post...",
      "move_in_date": "January" | "February" | "ASAP" | "Unknown",
      "budget_mentioned": "7000 kr" | null,
      "location_preference": "innanför tullarna" | "Stockholm" | null,
      "contact_method": "Messenger" | "Comment" | "Phone in post",
      "profile_url": "https://facebook.com/elsa.ridderstedt",
      "fit_notes": "Music student, 22, seeking long-term"
    }
  ]
}
```

---

## Scrolling & Extraction Strategy

### Overlap Scrolling (VALIDATED)

**Problem:** Facebook uses lazy loading. Scroll too fast = miss posts. Scroll too slow = waste time.

**Solution:** 50% viewport overlap with deduplication

```
Viewport 1:  [Post A] [Post B] [Post C] ←── Process all
             ↓ scroll 50% ↓
Viewport 2:  [Post B] [Post C] [Post D] ←── Process D only (B,C in processed_ids)
             ↓ scroll 50% ↓
Viewport 3:  [Post C] [Post D] [Post E] ←── Process E only
```

**Metrics from testing (Dec 10, 2025):**
- Viewport height: ~906px
- Optimal scroll amount: ~450px (50%)
- Post ID extraction: `/posts/(\d+)` regex from post URLs

### "See More" Expansion Strategy

**Two-pass approach:**
1. **Quick scan** - Read visible text, classify as SEEKING/OFFERING/UNKNOWN
2. **Targeted expansion** - Only click "See more" on SEEKING or UNKNOWN posts

**Detection:** `[role="button"]` elements with `textContent.trim() === 'See more'`

### Rate Limiting (Anti-Detection)

| Action | Delay Range | Notes |
|--------|-------------|-------|
| Between scrolls | 800-1500ms | Includes lazy-load time |
| After "See more" click | 500-1000ms | Human-like read time |
| Between groups | 3-8 seconds | Simulate navigation |
| Max session length | 15 minutes | Avoid long-session flags |

---

## Implementation Outline

### File Structure (IMPLEMENTED)

```
lib/scrapers/
  facebook_housing_scraper.rb    # ✅ Main scraper class (created Dec 10)

bin/
  scrape_housing_ads             # ✅ CLI runner script (created Dec 10)

data/
  housing_leads/
    2025-12-10_leads.json        # Output per run

~/.chrome-profiles/
  facebook-scraper/              # Chrome profile for FB session persistence
```

### Core Components

**1. FacebookSession**
- Handle login (credentials from .env)
- Maintain session cookies
- Navigate to groups

**2. GroupScraper**
- Scroll/paginate through group posts
- Filter by date range
- Extract post content

**3. PostAnalyzer**
- Classify: seeking vs offering
- Extract structured fields
- Score relevance

**4. OutputWriter**
- Write JSON results
- Optional: markdown summary for quick review

### CLI Interface (IMPLEMENTED)

```bash
# First-time setup: Login to Facebook (creates session)
bin/scrape_housing_ads --login
# (Log in manually in browser, handle 2FA, then Ctrl+C)

# Basic run - all configured groups, last 7 days
bin/scrape_housing_ads

# Custom options
bin/scrape_housing_ads --days 14              # Last 14 days
bin/scrape_housing_ads --max-posts 100        # More posts per group
bin/scrape_housing_ads --show-browser         # Watch it work
bin/scrape_housing_ads --debug                # Verbose logging

# Combined
bin/scrape_housing_ads --days 14 --max-posts 100 --debug
```

---

## Privacy & Ethics Considerations

- Only scraping public group posts
- Not scraping private messages
- Using your own Facebook account (not fake accounts)
- Purpose is housing search, not data harvesting
- Don't store unnecessary personal data
- Delete old scrape results after use

---

## Dependencies

- `playwright` or `ferrum` (browser automation)
- Facebook login credentials in `.env`
- Possibly `nokogiri` for HTML parsing

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Facebook blocks scraping | Use realistic browsing patterns, don't scrape too fast |
| Layout changes break scraper | Build with flexible selectors, expect maintenance |
| Rate limiting | Add delays between requests, limit pages per run |
| Login challenges (2FA, captcha) | Handle interactively if needed |
| Posts are images not text | Skip image-only posts or note for manual review |

---

## Open Questions

1. ~~Which Facebook groups specifically?~~ **ANSWERED** - Primary group identified, shortcuts found
2. ~~Do you have 2FA on your Facebook account?~~ **ANSWERED** - Yes, mobile app confirmation works
3. How many days back to search? (Currently 7-14 days)
4. ~~Any other keywords to include/exclude?~~ **UPDATED** - Priority-ranked system added
5. ~~Ruby (consistent with project) or Python?~~ **ANSWERED** - Playwright MCP for now, Ferrum for automation later

---

## Next Steps

1. ~~Test Playwright MCP session persistence~~ **DONE**
2. ~~Test post extraction and "See more" expansion~~ **DONE**
3. ~~Design scrolling strategy~~ **DONE**
4. ~~Implement Ferrum scraper~~ **DONE** (Dec 10)
5. ~~Create CLI runner~~ **DONE** (Dec 10)
6. ~~Run `bin/scrape_housing_ads --login` to create FB session~~ **DONE** (Dec 10)
7. ~~Run full production scrape~~ **DONE** (Dec 10) - 5 leads from 3 groups
8. ~~Review leads JSON output~~ **DONE** (Dec 10)
9. ~~Smarter post extraction with LLM~~ **DONE** (Dec 10) - Gemini 3 Pro integration complete
10. **TODO:** Add "See more" expansion for truncated posts
11. ~~Distinguish posts from comments properly~~ **DONE** (Dec 10) - LLM detects content_type: "post" vs "comment"
12. ~~Performance tuning~~ **DONE** (Dec 11) - Faster session verification, smarter scrolling, Chrome flags
13. ~~LLM error handling~~ **DONE** (Dec 11) - Fails hard on API errors (no silent fallback)
14. ~~Interest comment false positives~~ **DONE** (Dec 11) - "Intresserad!" now correctly excluded (intent=other)
15. ~~Early stopping bug~~ **DONE** (Dec 11) - Increased patience threshold from 3 to 6 consecutive empty scrolls

---

## Sample Posts Found (Dec 10, 2025)

| Poster | Type | Priority | Summary |
|--------|------|----------|---------|
| Alvee Patowary | SEEKING | P3 | Couple, 1-2 room apt, budget 8000kr, Feb 1 move-in |
| Lisa's friend (via Lisa Juntunen Roos) | SEEKING | P2 | Single mom, 3 kids, needs housing Jan 1 - **HOT LEAD** |
| Rengin Deniz | SEEKING | EXCLUDE | 21yo law student, explicitly "ej inneboende" |
| Niklas Siljemark | OFFERING | N/A | Renting out etta in Ursvik |
| Diana Weaver | OFFERING | N/A | 2-room in Täby |

---

**Status:** ✅ Phase 1 & 2 complete. LLM-enhanced extraction operational.

---

## Phase 2: LLM-Enhanced Extraction (IMPLEMENTED Dec 10, 2025)

**Problems solved from initial test run:**
- ~~`poster_name` always "Unknown"~~ → LLM extracts name from content
- ~~Picking up COMMENTS instead of POSTS~~ → LLM detects `content_type: "post"` vs `"comment"`
- ~~Keyword matching too rigid~~ → LLM understands Swedish context ("ej kollektiv" = exclude)

**Implementation:**

| File | Purpose |
|------|---------|
| `lib/scrapers/gemini_post_analyzer.rb` | Gemini 3 Pro client with structured extraction |
| `lib/scrapers/facebook_housing_scraper.rb` | Updated with `--llm` mode integration |
| `bin/scrape_housing_ads` | CLI with `--llm` flag |

**Usage:**

```bash
# Keyword mode (free, fast, less accurate)
bin/scrape_housing_ads

# LLM mode (Gemini 3 Pro - smart extraction)
bin/scrape_housing_ads --llm

# LLM with debug output
bin/scrape_housing_ads --llm --debug
```

**Requirements:**
- `GEMINI_API_KEY` environment variable
- `ruby-gemini-api` gem (added to Gemfile)

**Cost estimate (Gemini 3 Pro):**
- ~$0.001-0.002 per post analyzed
- 100 posts ≈ $0.10-0.20
- Monthly cost (weekly scraping): ~$0.50-1.00

**LLM Output Format:**

```json
{
  "content_type": "post",
  "intent": "seeking",
  "poster_name": "Anna Svensson",
  "kollektiv_fit": 1,
  "budget_kr": 8000,
  "move_in_date": "January",
  "location_preferences": "Södermalm",
  "exclude": false,
  "exclude_reason": null,
  "summary": "Söker rum i kollektiv, öppen för delat boende",
  "confidence": 0.92
}
```

**Architecture:**

```
Facebook DOM → Ferrum extraction → GeminiPostAnalyzer → Structured JSON → Lead filtering
                                         ↓
                              Gemini 3 Pro API
                              (model: gemini-3-pro-preview)
```

**Key Features:**
- Crisis context injected into prompt (Jan 2025 tenant situation)
- Confidence scoring (filters low-confidence results)
- Automatic comment detection and exclusion
- Swedish language understanding
- Graceful fallback to keyword mode if API fails

---

## Critical Bug Fix: Cookie Persistence (Dec 10, 2025)

**Problem:** Facebook session not persisting between scraper runs.

**Root cause:** Ferrum adds `--password-store=basic` Chrome flag by default, which has a Chrome bug (Google issue #393476248) that breaks cookie persistence.

**Solution:** Use `ignore_default_browser_options: true` in Ferrum::Browser.new

```ruby
@browser = Ferrum::Browser.new(
  browser_options: {
    'user-data-dir' => CHROME_PROFILE_PATH,
    'no-first-run' => true,
    # ... other flags
  },
  ignore_default_browser_options: true  # CRITICAL: removes --password-store=basic
)
```

**Lesson:** When Chrome profile cookies aren't persisting, check for `--password-store=basic` flag.
