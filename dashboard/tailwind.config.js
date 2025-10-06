/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'storm-blue': {
          50: '#f0f4ff',
          100: '#e0e7ff',
          200: '#c7d2fe',
          300: '#a5b4fc',
          400: '#818cf8',
          500: '#6366f1',
          600: '#4f46e5',
          700: '#4338ca',
          800: '#3730a3',
          900: '#312e81',
          950: '#1e1b4b',
        }
      },
      fontFamily: {
        'sans': ['Galvji', 'sans-serif'],
        'mono': ['JetBrains Mono', 'Menlo', 'Monaco', 'Consolas', 'Liberation Mono', 'Courier New', 'monospace'],
      },
      animation: {
        'dashboard-first': 'dashboard-first 18s ease-in-out infinite',
        'dashboard-second': 'dashboard-second 22s ease-in-out infinite',
        'dashboard-third': 'dashboard-third 20s ease-in-out infinite reverse',
        'dashboard-fourth': 'dashboard-fourth 16s ease-in-out infinite',
        'dashboard-fifth': 'dashboard-fifth 24s ease-in-out infinite',
      }
    },
  },
  plugins: [],
}

