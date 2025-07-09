import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5175,
    proxy: {
      '/api': {
        target: 'http://localhost:3001',
        changeOrigin: true,
      },
      '/data': {
        target: 'http://localhost:3001',
        changeOrigin: true,
      },
      '/www': {
        target: 'http://localhost:3001',
        changeOrigin: true,
      },
      '/dashboard/ws': {
        target: 'ws://localhost:3001',
        ws: true,
      }
    }
  }
})
