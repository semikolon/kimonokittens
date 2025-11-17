import React from 'react'
import ReactDOM from 'react-dom/client'
import SignupPage from './pages/SignupPage'
import './index.css'  // Shared styles (gradient blobs, etc.)

ReactDOM.createRoot(document.getElementById('signup-root')!).render(
  <React.StrictMode>
    <SignupPage />
  </React.StrictMode>,
)
