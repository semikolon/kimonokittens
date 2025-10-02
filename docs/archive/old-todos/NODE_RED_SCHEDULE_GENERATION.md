# Node-RED Schedule Generation Documentation

## Overview
This document details how the heatpump schedule is generated in Node-RED from Tibber electricity price data, processed through optimization algorithms, and converted to the `current_schedule` field consumed by the dashboard.

## Architecture Flow

### 1. Data Sources
- **Tibber API**: Provides hourly electricity prices for current and next day
- **Price Receiver**: Fetches 48-hour price data from Tibber every 20 minutes
- **Tibber Query Node**: Handles API authentication and data retrieval

### 2. Node-RED Flow Structure

#### A. Price Collection
```
[Tibber price today and tomorrow] → [Tibber Query] → [Price Receiver]
```

#### B. Schedule Optimization
```
[Price Receiver] → [Select lowest price hours] → [EVU] → [Remember current schedule]
```

#### C. Schedule Processing
```
[Remember current schedule] → [Function Node: JavaScript Logic] → [current_schedule output]
```

## 3. Schedule Optimization Algorithm

### Configuration Parameters (from screenshot analysis)
```javascript
{
  fromTime: "00:00",
  toTime: "00:00",          // 24-hour operation
  hoursOn: 13,              // Total hours to run per day
  maxPrice: 2.2,            // Maximum acceptable price threshold
  doNotSplit: false,        // Allow split periods
  outputIfNoSchedule: true,
  outputOutsidePeriod: false,
  outputValueForOn: "0",    // Inverted logic
  outputValueForOff: "1"    // Inverted logic
}
```

### Core Algorithm Logic
The "Select lowest price hours" node implements:

1. **Price Sorting**: Sort all 48 hours by electricity price (ascending)
2. **Hour Selection**: Select the 13 cheapest hours within constraints
3. **Continuity Optimization**: Group consecutive hours when possible
4. **Schedule Generation**: Create time ranges for ON periods

### 4. Raw Schedule Data Structure

#### Input Format (from Tibber)
```json
{
  "schedule": [
    {"time": "2025-09-26T21:00:00.000+02:00", "value": true, "countHours": 5},
    {"time": "2025-09-27T02:00:00.000+02:00", "value": false, "countHours": 4},
    {"time": "2025-09-27T06:00:00.000+02:00", "value": true, "countHours": 10}
  ],
  "hours": [
    {"start": "2025-09-26T21:00:00.000+02:00", "price": 1.0806, "onOff": true},
    {"start": "2025-09-26T22:00:00.000+02:00", "price": 0.6787, "onOff": true},
    {"start": "2025-09-26T23:00:00.000+02:00", "price": 0.5115, "onOff": true}
  ]
}
```

## 5. Current Schedule Conversion

### JavaScript Function Logic
The "Remember current schedule" function node contains:

```javascript
// Parse schedule data from optimization node
var scheduleData = msg.payload.schedule;
var currentTime = new Date();

// Find current schedule window
var currentSchedule = null;
for (var i = 0; i < scheduleData.length; i++) {
  var scheduleStart = new Date(scheduleData[i].time);
  var scheduleEnd = new Date(scheduleStart.getTime() + (scheduleData[i].countHours * 60 * 60 * 1000));

  if (currentTime >= scheduleStart && currentTime < scheduleEnd) {
    currentSchedule = scheduleData[i];
    break;
  }
}

if (currentSchedule) {
  var startTime = new Date(currentSchedule.time);
  var endTime = new Date(startTime.getTime() + (currentSchedule.countHours * 60 * 60 * 1000));
  var startHour = startTime.getHours();
  var endHour = endTime.getHours();

  // Handle midnight boundary (e.g., 21-2 for 21:00-02:00)
  var scheduleString = startHour + "-" + endHour;

  // Set the current_schedule string in global context
  global.set('current_schedule', scheduleString);
}

return msg;
```

### 6. Output Format Examples

#### Example 1: Normal Range
- **Schedule**: 06:00-18:00 ON
- **Output**: `"6-18"`

#### Example 2: Midnight-Spanning Range (Current)
- **Schedule**: 21:00-02:00 ON
- **Output**: `"21-2"`
- **Dashboard Logic**: `hour >= 21 || hour <= 2`

#### Example 3: Multiple Periods
- **Morning**: 06:00-10:00 ON → `"6-10"`
- **Evening**: 16:00-21:00 ON → `"16-21"`
- **Current Period**: Depends on time of day

## 7. Data Validation & Error Handling

### Schedule Validation
```javascript
// Validate schedule exists and has required fields
if (!scheduleData || scheduleData.length === 0) {
  global.set('current_schedule', null);
  return msg;
}

// Ensure time strings are valid ISO format
try {
  new Date(scheduleData[0].time);
} catch (e) {
  node.warn('Invalid time format in schedule data');
  return msg;
}
```

### Price Data Validation
```javascript
// Ensure all required price fields exist
if (!msg.payload.hours || msg.payload.hours.length < 24) {
  node.error('Insufficient price data received from Tibber');
  return null;
}
```

## 8. Integration Points

### A. WebSocket Output
- **Topic**: `temperature_data`
- **Field**: `current_schedule`
- **Format**: String (e.g., "21-2")
- **Update Frequency**: Every time schedule recalculates

### B. Dashboard Consumption
- **File**: `dashboard/src/components/TemperatureWidget.tsx`
- **Parsing**: Regex `/(\d+)-(\d+)/` extracts start/end hours
- **Logic**: Handles midnight-spanning ranges with `||` operator

### C. Time Synchronization
- **Device Clock**: Currently -1 hour offset (Thermiq issue)
- **Compensation**: Dashboard applies fixed offset until device fixed
- **Validation**: Staleness detection based on timestamp comparison

## 9. Debugging & Monitoring

### Key Debug Points
1. **Tibber API Response**: Verify 48-hour price data completeness
2. **Optimization Output**: Check selected hours align with price minimization
3. **Schedule Conversion**: Ensure time boundaries handled correctly
4. **Current Time Detection**: Validate active schedule window identification

### Common Issues
- **Midnight Boundary**: Schedule spans 00:00 requires special handling
- **Price Outliers**: Extremely high prices may force suboptimal scheduling
- **Network Failures**: Missing Tibber data causes schedule gaps
- **Time Zone Changes**: DST transitions require schedule recalculation

---

*Last Updated: 2025-09-26*
*Author: Claude + Fredrik (kimonokittens dashboard development)*