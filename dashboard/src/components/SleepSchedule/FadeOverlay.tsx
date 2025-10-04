import React from 'react';
import { useSleepSchedule } from '../../contexts/SleepScheduleContext';
import './FadeOverlay.css';

export const FadeOverlay: React.FC = () => {
  const { state } = useSleepSchedule();

  // Opacity targets:
  // - fading-out: 1 (transitions from 0 to 1)
  // - sleeping: 1 (stays at 1)
  // - fading-in: 0 (transitions from 1 to 0)
  // - awake: 0 (stays at 0)
  const opacity = (state.currentState === 'sleeping' || state.currentState === 'fading-out') ? 1 : 0;
  const hasTransition = state.currentState === 'fading-out' || state.currentState === 'fading-in';

  return (
    <div
      className="sleep-overlay"
      data-sleep-overlay
      style={{
        opacity,
        pointerEvents: state.currentState === 'sleeping' ? 'auto' : 'none',
        transition: hasTransition ? 'opacity 120s cubic-bezier(0.4, 0.0, 0.2, 1)' : 'none',
      }}
      aria-hidden={state.currentState !== 'sleeping'}
    />
  );
};
