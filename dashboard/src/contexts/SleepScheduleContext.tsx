import React, { createContext, useContext, useEffect, useReducer, useRef } from 'react';

interface SleepScheduleState {
  enabled: boolean;
  sleepTime: string;
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
  wakeTime: '05:30',
  currentState: 'awake',
  fadeProgress: 0,
  brightness: 1.0,
  manualOverride: false,
  lastTransitionTime: 0,
  monitorPowerControl: true,
  brightnessEnabled: true,
};

const STORAGE_KEY = 'sleepSchedule';

// Load from localStorage
const loadState = (): SleepScheduleState => {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      const parsed = JSON.parse(saved);
      return { ...DEFAULT_STATE, ...parsed };
    }
  } catch (error) {
    console.error('Failed to load sleep schedule state:', error);
  }
  return DEFAULT_STATE;
};

// Save to localStorage
const saveState = (state: SleepScheduleState) => {
  try {
    const toSave = {
      enabled: state.enabled,
      sleepTime: state.sleepTime,
      wakeTime: state.wakeTime,
      manualOverride: state.manualOverride,
      monitorPowerControl: state.monitorPowerControl,
      brightnessEnabled: state.brightnessEnabled,
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(toSave));
  } catch (error) {
    console.error('Failed to save sleep schedule state:', error);
  }
};

const reducer = (state: SleepScheduleState, action: SleepScheduleAction): SleepScheduleState => {
  switch (action.type) {
    case 'SET_SLEEP_TIME':
      return { ...state, sleepTime: action.time };
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

export const SleepScheduleProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [state, dispatch] = useReducer(reducer, DEFAULT_STATE, loadState);
  const fadeAnimationRef = useRef<number>();

  // Save to localStorage on state changes
  useEffect(() => {
    saveState(state);
  }, [state.enabled, state.sleepTime, state.wakeTime, state.manualOverride, state.monitorPowerControl, state.brightnessEnabled]);

  // Calculate adaptive brightness based on time of day
  const calculateBrightness = (hour: number, minute: number): number => {
    const time = hour + minute / 60;

    // Morning: 6am-12pm (1.0 → 1.4)
    if (time >= 6 && time < 12) {
      return 1.0 + ((time - 6) / 6) * 0.4;
    }

    // Afternoon: 12pm-6pm (1.4 → 1.2)
    if (time >= 12 && time < 18) {
      return 1.4 - ((time - 12) / 6) * 0.2;
    }

    // Evening: 6pm-10pm (1.2 → 0.9)
    if (time >= 18 && time < 22) {
      return 1.2 - ((time - 18) / 4) * 0.3;
    }

    // Night: 10pm-1am (0.9 → 0.7)
    if (time >= 22 || time < 1) {
      const nightTime = time >= 22 ? time - 22 : time + 2;
      return 0.9 - (nightTime / 3) * 0.2;
    }

    // Dawn: 5:30am-6am (0.7 → 1.0)
    if (time >= 5.5 && time < 6) {
      return 0.7 + ((time - 5.5) / 0.5) * 0.3;
    }

    // Default
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
    const interval = setInterval(updateBrightness, 60000); // Every minute

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

      if (currentTime === state.sleepTime && state.currentState === 'awake') {
        startFadeOut();
      }

      if (currentTime === state.wakeTime && state.currentState === 'sleeping') {
        startFadeIn();
      }
    };

    checkSchedule();
    const interval = setInterval(checkSchedule, 60000);

    return () => clearInterval(interval);
  }, [state.enabled, state.sleepTime, state.wakeTime, state.currentState, state.manualOverride]);

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
