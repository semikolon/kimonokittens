import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// Apply kiosk mode (disable scrolling) only in production
if (import.meta.env.PROD) {
  document.body.classList.add('kiosk-mode')
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
