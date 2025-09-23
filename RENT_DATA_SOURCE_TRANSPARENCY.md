# Rent Calculation Data Source Transparency

## Problem Statement
The rent widget currently displays calculated rent amounts without indicating whether the calculation is based on actual electricity bills or historical projections. Users should know the data source reliability for transparency.

## Research Findings

### Current Data Source Hierarchy
1. **Primary: Current Bills (Manual Entry)**
   - Actual bills manually entered into config when available
   - Takes precedence over all other sources
   - Example: `el: 2_470 + 1_757` in monthly calculation scripts

2. **Fallback: Historical Bills (`electricity_bills_history.txt`)**
   - Real historical data from Vattenfall (elnät) and Fortum (förbrukning) 2023-2024
   - Used by `get_historical_electricity_cost()` method for forecasting
   - Looks up same month from previous year when current bills unavailable
   - Example data: `2024-10-01 1164 kr` (Vattenfall), `2024-10-01 138 kr` (Fortum)

3. **Safety Defaults (Config::DEFAULTS)**
   - Hardcoded fallback: `el: 1_324 + 276` = 1,600 kr
   - Used when neither current nor historical data available

### How The System Actually Works
- **Current Month Calculation**: Uses actual bills if entered → Falls back to historical if not → Uses defaults as last resort
- **Forecasting**: Automatically uses `get_historical_electricity_cost()` to pull previous year's bills for same month
- **Mixed Reality**: Current rent might be based on actual October 2025 bills, but if November isn't available yet, it forecasts using November 2024 historical data

### Key Code Locations
- **Backend Handler**: `/Users/fredrikbranstrom/Projects/kimonokittens/handlers/rent_calculator_handler.rb`
  - `handle_friendly_message()` method (lines 497-531)
  - `get_historical_electricity_cost()` method (lines 365-413)
  - `extract_config()` method (lines 331-363)

- **Historical Data**: `/Users/fredrikbranstrom/Projects/kimonokittens/electricity_bills_history.txt`
  - Vattenfall bills: 2023-04-04 to 2024-10-01
  - Fortum bills: 2023-03-31 to 2024-10-01

- **Frontend Widget**: `/Users/fredrikbranstrom/Projects/kimonokittens/dashboard/src/components/RentWidget.tsx`
  - Currently displays friendly_message without data source context

## Proposed Solution

### Backend Changes
1. **Modify `handle_friendly_message()` to include data source metadata**:
   ```ruby
   result = {
     message: friendly_text,
     year: year,
     month: month,
     generated_at: Time.now.utc.iso8601,
     data_source: {
       type: 'actual' | 'historical' | 'defaults',
       electricity_source: 'current_bills' | 'historical_lookup' | 'fallback_defaults',
       description_sv: 'Baserad på aktuella elräkningar' | 'Baserad på prognos från förra årets elräkningar'
     }
   }
   ```

2. **Logic for determining data source**:
   - Check if electricity cost comes from manually entered config (actual)
   - Check if `get_historical_electricity_cost()` was used (historical)
   - Check if Config::DEFAULTS was used (defaults)

### Frontend Changes
1. **Update RentWidget to display data source**:
   ```tsx
   {rentData.data_source && (
     <div className="text-purple-300 text-xs mt-2" style={{ opacity: 0.5 }}>
       {rentData.data_source.description_sv}
     </div>
   )}
   ```

### Swedish Text Options
- **Actual bills**: `"Baserad på aktuella elräkningar"`
- **Historical projection**: `"Baserad på prognos från förra årets elräkningar"`
- **Defaults**: `"Baserad på uppskattade elkostnader"`

All displayed with ~50% opacity for subtle transparency.

## Implementation Priority
- **High**: This feature provides important transparency about data reliability
- **User Value**: Helps users understand if rent is based on real or projected costs
- **Technical Debt**: Low - clean addition to existing API structure

## Next Steps
1. Implement backend data source detection logic
2. Update API response format
3. Update frontend widget to display source indicator
4. Test with various scenarios (actual/historical/defaults)
5. Add tests for data source classification logic

## Implementation Complete ✅

### Backend Implementation
- **Added `handle_friendly_message` endpoint** in rent_calculator_handler.rb:497-531
- **Implemented `determine_electricity_data_source` method** for data source detection
- **Fixed nil handling bug** in `extract_config` method that was causing 500 errors
- **Added data source metadata** to API response with Swedish descriptions

### Frontend Implementation
- **Created RentWidget component** with proper markdown parsing and bold text rendering
- **Added data source transparency indicator** with subtle 50% opacity display
- **Integrated rent widget** into main dashboard layout with Horsemen font styling

### Train/Bus Widget Refinements
Multiple iterations based on user feedback to achieve perfect spacing and opacity:

1. **Spacing Fixes Applied**:
   - Added space after colon for bus lines: `"station:16:03"` → `"station: 16:03"`
   - Added space before "du hinner gå" for train lines
   - Fixed double dash issue: `"- - spring!"` → `"- spring!"`

2. **0m Departure Handling**:
   - Replaced `"om 0m"` with actionable `"- spring!"` text
   - **Critical UX decision**: 0m buses show normal opacity (not faded) since "spring!" is actionable
   - Logic: `const lineOpacity = minutesUntil === 0 ? 1.0 : getTimeOpacity(timeMatch[0])`

3. **Text Processing Rules Established**:
   ```tsx
   // Add space after colon for bus lines
   text = text.replace(/([^:\s]):(\d{2}:\d{2})/, '$1: $2')

   // Add space after "om Xm" before "- du hinner gå"
   text = text.replace(/(om \d+m)(-\s)/, '$1 $2')

   // Handle 0m case - replace with actionable text
   text = text.replace(/om 0m/, '- spring!')
   text = text.replace(/- - spring!/, '- spring!')
   ```

## Session Learnings & Technical Decisions

### Visual Hierarchy Principles
- **Time-based opacity gradient**: 20m (100%) → 50m (15%) for realistic departure visibility
- **Actionable content override**: 0m departures bypass opacity rules since "spring!" requires immediate action
- **Mix-blend-mode: hard-light** provides subtle layering without losing readability

### Error Handling Patterns
- **Backend nil safety**: Always check for nil before calling methods on dynamic config data
- **Frontend loading states**: Proper error boundaries with Swedish error messages
- **API response structure**: Include metadata for transparency without breaking existing clients

### User Experience Insights
- **Spacing matters critically**: Users notice missing spaces after colons immediately
- **Double dashes feel broken**: Text processing must handle cascading replacements
- **Opacity communicates urgency**: Faded = "less important", normal = "actionable now"
- **Transparency builds trust**: Showing data source (actual vs projected) helps users understand reliability

### Code Quality Patterns
- **Single responsibility**: Each text replacement handles one specific formatting rule
- **Defensive programming**: Handle edge cases like double replacements and nil values
- **User feedback iteration**: Small visual details require multiple refinement cycles
- **DOM inspection verification**: Always verify actual rendered output, not just code logic

## Related Files Modified in This Session
- **TrainWidget.tsx**: Complete departure time processing overhaul with spacing and opacity fixes
- **RentWidget.tsx**: New component with markdown parsing and data source transparency
- **App.tsx**: Integrated rent widget into dashboard layout
- **rent_calculator_handler.rb**: Added friendly_message endpoint with data source detection
- **Git commits**: All changes safeguarded with descriptive commit messages

## Context Notes
- This research was conducted as part of dashboard improvement session spanning train/bus widgets and rent transparency
- User specifically requested transparency about calculation methodology and precise spacing fixes
- Solution designed to be minimally invasive while maximally informative
- Multiple user feedback cycles refined spacing, opacity, and text processing to pixel-perfect standards
- Critical UX insight: 0m departures need normal opacity since "spring!" text is immediately actionable