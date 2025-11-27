# Sun Window Prediction Feature

**Status**: ✅ IMPLEMENTED (Nov 27, 2025) - Using Meteoblue CMV-based nowcasting
**Purpose**: Predict when sun will be out (continuous sunshine 10-20+ min) within next 1-2 hours for two Huddinge locations

---

## Use Case

Swedish winter problem: rare sunny hours, easy to miss them while indoors. Goal is to notify housemates when a sunny window is approaching so they can plan a walk and get sunlight on their faces.

**Two fixed locations in Huddinge:**
- **Solgård** (Sördalavägen 26): lat 59.233055, lng 17.978695
- **Urminnesvägen** (Urminnesvägen 6): lat 59.223566, lng 17.977356

---

## API Decision: Meteoblue (Winner) vs Alternatives

### Why Meteoblue (IMPLEMENTED)

**Meteoblue uses Cloud Motion Vector (CMV) for nowcasting:**
- Corrects NWP with real-time satellite observations every 15 minutes
- Tracks actual cloud motion to predict where they'll move
- **Next 5 hours** optimized using CMV (exactly our use case!)
- 10 million credits FREE for first year

**Accuracy for 1-2 hour nowcasting:**
- CMV-based: ~17-20% nRMSE (same technology as Solcast)
- Much better than pure NWP (~35% nRMSE)

### Research Summary (Nov 27, 2025)

Evaluated 15+ providers across three tiers:

| Provider | Technology | Free Tier | Accuracy (1-2hr) |
|----------|------------|-----------|------------------|
| **Meteoblue** | CMV | ✅ 10M credits/yr | ~17-20% nRMSE |
| Solcast | CMV | ⚠️ Requires approval | ~17% nRMSE |
| Open-Meteo | NWP | ✅ Unlimited | ~30-35% nRMSE |
| SMHI STRÅNG | Analysis | ✅ | N/A (not forecast) |
| Forecast.Solar | NWP | ✅ | ~35% nRMSE |

**Decision**: Meteoblue provides Solcast-quality CMV accuracy with generous free tier.

---

## Implementation

### Completed

1. **`lib/meteoblue_sun_predictor.rb`** - Service implementation
   - Fetches solar radiation forecast from Meteoblue API
   - Uses `shortwave_radiation` for sun detection (>200 W/m²)
   - Finds first continuous window meeting 10+ minute threshold
   - Returns JSON with `next_sun_window_start` and `next_sun_window_duration_minutes`

2. **`.env`** - API key configured
   ```
   METEOBLUE_API_KEY='4qfXsKW5F0vB6Gj3'
   ```

### TODO

3. ~~**Test the service**~~ ✅ DONE
   ```bash
   bundle exec ruby lib/meteoblue_sun_predictor.rb
   ```

4. **Integrate with dashboard weather widget** - IN PROGRESS
   - ✅ Prototyped orange gradient on Klimat widget during daylight
   - ✅ Tested multiple color variations (amber, coral, pink-orange)
   - **Current approach**: Orange gradient background on weather widget
   - **Color**: `rgba(255, 140, 50, 0.45)` → `rgba(255, 180, 80, 0.30)` (bright clean orange)
   - **Next steps**:
     - Add sun data to WebSocket broadcast from backend
     - Make gradient conditional on `is_daylight` or `brightness_percent`
     - Add brightness % indicator text to widget
     - Consider adding "next sun window" countdown

5. **Add API endpoint** (optional)
   - `GET /api/sun-windows` returning predictions for both locations

6. **Production deployment**
   - Add METEOBLUE_API_KEY to production .env ✅ (already in .env)
   - Monitor credit consumption via meteoblue dashboard

---

## Technical Details

### Meteoblue API

**Endpoint:** `https://my.meteoblue.com/packages/basic-1h_solar-1h`

**Parameters:**
- `lat`, `lon` - location coordinates
- `apikey` - authentication
- `format=json`

**Response:** Hourly forecasts with solar radiation fields:
- `ghi_instant`: Global Horizontal Irradiance (actual light hitting ground, W/m²)
- `clearskyshortwave_instant`: Maximum possible if no clouds (W/m²)
- `isdaylight`: Boolean daylight indicator

### Sun Detection Logic

**Swedish Winter Correction (Nov 27, 2025):**
At 59°N latitude in winter, the sun is so low that even a perfectly clear sky only produces ~100 W/m² GHI. Using absolute W/m² thresholds would never detect sun!

**Solution: Brightness Percentage = GHI / ClearSky GHI × 100**
- **90-100%**: Clear sky - direct sun visible ☀️
- **80-89%**: Thin clouds - sun perceivable 🌤️
- **60-79%**: Partly cloudy - occasional glimpses ⛅
- **<60%**: Overcast - no direct sun 🌥️☁️

**Implementation:**
- Threshold: `brightness_percent >= 80%` for "sun is perceivable"
- API fields: `ghi_instant` (actual) / `clearskyshortwave_instant` (max possible)
- Data: 1-hour intervals, need 1+ consecutive hours for sun window

### Cost

Meteoblue Free Weather API:
- 10 million credits for first year
- Simple forecast calls: ~1-5 credits per call
- Monitor at: https://www.meteoblue.com/en/weather-api/apikey/

---

## References

- Meteoblue API docs: https://docs.meteoblue.com/
- Meteoblue solar nowcasting: https://docs.meteoblue.com/en/services/energy/solar-monitoring-and-nowcasting
- API key dashboard: https://www.meteoblue.com/en/weather-api/apikey/

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-11-27 | Use Meteoblue over Solcast | CMV-based accuracy + free 10M credits/year, no approval wait |
| 2025-11-27 | Evaluated 15+ providers | SMHI STRÅNG = analysis only, Open-Meteo = NWP (~2x worse accuracy) |
