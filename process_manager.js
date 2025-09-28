#!/usr/bin/env node

/**
 * Enhanced Process Manager with Defensive Signal Handling
 *
 * Based on 2024 Node.js best practices for preventing orphaned processes:
 * - Proper SIGINT, SIGTERM, and exit event handling
 * - Child process tracking and cleanup
 * - Graceful shutdown procedures
 * - Process PID management
 */

const { spawn } = require('child_process')
const fs = require('fs')
const path = require('path')

class ProcessManager {
  constructor() {
    this.childProcesses = new Map()
    this.isShuttingDown = false
    this.pidFile = path.join(__dirname, '.process_manager.pid')

    // Track our own PID
    fs.writeFileSync(this.pidFile, process.pid.toString())

    this.setupSignalHandlers()
  }

  setupSignalHandlers() {
    // Handle clean shutdown signals
    ['SIGINT', 'SIGTERM', 'SIGQUIT'].forEach(signal => {
      process.on(signal, () => {
        console.log(`\n📡 Received ${signal} - initiating graceful shutdown...`)
        this.gracefulShutdown(signal)
      })
    })

    // Handle unexpected exits
    process.on('exit', (code) => {
      console.log(`🏁 Process Manager exiting with code ${code}`)
      this.cleanup()
    })

    // Handle uncaught exceptions
    process.on('uncaughtException', (error) => {
      console.error('💥 Uncaught Exception:', error)
      this.gracefulShutdown('UNCAUGHT_EXCEPTION')
    })

    // Handle unhandled promise rejections
    process.on('unhandledRejection', (reason, promise) => {
      console.error('💥 Unhandled Rejection at:', promise, 'reason:', reason)
      this.gracefulShutdown('UNHANDLED_REJECTION')
    })
  }

  spawnProcess(name, command, args = [], options = {}) {
    if (this.isShuttingDown) {
      console.log(`⚠️  Cannot spawn ${name} - shutting down`)
      return null
    }

    console.log(`🚀 Starting ${name}: ${command} ${args.join(' ')}`)

    const child = spawn(command, args, {
      stdio: 'inherit',
      ...options
    })

    // Track the child process
    this.childProcesses.set(name, {
      process: child,
      pid: child.pid,
      command,
      args,
      startTime: Date.now()
    })

    // Handle child process events
    child.on('error', (error) => {
      console.error(`❌ ${name} failed to start:`, error.message)
      this.childProcesses.delete(name)
    })

    child.on('exit', (code, signal) => {
      console.log(`🏁 ${name} exited with code ${code}, signal ${signal}`)
      this.childProcesses.delete(name)

      // If not shutting down and process died unexpectedly, could restart here
      if (!this.isShuttingDown && code !== 0 && !signal) {
        console.log(`⚠️  ${name} died unexpectedly, but not restarting during development`)
      }
    })

    return child
  }

  async gracefulShutdown(reason) {
    if (this.isShuttingDown) {
      console.log('⚠️  Already shutting down...')
      return
    }

    this.isShuttingDown = true
    console.log(`🛑 Graceful shutdown initiated (${reason})`)

    // Kill all child processes
    const shutdownPromises = []

    for (const [name, info] of this.childProcesses) {
      console.log(`🔄 Stopping ${name} (PID: ${info.pid})...`)

      const shutdownPromise = new Promise((resolve) => {
        const timeout = setTimeout(() => {
          console.log(`⚠️  Force killing ${name} (PID: ${info.pid})`)
          try {
            process.kill(info.pid, 'SIGKILL')
          } catch (e) {
            console.log(`   ${name} already dead: ${e.message}`)
          }
          resolve()
        }, 5000) // 5 second timeout

        info.process.on('exit', () => {
          clearTimeout(timeout)
          console.log(`✅ ${name} stopped gracefully`)
          resolve()
        })

        // Send SIGTERM first
        try {
          process.kill(info.pid, 'SIGTERM')
        } catch (e) {
          console.log(`   ${name} already dead: ${e.message}`)
          clearTimeout(timeout)
          resolve()
        }
      })

      shutdownPromises.push(shutdownPromise)
    }

    // Wait for all processes to shut down
    await Promise.all(shutdownPromises)

    console.log('✅ All child processes stopped')
    this.cleanup()

    // Exit with appropriate code
    process.exit(reason.includes('SIG') ? 0 : 1)
  }

  cleanup() {
    // Remove PID file
    try {
      if (fs.existsSync(this.pidFile)) {
        fs.unlinkSync(this.pidFile)
      }
    } catch (e) {
      console.error('Failed to remove PID file:', e.message)
    }
  }

  getStatus() {
    console.log('\n📊 Process Manager Status')
    console.log('========================')
    console.log(`Manager PID: ${process.pid}`)
    console.log(`Active children: ${this.childProcesses.size}`)

    for (const [name, info] of this.childProcesses) {
      const uptime = Math.round((Date.now() - info.startTime) / 1000)
      console.log(`  ${name}: PID ${info.pid}, uptime ${uptime}s`)
    }
    console.log('')
  }
}

// Main execution
if (require.main === module) {
  const manager = new ProcessManager()

  const command = process.argv[2]

  switch (command) {
    case 'start':
      console.log('🎯 Starting development environment with enhanced process management...')

      // Start backend
      manager.spawnProcess('backend', 'ruby', ['puma_server.rb'], {
        env: { ...process.env, PORT: '3001', ENABLE_BROADCASTER: '1' }
      })

      // Start frontend
      manager.spawnProcess('frontend', 'npm', ['run', 'dev'], {
        cwd: path.join(__dirname, 'dashboard'),
        env: { ...process.env }
      })

      // Periodic status check
      const statusInterval = setInterval(() => {
        if (!manager.isShuttingDown) {
          manager.getStatus()
        }
      }, 30000) // Every 30 seconds

      process.on('exit', () => clearInterval(statusInterval))

      break

    case 'status':
      manager.getStatus()
      process.exit(0)
      break

    default:
      console.log('Usage: node process_manager.js [start|status]')
      console.log('')
      console.log('Enhanced process manager with defensive signal handling')
      console.log('Prevents orphaned processes and ensures clean shutdown')
      process.exit(1)
  }
}

module.exports = ProcessManager