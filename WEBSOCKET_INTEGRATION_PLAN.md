# WebSocket Integration Plan: Rent & Todo Widgets

## Overview
Integrate RentWidget and TodoWidget into the existing WebSocket architecture to eliminate HTTP fetch requests and create a unified real-time data flow.

## Current State Analysis

### Existing WebSocket System
- **DataBroadcaster** (Ruby): Handles train, weather, temperature, strava data
- **DataContext** (React): WebSocket connection with reconnection logic
- **Widgets**: TrainWidget, WeatherWidget, TemperatureWidget, StravaWidget use `useData()` hook

### Legacy HTTP System
- **RentWidget**: `fetch('/api/rent/friendly_message')` on mount
- **TodoWidget**: `fetch('/api/todos')` on mount with hardcoded fallback

### Architecture Gap
Mixed HTTP/WebSocket approach creates:
- Inconsistent data freshness
- Duplicate connection management
- Per-widget error handling
- No real-time updates for rent/todo

## Implementation Plan

### Phase 1: Backend Integration

#### 1.1 Create Rent Handler
**File**: `handlers/rent_handler.rb`
```ruby
class RentHandler
  def self.get_data
    # Reuse existing /api/rent/friendly_message logic
    # Return structured data matching RentMessageData interface
  end

  def self.broadcast_data
    data = get_data
    DataBroadcaster.publish_message({
      type: "rent_data",
      payload: data,
      timestamp: Time.now.to_i
    })
  end
end
```

#### 1.2 Create Todo Handler
**File**: `handlers/todo_handler.rb`
```ruby
class TodoHandler
  def self.get_data
    # Reuse existing /api/todos logic
    # Include fallback to hardcoded todos on error
    # Return array of {text, id} objects
  end

  def self.broadcast_data
    data = get_data
    DataBroadcaster.publish_message({
      type: "todo_data",
      payload: data,
      timestamp: Time.now.to_i
    })
  end
end
```

#### 1.3 Integrate with DataBroadcaster
**File**: `data_broadcaster.rb`
- Add rent handler to scheduled tasks (every 1 hour)
- Add todo handler to scheduled tasks (every 5 minutes)
- Include in initial broadcasts

### Phase 2: Frontend Integration

#### 2.1 Extend DataContext Types
**File**: `dashboard/src/context/DataContext.tsx`

Add to interfaces:
```typescript
interface RentData {
  message: string
  year: number
  month: number
  generated_at: string
  data_source?: {
    type: 'actual' | 'historical' | 'defaults'
    electricity_source: 'current_bills' | 'historical_lookup' | 'fallback_defaults'
    description_sv: string
  }
}

interface TodoData {
  text: string
  id: string
}

interface DashboardState {
  // existing fields...
  rentData: RentData | null
  todoData: TodoData[] | null
  lastUpdated: {
    // existing fields...
    rent: number | null
    todo: number | null
  }
}
```

#### 2.2 Add Action Types and Reducer Cases
```typescript
type DashboardAction =
  // existing actions...
  | { type: 'SET_RENT_DATA'; payload: RentData }
  | { type: 'SET_TODO_DATA'; payload: TodoData[] }

// Add reducer cases for SET_RENT_DATA and SET_TODO_DATA
```

#### 2.3 Add WebSocket Message Handling
```typescript
switch (message.type) {
  // existing cases...
  case 'rent_data':
    dispatch({ type: 'SET_RENT_DATA', payload: message.payload })
    break
  case 'todo_data':
    dispatch({ type: 'SET_TODO_DATA', payload: message.payload })
    break
}
```

### Phase 3: Widget Refactoring

#### 3.1 Refactor RentWidget
**File**: `dashboard/src/components/RentWidget.tsx`

**Before**: 95 lines with fetch, loading, error states
**After**: ~40 lines using useData() hook

```typescript
export function RentWidget() {
  const { state } = useData()
  const { rentData, connectionStatus } = state

  // Remove: useState, useEffect, fetch logic
  // Keep: parsing and rendering logic
  // Add: simple connection-based error states
}
```

#### 3.2 Refactor TodoWidget
**File**: `dashboard/src/components/TodoWidget.tsx`

**Before**: 82 lines with fetch, loading, fallback
**After**: ~30 lines using useData() hook

```typescript
export function TodoWidget() {
  const { state } = useData()
  const { todoData, connectionStatus } = state

  // Remove: useState, useEffect, fetch logic
  // Keep: rendering logic
  // Add: simple connection-based error states
}
```

### Phase 4: App.tsx Widget Visibility Logic

#### 4.1 Update BackendDataWidgets Conditional
```typescript
function BackendDataWidgets() {
  const { state } = useData()
  const { connectionStatus, trainData, temperatureData, weatherData, stravaData, rentData, todoData } = state

  const isConnected = connectionStatus === 'open'
  const hasAnyData = trainData || temperatureData || weatherData || stravaData || rentData || todoData

  // Now includes rentData and todoData in visibility logic
}
```

## Performance Impact Analysis

### Before Integration
- **RentWidget**: HTTP request on every mount (network overhead)
- **TodoWidget**: HTTP request on every mount (network overhead)
- **Total**: 2 HTTP requests per page load/refresh

### After Integration
- **RentWidget**: Uses existing WebSocket data (zero additional overhead)
- **TodoWidget**: Uses existing WebSocket data (zero additional overhead)
- **Total**: 0 additional HTTP requests

### WebSocket Message Overhead
- **Rent data**: ~500 bytes every hour = 43KB/day
- **Todo data**: ~200 bytes every 5 minutes = 58KB/day
- **Total additional**: ~100KB/day (negligible)

**Net benefit**: Eliminate HTTP request overhead in favor of tiny WebSocket messages

## Testing Strategy

### 1. Backend Testing
- Verify rent handler produces correct data format
- Verify todo handler produces correct data format
- Test DataBroadcaster includes new message types
- Test scheduled broadcasting intervals

### 2. Frontend Testing
- Test DataContext receives and stores new data types
- Test widgets render correctly with WebSocket data
- Test widget behavior when disconnected/reconnected
- Test no HTTP requests are made after refactor

### 3. Integration Testing
- Full end-to-end: backend broadcast → frontend display
- Test error scenarios (malformed data, connection drops)
- Performance testing (message frequency impact)

## Rollback Plan

### If Issues Arise
1. **Quick rollback**: Revert widget files to HTTP fetch versions
2. **Backend**: Comment out new handlers in DataBroadcaster
3. **Frontend**: Remove new message types from DataContext
4. **Full rollback**: Git revert integration commits

### Rollback Triggers
- Significant performance degradation
- Data consistency issues
- WebSocket message size concerns
- Connection stability problems

## Success Metrics

### Technical Metrics
- ✅ Zero HTTP requests from RentWidget/TodoWidget
- ✅ All 6 data types in single WebSocket stream
- ✅ Consistent widget behavior (all use useData())
- ✅ Real-time updates for rent/todo changes

### UX Metrics
- ✅ Widgets appear/disappear consistently when backend connects/disconnects
- ✅ No stale data (all widgets update via broadcast)
- ✅ Faster initial load (no HTTP fetch delays)

## Implementation Timeline

### Estimated Effort
- **Phase 1 (Backend)**: 30 minutes
- **Phase 2 (DataContext)**: 20 minutes
- **Phase 3 (Widgets)**: 45 minutes
- **Phase 4 (App logic)**: 10 minutes
- **Testing**: 30 minutes
- **Total**: ~2.5 hours

### Dependencies
- Must have backend server running for testing
- Frontend dev server for real-time testing
- Both systems needed for full integration testing

## File Changes Summary

### New Files
- `handlers/rent_handler.rb`
- `handlers/todo_handler.rb`

### Modified Files
- `data_broadcaster.rb` (add new handlers)
- `dashboard/src/context/DataContext.tsx` (extend types, add message handling)
- `dashboard/src/components/RentWidget.tsx` (refactor to WebSocket)
- `dashboard/src/components/TodoWidget.tsx` (refactor to WebSocket)
- `dashboard/src/App.tsx` (update visibility logic)

### Removed Dependencies
- HTTP fetch calls in RentWidget
- HTTP fetch calls in TodoWidget
- Per-widget error handling and loading states

## Post-Integration Benefits

### Developer Experience
- Single data flow pattern across all widgets
- Centralized connection management
- Easier debugging (all data in WebSocket traffic)
- No more mixed HTTP/WebSocket architecture

### User Experience
- Consistent widget behavior
- Real-time updates for all data types
- Faster page loads (no HTTP fetch delays)
- Better error handling (unified connection status)

### System Architecture
- Pure WebSocket-based dashboard
- Eliminated architectural debt
- Scalable pattern for future widgets
- Simplified testing and monitoring

## Next Steps After Integration

1. **Monitor Performance**: Track WebSocket message frequency and size
2. **Consider Optimization**: Batch multiple data types in single messages if needed
3. **Future Widgets**: Use WebSocket pattern as template
4. **Documentation**: Update system architecture docs

---

**Ready to implement**: This plan provides comprehensive coverage of the integration with clear rollback options and success metrics.