import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  define: {
    // Expose OPENAI_API_KEY from shell environment for local testing
    'import.meta.env.OPENAI_API_KEY': JSON.stringify(process.env.OPENAI_API_KEY || ''),
  },
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
        target: 'http://localhost:3001',
        ws: true,
        changeOrigin: true,
      }
    }
  }
})
