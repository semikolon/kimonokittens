import React from 'react';
import { useSleepSchedule } from '../../contexts/SleepScheduleContext';
import './FadeOverlay.css';

export const FadeOverlay: React.FC = () => {
  const { state } = useSleepSchedule();

  const opacity = state.fadeProgress / 100;
  const isFullySleeping = state.currentState === 'sleeping';
  const isFading = state.currentState === 'fading-out' || state.currentState === 'fading-in';

  return (
    <div
      className="sleep-overlay"
      style={{
        opacity,
        pointerEvents: isFullySleeping ? 'auto' : 'none',
        transition: isFading ? 'opacity 120s cubic-bezier(0.4, 0.0, 0.2, 1)' : 'none',
      }}
      aria-hidden={!isFullySleeping}
    />
  );
};
