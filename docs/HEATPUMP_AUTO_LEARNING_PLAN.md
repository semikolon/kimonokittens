# Heatpump Auto-Learning Implementation Plan

**Created:** December 20, 2025
**Status:** Implementation Complete - Awaiting Migration
**Prerequisites:** Override logging + analysis endpoint (deployed Dec 19, 2025)
**Related:** `HEATPUMP_SCHEDULE_API_PLAN.md`, `HEATPUMP_CONFIG_UI_PLAN.md`

---

## Executive Summary

**Problem:** Current heatpump scheduling uses static parameters (`hours_on=15`, `MIN_HOURS_PER_BLOCK=2`). When these don't match actual heating demand, temperature emergencies trigger overrides - wasting money by running during expensive hours.

**Solution:** Closed-loop auto-learning system that:
1. Analyzes override patterns weekly
2. Adjusts `hours_on` based on override frequency
3. Learns per-block distribution based on where overrides cluster

**Benefit:** Self-optimizing schedule that adapts to seasonal changes, usage patterns, and building characteristics without manual intervention.

---

## Current State (Dec 19, 2025)

### What's Deployed

| Component | Status | Location |
|-----------|--------|----------|
| Override logging | ✅ Live | `heatpump_schedule_handler.rb:log_override()` |
| HeatpumpOverride table | ✅ Live | Prisma schema + migration applied |
| Analysis endpoint | ✅ Live | `GET /api/heatpump/analysis?days=N` |
| Distribution algorithm | ✅ Live | MIN_HOURS_PER_BLOCK=2 per 6-hour block |
| Recommendations | ✅ Live | Text suggestions in analysis response |

### What's Missing (This Plan)

| Component | Status | Description |
|-----------|--------|-------------|
| Auto-adjustment logic | ❌ | Actually apply recommendations |
| Per-block learning | ❌ | Variable MIN_HOURS per block |
| Cron job | ❌ | Weekly execution trigger |
| Adjustment history | ❌ | Audit log of all changes |
| SMS notifications | ❌ | Alert when auto-adjusted |

---

## Architecture Design

### Data Flow

```
Override Events (continuous)
    ↓
HeatpumpOverride table
    ↓
Weekly Cron Job (Sunday 3am)
    ↓
┌─────────────────────────────────────┐
│  HeatpumpAutoTuner                  │
│  ├─ Analyze last 7 days            │
│  ├─ Calculate adjustment needed     │
│  ├─ Apply guardrails               │
│  ├─ Update HeatpumpConfig          │
│  ├─ Log to HeatpumpAdjustment      │
│  └─ Send SMS notification          │
└─────────────────────────────────────┘
    ↓
Updated schedule (next Node-RED poll)
```

### Database Schema Changes

```prisma
// NEW: Track all auto-adjustments for audit
model HeatpumpAdjustment {
  id              String   @id @default(cuid())
  adjustmentType  String   // 'hours_on' or 'block_distribution'
  previousValue   String   // JSON: {"hours_on": 14} or {"blocks": [2,2,2,2]}
  newValue        String   // JSON: {"hours_on": 15} or {"blocks": [2,3,2,2]}
  reason          String   // Human-readable explanation
  overrideStats   String   // JSON: stats that triggered this
  createdAt       DateTime @default(now())

  @@index([createdAt(sort: Desc)])
}

// MODIFY: Add per-block distribution to config
model HeatpumpConfig {
  // ... existing fields ...

  // NEW: Per-block minimum hours (JSON array)
  // Default: [2,2,2,2] = 2 hours per 6-hour block
  // Learned: [2,3,2,2] = 3 hours in morning block
  blockDistribution String @default("[2,2,2,2]")

  // NEW: Last auto-adjustment timestamp
  lastAutoAdjustment DateTime?
}
```

---

## Layer 2: Weekly Auto-Adjustment

### Algorithm

```ruby
class HeatpumpAutoTuner
  # Thresholds
  INCREASE_THRESHOLD = 1.5   # overrides/day triggers increase
  DECREASE_THRESHOLD = 0.0   # must be zero to decrease
  DECREASE_WAIT_WEEKS = 2    # consecutive zero-override weeks

  # Guardrails
  MIN_HOURS = 10             # Never below (safety)
  MAX_HOURS = 20             # Never above (cost)
  MIN_ADJUSTMENT_INTERVAL_DAYS = 7  # Prevent oscillation

  def run
    return skip("Too soon") if days_since_last_adjustment < MIN_ADJUSTMENT_INTERVAL_DAYS

    stats = analyze_period(days: 7)

    if stats[:overrides_per_day] > INCREASE_THRESHOLD
      adjust_hours_on(+1, "High override rate: #{stats[:overrides_per_day].round(1)}/day")

    elsif stats[:overrides_per_day] == 0 && consecutive_zero_weeks >= DECREASE_WAIT_WEEKS
      adjust_hours_on(-1, "Zero overrides for #{DECREASE_WAIT_WEEKS}+ weeks")

    else
      log_no_change(stats)
    end
  end

  private

  def adjust_hours_on(delta, reason)
    config = Persistence.heatpump_config.get_current
    new_hours = (config.hours_on + delta).clamp(MIN_HOURS, MAX_HOURS)

    return if new_hours == config.hours_on  # Hit limit

    # Update config
    Persistence.heatpump_config.update(
      hours_on: new_hours,
      last_auto_adjustment: Time.now
    )

    # Log adjustment
    Persistence.heatpump_adjustments.record(
      adjustment_type: 'hours_on',
      previous_value: { hours_on: config.hours_on }.to_json,
      new_value: { hours_on: new_hours }.to_json,
      reason: reason,
      override_stats: stats.to_json
    )

    # Notify
    send_sms("Värmepump auto-justerad: #{config.hours_on}→#{new_hours}h (#{reason})")
  end
end
```

### Decision Matrix

| Overrides/Day | Consecutive Zero Weeks | Action |
|---------------|------------------------|--------|
| > 1.5 | - | hours_on += 1 |
| 0.5 - 1.5 | - | No change (acceptable) |
| 0.1 - 0.5 | - | No change (good) |
| 0 | < 2 | No change (wait for confidence) |
| 0 | >= 2 | hours_on -= 1 |

---

## Layer 3: Block-Level Learning

### Concept

Instead of uniform `MIN_HOURS_PER_BLOCK = 2` for all blocks, learn which blocks need more coverage.

```
Current (static):  [2, 2, 2, 2]  = overnight, morning, afternoon, evening
Learned example:   [2, 3, 2, 2]  = morning needs more (shower recovery)
```

### Algorithm

```ruby
def analyze_block_distribution
  # Only run after sufficient data (30+ days)
  overrides = Persistence.heatpump_overrides.last_n_days(30)
  return nil if overrides.count < 10  # Not enough data

  # Count overrides by block
  block_counts = { overnight: 0, morning: 0, afternoon: 0, evening: 0 }

  overrides.each do |o|
    block = hour_to_block(o.hour_of_day)
    block_counts[block] += 1
  end

  total = block_counts.values.sum

  # Find blocks with disproportionate overrides (> 35% of total)
  problem_blocks = block_counts.select { |_, count| count > total * 0.35 }

  return nil if problem_blocks.empty?

  # Build new distribution
  current = Persistence.heatpump_config.get_current.block_distribution
  new_distribution = current.dup

  problem_blocks.each do |block, _|
    block_index = BLOCK_NAMES.index(block)
    new_distribution[block_index] += 1  # Add one hour to problem block
  end

  # Cap total distributed hours (can't exceed hours_on)
  if new_distribution.sum > config.hours_on
    # Reduce from lowest-override block
    min_block = block_counts.min_by { |_, v| v }.first
    min_index = BLOCK_NAMES.index(min_block)
    new_distribution[min_index] -= 1
  end

  new_distribution
end
```

### Block Definitions

| Block | Hours | Typical Pattern |
|-------|-------|-----------------|
| Overnight | 00:00-05:59 | Low usage, cheap electricity |
| Morning | 06:00-11:59 | Showers deplete hot water |
| Afternoon | 12:00-17:59 | Moderate, some peak pricing |
| Evening | 18:00-23:59 | Cooking, evening showers |

---

## Implementation Plan

### Phase 1: Schema + Model (30 min)

1. Add `HeatpumpAdjustment` model to Prisma schema
2. Add `blockDistribution` and `lastAutoAdjustment` to HeatpumpConfig
3. Create migration
4. Create domain model: `lib/models/heatpump_adjustment.rb`
5. Create repository: `lib/repositories/heatpump_adjustment_repository.rb`
6. Wire up in `lib/persistence.rb`

### Phase 2: Auto-Tuner Service (1 hour)

1. Create `lib/services/heatpump_auto_tuner.rb`
   - `run()` - main entry point
   - `analyze_period(days:)` - calculate stats
   - `adjust_hours_on(delta, reason)` - apply change
   - `consecutive_zero_weeks` - track zero-override streaks

2. Guardrails:
   - Hard limits (10-20 hours)
   - Rate limiting (7 days between adjustments)
   - Dry-run mode for testing

3. SMS notification via existing `Sms::Gateway`

### Phase 3: Block Learning Extension (30 min)

1. Add `analyze_block_distribution()` to auto-tuner
2. Modify schedule handler to read `blockDistribution` from config
3. Update `select_cheapest_hours()` to use per-block minimums

### Phase 4: Cron Job + CLI (20 min)

1. Create `bin/heatpump_auto_tune`
   ```ruby
   #!/usr/bin/env ruby
   require_relative '../lib/boot'

   tuner = HeatpumpAutoTuner.new(dry_run: ARGV.include?('--dry-run'))
   result = tuner.run

   puts result[:message]
   exit(result[:adjusted] ? 0 : 1)
   ```

2. Add to production cron:
   ```cron
   # Sunday 3am - weekly heatpump auto-tune
   0 3 * * 0 /home/kimonokittens/.rbenv/shims/bundle exec ruby /home/kimonokittens/Projects/kimonokittens/bin/heatpump_auto_tune >> /var/log/kimonokittens/auto_tune.log 2>&1
   ```

### Phase 5: Testing (20 min)

1. Unit tests for `HeatpumpAutoTuner`
   - Test increase threshold logic
   - Test decrease with consecutive weeks
   - Test guardrails (min/max limits)
   - Test rate limiting

2. Integration test with mock override data

### Phase 6: Monitoring Endpoint (10 min)

1. Extend `/api/heatpump/analysis` to include:
   - `last_adjustment` - when auto-tune last ran
   - `adjustment_history` - last 5 adjustments
   - `next_eligible_adjustment` - when next adjustment allowed

---

## Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `lib/models/heatpump_adjustment.rb` | Domain model for adjustment history |
| `lib/repositories/heatpump_adjustment_repository.rb` | Persistence layer |
| `lib/services/heatpump_auto_tuner.rb` | Main auto-learning logic |
| `bin/heatpump_auto_tune` | CLI entry point for cron |
| `spec/services/heatpump_auto_tuner_spec.rb` | Unit tests |

### Modified Files

| File | Changes |
|------|---------|
| `prisma/schema.prisma` | Add HeatpumpAdjustment, extend HeatpumpConfig |
| `lib/persistence.rb` | Wire up new repositories |
| `lib/models/heatpump_config.rb` | Add block_distribution accessor |
| `handlers/heatpump_schedule_handler.rb` | Read per-block distribution |
| `handlers/heatpump_analysis_handler.rb` | Include adjustment history |

---

## Guardrails & Safety

### Hard Limits

```ruby
MIN_HOURS = 10   # Below this, house gets too cold
MAX_HOURS = 20   # Above this, cost savings lost
MIN_BLOCK_HOURS = 1  # Every block needs at least 1 hour
MAX_BLOCK_HOURS = 4  # No block should dominate
```

### Rate Limiting

- Minimum 7 days between adjustments
- Maximum 1 adjustment per week
- Prevents oscillation (up-down-up-down)

### Rollback Capability

- All adjustments logged with full context
- Can manually revert via HeatpumpConfig admin
- Emergency: set hours_on manually, disable auto-tune

### Notification

- SMS to admin on every adjustment
- Include before/after values and reason
- Example: "Värmepump: 14→15h (1.8 övertramp/dag senaste veckan)"

---

## Success Metrics

After 30 days of operation:

| Metric | Target |
|--------|--------|
| Override frequency | < 0.5/day |
| Manual interventions | 0 |
| Cost increase from over-provisioning | < 5% |
| Adjustment oscillations | 0 |

---

## Rollout Plan

1. **Week 1:** Deploy to production, run in dry-run mode (log what WOULD change)
2. **Week 2:** Enable real adjustments, monitor closely
3. **Week 3+:** Hands-off, review weekly via analysis endpoint

---

## Future Enhancements (Layer 4+)

### Weather Correlation (90+ days data)

```ruby
# Build model: outdoor_temp → extra_hours_needed
# Proactively adjust based on weather forecast
def weather_adjusted_hours(base_hours, forecast_temp)
  # Linear model: add 0.5 hours per degree below 5°C
  extra = [0, (5 - forecast_temp) * 0.5].max
  (base_hours + extra).round.clamp(MIN_HOURS, MAX_HOURS)
end
```

### Hot Water Usage Patterns

- Track hot water depletion times
- Pre-heat before predictable demand (morning showers)
- Requires more granular temperature logging

### Energy Price Forecasting

- Use day-ahead price data
- Shift hours to cheapest windows within block constraints
- Balance cost vs comfort

---

## Appendix: Current Constants

From `heatpump_schedule_handler.rb`:

```ruby
DEFAULT_HOURS_ON = 12
MIN_HOURS_PER_BLOCK = 2

HOUR_BLOCKS = [
  (0..5),   # overnight
  (6..11),  # morning
  (12..17), # afternoon
  (18..23)  # evening
]
```

From `HeatpumpConfig` table:
- `hours_on`: 15 (current production value)
- `min_hotwater`: 42.0°C
- `emergency_temp_offset`: 2.0°C
