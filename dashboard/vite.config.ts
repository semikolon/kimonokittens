import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'
import { resolve } from 'path'

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
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        signup: resolve(__dirname, 'signup.html')
      },
      output: {
        // Put signup bundle at root (not in nested dir)
        entryFileNames: (chunkInfo) => {
          return chunkInfo.name === 'signup'
            ? 'assets/signup-[hash].js'
            : 'assets/[name]-[hash].js'
        }
      }
    }
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
