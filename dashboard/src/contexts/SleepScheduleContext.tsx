import React, { createContext, useContext, useEffect, useReducer, useRef } from 'react';

interface SleepScheduleState {
  enabled: boolean;
  sleepTime: string;
  sleepTimeWeekend: string;
  wakeTime: string;
  currentState: 'awake' | 'sleeping' | 'fading-out' | 'fading-in';
  fadeProgress: number;
  brightness: number;
  manualOverride: boolean;
  lastTransitionTime: number;
  monitorPowerControl: boolean;
  brightnessEnabled: boolean;
}

type SleepScheduleAction =
  | { type: 'SET_SLEEP_TIME'; time: string }
  | { type: 'SET_SLEEP_TIME_WEEKEND'; time: string }
  | { type: 'SET_WAKE_TIME'; time: string }
  | { type: 'TOGGLE_ENABLED' }
  | { type: 'SET_STATE'; state: SleepScheduleState['currentState'] }
  | { type: 'SET_FADE_PROGRESS'; progress: number }
  | { type: 'SET_BRIGHTNESS'; brightness: number }
  | { type: 'FORCE_SLEEP' }
  | { type: 'FORCE_WAKE' }
  | { type: 'CLEAR_OVERRIDE' }
  | { type: 'TOGGLE_MONITOR_CONTROL' }
  | { type: 'TOGGLE_BRIGHTNESS' };

interface SleepScheduleContextValue {
  state: SleepScheduleState;
  setSleepTime: (time: string) => void;
  setWakeTime: (time: string) => void;
  toggleEnabled: () => void;
  forceSleep: () => void;
  forceWake: () => void;
  clearOverride: () => void;
  toggleMonitorControl: () => void;
  toggleBrightness: () => void;
}

const DEFAULT_STATE: SleepScheduleState = {
  enabled: true,
  sleepTime: '01:00',
  sleepTimeWeekend: '03:00',
  wakeTime: '05:30',
  currentState: 'awake',
  fadeProgress: 0,
  brightness: 1.0,
  manualOverride: false,
  lastTransitionTime: 0,
  monitorPowerControl: true,
  brightnessEnabled: true,
};

const reducer = (state: SleepScheduleState, action: SleepScheduleAction): SleepScheduleState => {
  switch (action.type) {
    case 'SET_SLEEP_TIME':
      return { ...state, sleepTime: action.time };
    case 'SET_SLEEP_TIME_WEEKEND':
      return { ...state, sleepTimeWeekend: action.time };
    case 'SET_WAKE_TIME':
      return { ...state, wakeTime: action.time };
    case 'TOGGLE_ENABLED':
      return { ...state, enabled: !state.enabled };
    case 'SET_STATE':
      return { ...state, currentState: action.state };
    case 'SET_FADE_PROGRESS':
      return { ...state, fadeProgress: action.progress };
    case 'SET_BRIGHTNESS':
      return { ...state, brightness: action.brightness };
    case 'FORCE_SLEEP':
      return { ...state, manualOverride: true, currentState: 'fading-out' };
    case 'FORCE_WAKE':
      return { ...state, manualOverride: true, currentState: 'fading-in' };
    case 'CLEAR_OVERRIDE':
      return { ...state, manualOverride: false };
    case 'TOGGLE_MONITOR_CONTROL':
      return { ...state, monitorPowerControl: !state.monitorPowerControl };
    case 'TOGGLE_BRIGHTNESS':
      return { ...state, brightnessEnabled: !state.brightnessEnabled };
    default:
      return state;
  }
};

const SleepScheduleContext = createContext<SleepScheduleContextValue | undefined>(undefined);

// Helper: Parse "HH:MM" to decimal hours
const parseTimeString = (timeStr: string): number => {
  const [h, m] = timeStr.split(':').map(Number);
  return h + m / 60;
};

// Helper: Get effective sleep time (weekend vs weekday)
const getEffectiveSleepTime = (state: SleepScheduleState): string => {
  const dayOfWeek = new Date().getDay();
  const isWeekend = dayOfWeek === 5 || dayOfWeek === 6; // Friday or Saturday
  return isWeekend ? state.sleepTimeWeekend : state.sleepTime;
};

// Remote logging helper (outside component to avoid stale closures)
const log = (message: string) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}]`, message);
  fetch('/api/log', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: `[${timestamp}] ${message}` })
  }).catch(() => {}); // Ignore errors
};

export const SleepScheduleProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [state, dispatch] = useReducer(reducer, DEFAULT_STATE);
  const fadeAnimationRef = useRef<number>();

  // Load config from API on mount
  useEffect(() => {
    const loadConfig = async () => {
      try {
        log('[SleepSchedule] Loading config from API...');
        const response = await fetch('/api/sleep/config');
        const result = await response.json();
        log(`[SleepSchedule] API response: ${JSON.stringify(result)}`);

        if (result.success && result.config) {
          const config = result.config;
          log(`[SleepSchedule] Config loaded: sleep=${config.sleepTime} wake=${config.wakeTime} enabled=${config.enabled}`);
          if (config.sleepTime) dispatch({ type: 'SET_SLEEP_TIME', time: config.sleepTime });
          if (config.sleepTimeWeekend) dispatch({ type: 'SET_SLEEP_TIME_WEEKEND', time: config.sleepTimeWeekend });
          if (config.wakeTime) dispatch({ type: 'SET_WAKE_TIME', time: config.wakeTime });
          if (typeof config.enabled === 'boolean' && !config.enabled) {
            dispatch({ type: 'TOGGLE_ENABLED' }); // Toggle if disabled in config
          }
          if (typeof config.monitorPowerControl === 'boolean' && !config.monitorPowerControl) {
            dispatch({ type: 'TOGGLE_MONITOR_CONTROL' }); // Toggle if disabled in config
          }
          if (typeof config.brightnessEnabled === 'boolean' && !config.brightnessEnabled) {
            dispatch({ type: 'TOGGLE_BRIGHTNESS' }); // Toggle if disabled in config
          }
        } else {
          log(`[SleepSchedule] API response invalid: ${JSON.stringify(result)}`);
        }
      } catch (error) {
        log(`[SleepSchedule] Failed to load config: ${error}`);
        // Continue with DEFAULT_STATE
      }
    };

    loadConfig();
  }, []);

  // Calculate adaptive brightness based on time of day
  const calculateBrightness = (hour: number, minute: number): number => {
    const time = hour + minute / 60;

    // Get effective sleep time and parse to decimal hours
    const sleepTimeStr = getEffectiveSleepTime(state);
    const wakeTime = parseTimeString(state.wakeTime);
    const sleepTime = parseTimeString(sleepTimeStr);
    const oneHourBeforeSleep = sleepTime - 1;

    // Wake → 9am: Fade 0.5 → 1.2
    if (wakeTime <= 9) {
      if (time >= wakeTime && time < 9) {
        const duration = 9 - wakeTime;
        return 0.5 + ((time - wakeTime) / duration) * 0.7;
      }
    }

    // 9am → 5pm: Stay at 1.2 (peak brightness)
    if (time >= 9 && time < 17) {
      return 1.2;
    }

    // 5pm → 7pm: Fade 1.2 → 1.0
    if (time >= 17 && time < 19) {
      return 1.2 - ((time - 17) / 2) * 0.2;
    }

    // 7pm → 1hr before sleep: Fade 1.0 → 0.5
    if (sleepTime >= 20) { // Sleep after 8pm (normal case)
      if (time >= 19 && time < oneHourBeforeSleep) {
        const duration = oneHourBeforeSleep - 19;
        return 1.0 - ((time - 19) / duration) * 0.5;
      }

      // 1hr before sleep → sleep: Stay at 0.5
      if (time >= oneHourBeforeSleep && time < sleepTime) {
        return 0.5;
      }
    }

    // Handle early morning hours (after midnight, before wake)
    if (sleepTime < 12) { // Sleep is early morning (like 1am, 2am, etc)
      // Handle crossing midnight: 7pm → midnight
      if (time >= 19) {
        const oneHourBeforeSleep = sleepTime - 1; // Could be 0 or negative for very early sleep
        const fadeEndSameDay = oneHourBeforeSleep <= 0 ? 24 : oneHourBeforeSleep + 24;

        if (time < fadeEndSameDay) {
          // Still in fade period 7pm → 1hr before sleep (or midnight if sleep <= 01:00)
          const duration = fadeEndSameDay - 19;
          return 1.0 - ((time - 19) / duration) * 0.5;
        } else {
          // Last hour before sleep
          return 0.5;
        }
      }

      // Handle early morning: midnight → sleep
      if (time < sleepTime) {
        const effectiveOneHourBeforeSleep = sleepTime - 1;
        if (effectiveOneHourBeforeSleep < 0) {
          // One hour before sleep is yesterday (unusual but handle it)
          return 0.5;
        } else if (time >= effectiveOneHourBeforeSleep) {
          // Last hour before sleep
          return 0.5;
        } else {
          // Between midnight and 1hr before sleep, continue fade
          const fadeStart = 19;
          const totalDuration = (24 - fadeStart) + effectiveOneHourBeforeSleep;
          const elapsed = (24 - fadeStart) + time;
          return 1.0 - (elapsed / totalDuration) * 0.5;
        }
      }
    }

    // During sleep time or between sleep and wake: 0.5
    if (sleepTime < wakeTime) {
      // Normal case: sleep at night, wake in morning (e.g., sleep 1am, wake 5:30am)
      if (time >= sleepTime && time < wakeTime) {
        return 0.5;
      }
    } else {
      // Unusual case: sleep during day, wake at night
      if (time >= sleepTime || time < wakeTime) {
        return 0.5;
      }
    }

    // Default fallback
    return 1.0;
  };

  // Adaptive brightness updater
  useEffect(() => {
    if (!state.enabled || !state.brightnessEnabled || state.currentState === 'sleeping') return;

    const updateBrightness = async () => {
      const now = new Date();
      const targetBrightness = calculateBrightness(now.getHours(), now.getMinutes());

      if (Math.abs(targetBrightness - state.brightness) > 0.01) {
        try {
          const response = await fetch('/api/display/brightness', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ level: targetBrightness }),
          });

          if (response.ok) {
            dispatch({ type: 'SET_BRIGHTNESS', brightness: targetBrightness });
          }
        } catch (error) {
          console.error('Failed to update brightness:', error);
        }
      }
    };

    updateBrightness();
    const interval = setInterval(updateBrightness, 30000); // Every 30 seconds for smooth transitions

    return () => clearInterval(interval);
  }, [state.enabled, state.brightnessEnabled, state.currentState, state.brightness]);

  // Fade-out animation
  const startFadeOut = () => {
    dispatch({ type: 'SET_STATE', state: 'fading-out' });

    const duration = 120000; // 2 minutes
    const startTime = Date.now();

    const animate = () => {
      const elapsed = Date.now() - startTime;
      const progress = Math.min(elapsed / duration, 1);

      dispatch({ type: 'SET_FADE_PROGRESS', progress: progress * 100 });

      if (progress < 1) {
        fadeAnimationRef.current = requestAnimationFrame(animate);
      } else {
        dispatch({ type: 'SET_STATE', state: 'sleeping' });

        // Turn off monitor if enabled
        if (state.monitorPowerControl) {
          fetch('/api/display/power', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'off' }),
          }).catch(error => console.error('Failed to turn off monitor:', error));
        }
      }
    };

    fadeAnimationRef.current = requestAnimationFrame(animate);
  };

  // Fade-in animation
  const startFadeIn = () => {
    // Turn on monitor before fade-in
    if (state.monitorPowerControl) {
      fetch('/api/display/power', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'on' }),
      }).catch(error => console.error('Failed to turn on monitor:', error));
    }

    setTimeout(() => {
      dispatch({ type: 'SET_STATE', state: 'fading-in' });

      const duration = 120000;
      const startTime = Date.now();

      const animate = () => {
        const elapsed = Date.now() - startTime;
        const progress = Math.min(elapsed / duration, 1);

        dispatch({ type: 'SET_FADE_PROGRESS', progress: 100 - (progress * 100) });

        if (progress < 1) {
          fadeAnimationRef.current = requestAnimationFrame(animate);
        } else {
          dispatch({ type: 'SET_STATE', state: 'awake' });
          dispatch({ type: 'SET_FADE_PROGRESS', progress: 0 });
        }
      };

      fadeAnimationRef.current = requestAnimationFrame(animate);
    }, 500); // 500ms delay for monitor wake
  };

  // Schedule checker
  useEffect(() => {
    if (!state.enabled || state.manualOverride) return;

    const checkSchedule = () => {
      const now = new Date();
      const currentTime = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;

      // Get effective sleep time (weekend vs weekday)
      const effectiveSleepTime = getEffectiveSleepTime(state);

      const sleepMatch = currentTime === effectiveSleepTime;
      const wakeMatch = currentTime === state.wakeTime;

      log(`[SleepSchedule] Check: time=${currentTime} sleep=${effectiveSleepTime} wake=${state.wakeTime} state=${state.currentState} enabled=${state.enabled} sleepMatch=${sleepMatch} wakeMatch=${wakeMatch}`);

      if (sleepMatch && state.currentState === 'awake') {
        log('[SleepSchedule] 🌙 TRIGGERING FADE-OUT!');
        startFadeOut();
      }

      if (wakeMatch && state.currentState === 'sleeping') {
        log('[SleepSchedule] ☀️ TRIGGERING FADE-IN!');
        startFadeIn();
      }
    };

    // Check immediately, then sync to minute boundaries by checking every 30s
    // This guarantees we hit the target minute at least twice regardless of start time
    checkSchedule();
    const interval = setInterval(checkSchedule, 30000);

    return () => clearInterval(interval);
  }, [state.enabled, state.sleepTime, state.sleepTimeWeekend, state.wakeTime, state.currentState, state.manualOverride]);

  // Cleanup animation on unmount
  useEffect(() => {
    return () => {
      if (fadeAnimationRef.current) {
        cancelAnimationFrame(fadeAnimationRef.current);
      }
    };
  }, []);

  const value: SleepScheduleContextValue = {
    state,
    setSleepTime: (time: string) => dispatch({ type: 'SET_SLEEP_TIME', time }),
    setWakeTime: (time: string) => dispatch({ type: 'SET_WAKE_TIME', time }),
    toggleEnabled: () => dispatch({ type: 'TOGGLE_ENABLED' }),
    forceSleep: () => {
      if (fadeAnimationRef.current) cancelAnimationFrame(fadeAnimationRef.current);
      startFadeOut();
    },
    forceWake: () => {
      if (fadeAnimationRef.current) cancelAnimationFrame(fadeAnimationRef.current);
      startFadeIn();
    },
    clearOverride: () => dispatch({ type: 'CLEAR_OVERRIDE' }),
    toggleMonitorControl: () => dispatch({ type: 'TOGGLE_MONITOR_CONTROL' }),
    toggleBrightness: () => dispatch({ type: 'TOGGLE_BRIGHTNESS' }),
  };

  return (
    <SleepScheduleContext.Provider value={value}>
      {children}
    </SleepScheduleContext.Provider>
  );
};

export const useSleepSchedule = (): SleepScheduleContextValue => {
  const context = useContext(SleepScheduleContext);
  if (!context) {
    throw new Error('useSleepSchedule must be used within SleepScheduleProvider');
  }
  return context;
};
