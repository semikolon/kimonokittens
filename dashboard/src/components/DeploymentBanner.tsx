import { useData } from '../context/DataContext'

export function DeploymentBanner() {
  const { state } = useData()
  const { deploymentStatus } = state

  if (!deploymentStatus?.pending) return null

  const timeRemaining = deploymentStatus.time_remaining || 0
  const totalTime = 120 // 2 minutes debounce
  const progress = Math.max(0, Math.min(1, timeRemaining / totalTime))
  const circumference = 2 * Math.PI * 16 // radius = 16
  const strokeDashoffset = circumference * (1 - progress)

  return (
    <div className="fixed bottom-6 right-6 z-50">
      <div className="relative group">
        {/* Circular progress indicator */}
        <svg className="w-12 h-12 -rotate-90" viewBox="0 0 40 40">
          {/* Background circle */}
          <circle
            cx="20"
            cy="20"
            r="16"
            fill="rgba(139, 92, 246, 0.2)"
            stroke="rgba(139, 92, 246, 0.3)"
            strokeWidth="2"
          />
          {/* Progress circle */}
          <circle
            cx="20"
            cy="20"
            r="16"
            fill="none"
            stroke="rgb(168, 85, 247)"
            strokeWidth="3"
            strokeDasharray={circumference}
            strokeDashoffset={strokeDashoffset}
            strokeLinecap="round"
            className="transition-all duration-1000"
          />
        </svg>

        {/* Time text in center */}
        <div className="absolute inset-0 flex items-center justify-center">
          <span className="text-purple-200 text-xs font-medium">
            {Math.ceil(timeRemaining)}s
          </span>
        </div>

        {/* Tooltip on hover */}
        <div className="absolute bottom-full right-0 mb-2 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
          <div className="bg-purple-900/90 text-purple-100 text-xs px-3 py-2 rounded-lg shadow-lg backdrop-blur-sm whitespace-nowrap">
            <div className="font-medium mb-1">Deployment in progress</div>
            {deploymentStatus.commit_sha && (
              <div className="text-purple-300">
                {deploymentStatus.commit_sha.slice(0, 7)}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
